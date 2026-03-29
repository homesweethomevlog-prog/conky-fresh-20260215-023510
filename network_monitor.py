#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from pathlib import Path

STATE_PATH = Path('/tmp/conky_network_state.json')
MIN_SAMPLE_INTERVAL = 0.8
MIN_DOWN_GRAPH_KIB = 256.0
MIN_UP_GRAPH_KIB = 64.0
PEAK_DECAY = 0.92


def run_command(args: list[str]) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ''


def detect_interface() -> str:
    default_route = run_command(['ip', '-o', 'route', 'show', 'to', 'default'])
    if default_route:
        parts = default_route.split()
        for idx, token in enumerate(parts):
            if token == 'dev' and idx + 1 < len(parts):
                return parts[idx + 1]

    net_dir = Path('/sys/class/net')
    for iface_dir in sorted(net_dir.iterdir()):
        iface = iface_dir.name
        if iface == 'lo':
            continue
        operstate = (iface_dir / 'operstate').read_text().strip() if (iface_dir / 'operstate').exists() else 'down'
        if operstate == 'up':
            return iface
    return ''


def interface_type(iface: str) -> str:
    if not iface:
        return 'Disconnected'
    if Path(f'/sys/class/net/{iface}/wireless').exists():
        return 'Wi-Fi'
    return 'Wired'


def carrier_state(iface: str) -> str:
    carrier = Path(f'/sys/class/net/{iface}/carrier')
    if carrier.exists():
        return 'Connected' if carrier.read_text().strip() == '1' else 'Disconnected'
    return 'Unknown'


def ipv4_address(iface: str) -> str:
    output = run_command(['ip', '-o', '-4', 'addr', 'show', 'dev', iface, 'scope', 'global'])
    if not output:
        return 'No IP'
    for part in output.split():
        if '/' in part and part[0].isdigit():
            return part.split('/')[0]
    return 'No IP'


def wifi_ssid(iface: str) -> str:
    return run_command(['iwgetid', iface, '-r'])


def read_bytes(iface: str) -> tuple[int, int]:
    rx_path = Path(f'/sys/class/net/{iface}/statistics/rx_bytes')
    tx_path = Path(f'/sys/class/net/{iface}/statistics/tx_bytes')
    if not rx_path.exists() or not tx_path.exists():
        return (0, 0)
    return (int(rx_path.read_text().strip()), int(tx_path.read_text().strip()))


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {}
    try:
        return json.loads(STATE_PATH.read_text())
    except Exception:
        return {}


def save_state(state: dict) -> None:
    try:
        STATE_PATH.write_text(json.dumps(state))
    except Exception:
        pass


def graph_percent(value_kib: float, peak_kib: float, minimum_peak_kib: float) -> tuple[float, float]:
    next_peak = max(value_kib, minimum_peak_kib, peak_kib * PEAK_DECAY)
    if next_peak <= 0:
        return (0.0, minimum_peak_kib)
    return (min((value_kib / next_peak) * 100.0, 100.0), next_peak)


def sample_speeds(iface: str) -> tuple[float, float]:
    if not iface:
        return (0.0, 0.0)

    now = time.time()
    rx_now, tx_now = read_bytes(iface)

    state = load_state()
    prev = state.get(iface, {})

    down_kib = float(prev.get('down_kib', 0.0))
    up_kib = float(prev.get('up_kib', 0.0))
    prev_t = float(prev.get('t', 0.0))
    down_peak_kib = float(prev.get('down_peak_kib', MIN_DOWN_GRAPH_KIB))
    up_peak_kib = float(prev.get('up_peak_kib', MIN_UP_GRAPH_KIB))

    sample_t = prev_t
    sample_rx = int(prev.get('rx', rx_now))
    sample_tx = int(prev.get('tx', tx_now))

    if prev_t <= 0:
        sample_t = now
        sample_rx = rx_now
        sample_tx = tx_now
    else:
        dt = max(now - prev_t, 0.001)
        if dt >= MIN_SAMPLE_INTERVAL:
            down_kib = max((rx_now - sample_rx) / 1024.0 / dt, 0.0)
            up_kib = max((tx_now - sample_tx) / 1024.0 / dt, 0.0)
            sample_t = now
            sample_rx = rx_now
            sample_tx = tx_now

    _, down_peak_kib = graph_percent(down_kib, down_peak_kib, MIN_DOWN_GRAPH_KIB)
    _, up_peak_kib = graph_percent(up_kib, up_peak_kib, MIN_UP_GRAPH_KIB)

    state[iface] = {
        'rx': sample_rx,
        'tx': sample_tx,
        't': sample_t,
        'down_kib': down_kib,
        'up_kib': up_kib,
        'down_peak_kib': down_peak_kib,
        'up_peak_kib': up_peak_kib,
    }
    save_state(state)

    return (down_kib, up_kib)


def speed_text(iface: str) -> str:
    down_kib, up_kib = sample_speeds(iface)
    return f'Down: {down_kib:.1f} KiB/s  Up: {up_kib:.1f} KiB/s'


def graph_value_text(iface: str, direction: str) -> str:
    down_kib, up_kib = sample_speeds(iface)
    state = load_state().get(iface, {})

    if direction == 'down':
        percent, _ = graph_percent(down_kib, float(state.get('down_peak_kib', MIN_DOWN_GRAPH_KIB)), MIN_DOWN_GRAPH_KIB)
    else:
        percent, _ = graph_percent(up_kib, float(state.get('up_peak_kib', MIN_UP_GRAPH_KIB)), MIN_UP_GRAPH_KIB)

    return f'{percent:.2f}'


def summary_line(iface: str) -> str:
    if not iface:
        return 'Network: Disconnected'
    net_type = interface_type(iface)
    return f'Network: {net_type} ({iface})'


def details_line(iface: str) -> str:
    if not iface:
        return 'IP: No network'

    net_type = interface_type(iface)
    ip_addr = ipv4_address(iface)

    if net_type == 'Wi-Fi':
        ssid = wifi_ssid(iface)
        ssid_text = f'SSID: {ssid}' if ssid else 'SSID: Unknown'
        return f'{ssid_text}  IP: {ip_addr}'

    status = carrier_state(iface)
    return f'Link: {status}  IP: {ip_addr}'


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else 'summary'
    iface = detect_interface()

    if mode == 'summary':
        print(summary_line(iface))
    elif mode == 'details':
        print(details_line(iface))
    elif mode == 'speed':
        print(speed_text(iface))
    elif mode == 'down_pct':
        print(graph_value_text(iface, 'down'))
    elif mode == 'up_pct':
        print(graph_value_text(iface, 'up'))
    else:
        print('Network: Unknown mode')


if __name__ == '__main__':
    main()
