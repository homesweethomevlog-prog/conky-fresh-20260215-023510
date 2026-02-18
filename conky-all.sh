#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/.config/conky"

start_if_missing() {
  local cfg="$1"
  pkill -f "conky -c ${cfg}" >/dev/null 2>&1 || true
  /usr/bin/conky -c "$cfg" -d
}

start_if_missing "$BASE_DIR/conky.conf"
start_if_missing "$BASE_DIR/conky_calendar.conf"
start_if_missing "$BASE_DIR/conky_weather.conf"
