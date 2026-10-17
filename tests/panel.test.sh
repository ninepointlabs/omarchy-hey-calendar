#!/bin/bash
# The panel's About page, in a real Quickshell.
# Usage: tests/panel.test.sh
#
# Loads BarWidget.qml -> Panel.qml -> Service.qml from a scratch copy of this
# checkout with the installed shell's Ui/ and Commons/, through the harness in
# tests/qml/PanelHarness.qml. `hey` is a stub on PATH (tests/fixtures/hey) that
# answers with empty data, so no real HEY account is read or changed; HOME is
# a scratch directory, shell.json writes are recorded by the harness, never
# made, and the run is in a network namespace (unshare -Urn).
#
# It needs the Wayland session: the panel opens briefly on screen. Leave the
# mouse alone while it runs; a click elsewhere can dismiss the panel.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_SRC="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

skip() { printf 'skip panel tests (%s)\n' "$1"; exit 0; }
command -v qs >/dev/null || skip "qs not installed"
command -v jq >/dev/null || skip "jq not installed"
[ -d "$SHELL_SRC/Ui" ] && [ -d "$SHELL_SRC/Commons" ] || skip "no Omarchy shell at $SHELL_SRC"
[ -n "${WAYLAND_DISPLAY:-}" ] || skip "no Wayland session"
unshare -Urn true 2>/dev/null || skip "unshare -Urn unavailable"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root" "$work/plugin" "$work/home" "$work/bin"

# qs resolves qs.Ui / qs.Commons relative to the config root.
cp -r "$SHELL_SRC/Ui" "$SHELL_SRC/Commons" "$work/root/"
cp "$ROOT/tests/qml/PanelHarness.qml" "$work/root/shell.qml"
# The version check follows manifest.json, so a release bump doesn't break it.
version_re=$(jq -r .version "$ROOT/manifest.json" | sed 's/\./\\\\./g')
sed -i "s/@MANIFEST_VERSION_RE@/$version_re/" "$work/root/shell.qml"
cp "$ROOT"/*.qml "$ROOT"/*.js "$ROOT/manifest.json" "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$work/plugin/"
cp "$ROOT/tests/fixtures/hey" "$work/bin/hey"
chmod +x "$work/bin/hey"

HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_STATE_HOME="$work/home/.local/state" \
  XDG_CACHE_HOME="$work/home/.cache" PATH="$work/bin:$PATH" HEY_STUB_LOG="$work/hey.log" \
  HEY_CALENDAR_PLUGIN="$work/plugin" \
  unshare -Urn timeout 60 qs --no-color -p "$work/root/shell.qml" >"$work/log" 2>&1
rc=$?

line=$(grep -o 'RESULT .*' "$work/log" | tail -1)
if [ -z "$line" ]; then
  printf 'FAIL harness produced no result (qs exit %d). Log tail:\n' "$rc"
  tail -30 "$work/log"
  exit 1
fi

warnings=$(grep -E 'WARN|ERROR' "$work/log" | grep -v 'qt\.qpa\.' | grep -v 'RESULT ')
json=${line#RESULT }
echo "$json" | jq -r '.[] | if .ok then "ok   " + .name else "FAIL " + .name + " -- " + .detail end'
pass=$(echo "$json" | jq '[.[] | select(.ok)] | length')
failn=$(echo "$json" | jq '[.[] | select(.ok | not)] | length')
if [ -n "$warnings" ]; then
  failn=$((failn + 1))
  printf 'FAIL QML warnings:\n%s\n' "$warnings"
fi
# The About page itself runs nothing: only the probe and read-only calls.
if grep -vE '^(--version|auth status --json|calendar list --json|(event|journal) list .*--json|journal read .* --json)$' "$work/hey.log" | grep -q .; then
  failn=$((failn + 1))
  printf 'FAIL unexpected hey calls:\n%s\n' "$(cat "$work/hey.log")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$failn"
[ "$failn" -eq 0 ]
