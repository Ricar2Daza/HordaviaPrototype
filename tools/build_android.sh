#!/usr/bin/env bash
# Compila un APK Android debug para probar en dispositivo.
# Requisitos: Godot 4.7 + export templates 4.7, Android SDK 36 y JDK 17/21.
# Uso: bash tools/build_android.sh [--release]
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-${GODOT_BIN:-./Godot_v4.7-stable_linux.x86_64}}"
if [ ! -x "$GODOT" ]; then
  echo "No se encontró el binario de Godot: $GODOT" >&2
  exit 1
fi

if [ -n "${GODOT_EXPORT_TEMPLATES:-}" ]; then
  TEMPLATES="$GODOT_EXPORT_TEMPLATES"
else
  version="$("$GODOT" --version 2>/dev/null | head -1 | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
  [ -n "$version" ] || version="4.7"
  TEMPLATES="$HOME/.local/share/godot/export_templates/${version}.stable"
fi
if [ ! -d "$TEMPLATES" ] || [ -z "$(ls -A "$TEMPLATES" 2>/dev/null)" ]; then
  echo "Faltan las export templates en: $TEMPLATES" >&2
  echo "Instálalas en el editor: Editor > Gestionar plantillas de exportación." >&2
  echo "Alternativa: define GODOT_EXPORT_TEMPLATES con la ruta correcta." >&2
  exit 1
fi

mkdir -p build
"$GODOT" --headless --path . --export-debug "Android" build/Hordavia-debug.apk
sha256sum build/Hordavia-debug.apk > build/Hordavia-debug.apk.sha256
echo "APK debug: build/Hordavia-debug.apk"
echo "Instalar: adb install -r build/Hordavia-debug.apk"
echo "Logs:     adb logcat -s godot:V"

if [ "${1:-}" = "--release" ]; then
  "$GODOT" --headless --path . --export-release "Android" build/Hordavia.apk
  sha256sum build/Hordavia.apk > build/Hordavia.apk.sha256
  echo "APK release: build/Hordavia.apk (requiere keystore de release configurado)"
fi
