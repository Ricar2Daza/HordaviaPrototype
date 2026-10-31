#!/usr/bin/env bash
# Comprueba el layout táctil en 3 tamaños sin necesidad de display.
# Uso: bash tools/check_layouts.sh   (GODOT=... para otro binario)
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-${GODOT_BIN:-./Godot_v4.7-stable_linux.x86_64}}"
if [ ! -x "$GODOT" ]; then
  echo "No se encontró el binario de Godot: $GODOT" >&2
  exit 1
fi

fail=0
for res in 960x540 1280x720 1920x1080; do
  log="$(mktemp)"
  if ! HORDAVIA_LAYOUT_TEST=1 HORDAVIA_LAYOUT_SIZE="$res" \
      timeout 45 "$GODOT" --headless --path . --quit-after 45 >"$log" 2>&1; then
    echo "LAYOUT_FAIL $res (Godot terminó con error)" >&2
    tail -40 "$log" >&2
    fail=1
    rm -f "$log"
    continue
  fi
  line="$(grep "LAYOUT viewport=" "$log" | head -1 || true)"
  if echo "$line" | grep -q "ok=true"; then
    echo "LAYOUT_OK $res :: $line"
  else
    echo "LAYOUT_FAIL $res" >&2
    tail -40 "$log" >&2
    fail=1
  fi
  rm -f "$log"
done

exit "$fail"
