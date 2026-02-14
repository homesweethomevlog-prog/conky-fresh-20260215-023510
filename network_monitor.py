#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from pathlib import Path

STATE_PATH = Path('/tmp/conky_network_state.json')


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


def speed_text(iface: str) -> str:
    if not iface:
        return 'Down: 0.0 KiB/s  Up: 0.0 KiB/s'

    now = time.time()
    rx_now, tx_now = read_bytes(iface)

    state = load_state()
    prev = state.get(iface)

    down_kib = 0.0
    up_kib = 0.0
    if prev:
        dt = max(now - float(prev.get('t', now)), 0.001)
        rx_prev = int(prev.get('rx', rx_now))
        tx_prev = int(prev.get('tx', tx_now))
        down_kib = max((rx_now - rx_prev) / 1024.0 / dt, 0.0)
        up_kib = max((tx_now - tx_prev) / 1024.0 / dt, 0.0)

    state[iface] = {'rx': rx_now, 'tx': tx_now, 't': now}
    save_state(state)

    return f'Down: {down_kib:.1f} KiB/s  Up: {up_kib:.1f} KiB/s'


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
    else:
        print('Network: Unknown mode')


if __name__ == '__main__':
    main()
