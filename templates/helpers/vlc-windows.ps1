# Torrent Tube - VLC helper for Windows.
#
# Teaches Windows that torrenttube-vlc: links open in VLC, so "Play in VLC"
# on {{ origin }} starts VLC straight away, like "Play in Infuse". Per user
# (HKCU), no administrator rights. It only opens play links from
# {{ origin }}.
#
#   Install (PowerShell):  irm {{ origin }}/helper/vlc-windows.ps1 | iex
#   Uninstall:             Remove-Item -Recurse HKCU:\Software\Classes\torrenttube-vlc, "$env:LOCALAPPDATA\TorrentTube"

$origin = '{{ origin }}'

$vlc = $null
foreach ($key in 'HKLM:\SOFTWARE\VideoLAN\VLC', 'HKLM:\SOFTWARE\WOW6432Node\VideoLAN\VLC') {
    $value = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).'(default)'
    if ($value -and (Test-Path $value)) { $vlc = $value; break }
}
if (-not $vlc) {
    foreach ($path in "$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe") {
        if (Test-Path $path) { $vlc = $path; break }
    }
}
if (-not $vlc) {
    Write-Host "VLC isn't installed - get it from https://www.videolan.org/vlc/ and run this again." -ForegroundColor Yellow
    return
}

# The link handler: takes the torrenttube-vlc: link Windows passes in,
# checks it's a play link from this server, and hands it to VLC.
$dir = Join-Path $env:LOCALAPPDATA 'TorrentTube'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$handler = Join-Path $dir 'open-vlc.ps1'
@"
param([string]`$link)
`$target = `$link -replace '^torrenttube-vlc:', ''
if (-not `$target.StartsWith('$origin/play/')) { exit }
Start-Process -FilePath '$vlc' -ArgumentList @('--one-instance', `$target)
"@ | Set-Content -Path $handler -Encoding UTF8

$key = 'HKCU:\Software\Classes\torrenttube-vlc'
New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $key -Name '(default)' -Value 'URL:Torrent Tube VLC link'
Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$key\shell\open\command" -Name '(default)' `
    -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$handler`" `"%1`""

Write-Host "Done: Torrent Tube VLC helper is installed (VLC at $vlc)." -ForegroundColor Green
Write-Host "Press Play in VLC in Torrent Tube - your browser asks once whether to open it."
