#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/.conky"
GENERATED_DIR="$BASE_DIR/.generated"

detect_interface() {
  local iface

  iface="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
  if [[ -n "$iface" ]]; then
    printf '%s\n' "$iface"
    return 0
  fi

  iface="$(ip -o link show 2>/dev/null | awk -F': ' '$2 != "lo" {print $2}' | sed 's/@.*//' | head -n 1)"
  if [[ -n "$iface" ]]; then
    printf '%s\n' "$iface"
    return 0
  fi

  printf 'lo\n'
}

render_main_config() {
  local iface rendered_config

  iface="$(detect_interface)"
  rendered_config="$GENERATED_DIR/conky.conf"
  mkdir -p "$GENERATED_DIR"
  sed "s/__NET_IFACE__/$iface/g" "$BASE_DIR/conky.conf" > "$rendered_config"
  printf '%s\n' "$rendered_config"
}

start_if_missing() {
  local cfg="$1"
  pkill -f "conky -c ${cfg}" >/dev/null 2>&1 || true
  /usr/bin/conky -c "$cfg" -d
}

# Disabled for now: keep the main right-side panel config available,
# but do not start it automatically.
# start_if_missing "$(render_main_config)"
start_if_missing "$BASE_DIR/conky_calendar.conf"
start_if_missing "$BASE_DIR/conky_dashboard.conf"
start_if_missing "$BASE_DIR/conky_weather.conf"
