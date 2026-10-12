#!/bin/sh
# Torrent Tube - VLC helper for macOS.
#
# Teaches this Mac that torrenttube-vlc: links open in VLC, so "Play in VLC"
# on {{ origin }} starts VLC straight away, like "Play in Infuse".
# The helper is built here (not downloaded as an app), so Gatekeeper has
# nothing to quarantine. It only opens play links from {{ origin }}.
#
#   Install:    curl -fsSL "{{ origin }}/helper/vlc-mac.sh" | sh
#   Uninstall:  rm -rf ~/Applications/"Torrent Tube VLC Helper.app"
set -e

ORIGIN="{{ origin }}"
APP="$HOME/Applications/Torrent Tube VLC Helper.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Is VLC here? (Spotlight finds it wherever it's installed.) Reported to
# the page, which can't see installed apps itself.
VLC_FOUND=0
if [ -d /Applications/VLC.app ] || [ -d "$HOME/Applications/VLC.app" ] \
   || [ -n "$(mdfind "kMDItemCFBundleIdentifier == 'org.videolan.vlc'" 2>/dev/null | head -1)" ]; then
  VLC_FOUND=1
else
  echo "Note: VLC isn't installed yet - get it from https://www.videolan.org/vlc/"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/helper.applescript" <<'APPLESCRIPT'
property linkPrefix : "torrenttube-vlc:"
property allowedOrigin : "{{ origin }}/"

on open location theURL
	if theURL does not start with linkPrefix then return
	set target to text ((length of linkPrefix) + 1) thru -1 of theURL
	if not (target starts with (allowedOrigin & "play/") or target starts with (allowedOrigin & "playlist/") or target starts with (allowedOrigin & "media/")) then return
	try
		do shell script "open -a VLC " & quoted form of target
	on error
		display dialog "VLC isn't installed. Get it from videolan.org, then press Play again." buttons {"OK"} default button 1 with title "Torrent Tube"
	end try
end open location

on run
	display dialog "Torrent Tube VLC Helper is installed. \"Play in VLC\" now opens films in VLC." buttons {"OK"} default button 1 with title "Torrent Tube"
end run
APPLESCRIPT

mkdir -p "$HOME/Applications"
rm -rf "$APP"
osacompile -o "$APP" "$TMP/helper.applescript"

PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "local.torrenttube.vlc-helper" "$PLIST"
plutil -replace LSUIElement -bool true "$PLIST"   # no Dock icon while it hands a link to VLC
plutil -replace CFBundleURLTypes -json '[{"CFBundleURLName":"Torrent Tube VLC link","CFBundleURLSchemes":["torrenttube-vlc"]}]' "$PLIST"
codesign --force --deep --sign - "$APP" 2>/dev/null   # re-sign after editing Info.plist
"$LSREGISTER" -f "$APP"
{% if key %}
# Tell the Torrent Tube page this computer is ready, so it can go on by itself.
curl -fsS -X POST -d "vlc=$VLC_FOUND" "$ORIGIN/api/helper/{{ key }}" >/dev/null 2>&1 || true
{% endif %}
echo "Done: Torrent Tube VLC Helper is installed in ~/Applications."
echo "Press Play in VLC in Torrent Tube - your browser asks once whether to open the helper."
