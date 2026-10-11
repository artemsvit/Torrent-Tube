#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
case "$mode" in
  run|--verify|--debug|--logs|--telemetry) ;;
  *) echo 'Usage: build_and_run.sh [--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${TORRENTTUBE_MAC_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/TorrentTubeMacLocal}"
app_name='Torrent Tube'
pkill -x "$app_name" >/dev/null 2>&1 || true
xcodebuild -project "$task_root/appletv/TorrentTubeTV.xcodeproj" -scheme TorrentTubeMac \
  -destination 'platform=macOS' -derivedDataPath "$build_dir" -allowProvisioningUpdates build
app_bundle="$build_dir/Build/Products/Debug/$app_name.app"
if [[ "$mode" == '--debug' ]]; then
  exec lldb "$app_bundle/Contents/MacOS/$app_name"
fi
open -n "$app_bundle"
case "$mode" in
  --verify) sleep 1; pgrep -x "$app_name" >/dev/null ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "Torrent Tube"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.artsvit.torrenttube.mac"' ;;
esac
