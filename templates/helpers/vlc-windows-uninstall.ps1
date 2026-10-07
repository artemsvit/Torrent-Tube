# Torrent Tube - remove the VLC helper from this PC.
#
#   irm "{{ origin }}/helper/vlc-windows-uninstall.ps1" | iex
#
# Takes out the torrenttube-vlc link (per user, HKCU) and the small script
# it ran. VLC itself is left alone.

$origin = '{{ origin }}'
$link = 'HKCU:\Software\Classes\torrenttube-vlc'
$dir = Join-Path $env:LOCALAPPDATA 'TorrentTube'
if ((Test-Path $link) -or (Test-Path $dir)) {
    Remove-Item -Path $link -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Done: the Torrent Tube VLC helper is removed. VLC itself is still installed." -ForegroundColor Green
} else {
    Write-Host "The Torrent Tube VLC helper isn't installed on this PC."
}
{% if key %}
# Tell the Torrent Tube page, so Settings > Players can show it at once.
try { Invoke-RestMethod -Method Post -Uri "$origin/api/helper/{{ key }}" -Body @{ removed = 1 } | Out-Null } catch {}
{% endif %}
