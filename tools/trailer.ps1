# Трейлер из живого геймплея: Godot Movie Maker (детерминированно, 30 fps) → ffmpeg → mp4.
#   pwsh tools/trailer.ps1 [-Godot путь] [-Width 1920 -Height 1080] [-Fps 30]
# Результат: %APPDATA%\Godot\app_userdata\COOONTAINER\trailer\COOONTAINER_trailer.mp4
param(
	[string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
	[int]$Width = 1280,
	[int]$Height = 720,
	[int]$Fps = 30
)
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out = Join-Path $env:APPDATA "Godot\app_userdata\COOONTAINER\trailer"
New-Item -ItemType Directory -Force $out | Out-Null
Remove-Item "$out\raw.avi" -ErrorAction SilentlyContinue
Push-Location $root
# Steam-сборка Godot на Windows перезапускает себя дочерним процессом — ждём файл, а не процесс
Start-Process -FilePath $Godot -ArgumentList @('--path', '.', '--write-movie', "$out\raw.avi", '--fixed-fps', "$Fps", '--resolution', "${Width}x${Height}", '--', '--trailer') -Wait -NoNewWindow
Pop-Location
$deadline = (Get-Date).AddMinutes(15)
$last = -1
while ((Get-Date) -lt $deadline) {
	Start-Sleep 3
	if (-not (Test-Path "$out\raw.avi")) { continue }
	$size = (Get-Item "$out\raw.avi").Length
	if ($size -gt 0 -and $size -eq $last) { break }
	$last = $size
}
if (-not (Test-Path "$out\raw.avi")) { Write-Error "raw.avi was not written"; exit 1 }
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
	ffmpeg -y -loglevel error -i "$out\raw.avi" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart "$out\COOONTAINER_trailer.mp4"
	Write-Host "OK: $out\COOONTAINER_trailer.mp4"
} else {
	Write-Host "ffmpeg not found - kept $out\raw.avi (MJPEG + PCM)"
}
