#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME_DIR=$(mktemp -d /tmp/ephemera-panel-qml-test.XXXXXX)
trap 'rm -rf "$RUNTIME_DIR"' EXIT
chmod 700 "$RUNTIME_DIR"

if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ] \
        || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    printf '%s\n' "EPHEMERA_PANEL_QML_TEST SKIP: a running Wayland compositor is required"
    exit 77
fi

CONFIG_DIR="$RUNTIME_DIR/config"
mkdir -p "$CONFIG_DIR/src/components" "$CONFIG_DIR/Common" "$CONFIG_DIR/Services"
cp "$ROOT/tests/EphemeraPanelHarness.qml" "$CONFIG_DIR/EphemeraPanelHarness.qml"
cp "$ROOT/src/components/EphemeraPanel.qml" "$CONFIG_DIR/src/components/EphemeraPanel.qml"
cp "$ROOT/tests/fixtures/qml/Common/"* "$CONFIG_DIR/Common/"
cp "$ROOT/tests/fixtures/qml/Services/"* "$CONFIG_DIR/Services/"

output=$(QT_QPA_PLATFORM=wayland \
    QS_NO_RELOAD_POPUP=1 \
    DMS_DISABLE_LAYER=1 \
    timeout 8s qs -p "$CONFIG_DIR/EphemeraPanelHarness.qml" 2>&1) || {
    printf '%s\n' "$output"
    exit 1
}

printf '%s\n' "$output"
printf '%s\n' "$output" | grep -Fq "EPHEMERA_PANEL_QML_TEST PASS"
