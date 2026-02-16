#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/.config/conky"

start_if_missing() {
  local cfg="$1"
  if ! pgrep -af "conky -c ${cfg}" >/dev/null; then
    conky -c "$cfg" -d
  fi
}

start_if_missing "$BASE_DIR/conky.conf"
start_if_missing "$BASE_DIR/conky_calendar.conf"
start_if_missing "$BASE_DIR/conky_weather.conf"
