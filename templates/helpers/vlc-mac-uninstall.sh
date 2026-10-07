#!/bin/sh
# Torrent Tube - remove the VLC helper from this Mac.
#
#   curl -fsSL "{{ origin }}/helper/vlc-mac-uninstall.sh" | sh
#
# Takes the helper app out of ~/Applications and out of macOS's list of
# link handlers. VLC itself is left alone.

ORIGIN="{{ origin }}"
APP="$HOME/Applications/Torrent Tube VLC Helper.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ -d "$APP" ]; then
  "$LSREGISTER" -u "$APP" 2>/dev/null
  rm -rf "$APP"
  echo "Done: the Torrent Tube VLC helper is removed. VLC itself is still installed."
else
  echo "The Torrent Tube VLC helper isn't installed on this Mac."
fi
{% if key %}
# Tell the Torrent Tube page, so Settings > Players can show it at once.
curl -fsS -X POST -d "removed=1" "$ORIGIN/api/helper/{{ key }}" >/dev/null 2>&1 || true
{% endif %}
