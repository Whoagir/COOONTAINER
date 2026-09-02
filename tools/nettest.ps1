# Сетевой тест: хост + клиент headless на localhost (tools/NetTest.gd).
#   pwsh tools/nettest.ps1 [путь_к_godot.exe]
param([string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root
$tmp = $env:TEMP
$h = Start-Process -FilePath $Godot -ArgumentList '--headless','--path','.','--','--nettest' -RedirectStandardOutput "$tmp\net_host.log" -RedirectStandardError "$tmp\net_host.err" -PassThru -NoNewWindow
$null = $h.Handle # без кэша хэндла Windows PowerShell теряет ExitCode
Start-Sleep 6
$c = Start-Process -FilePath $Godot -ArgumentList '--headless','--path','.','--','--nettest','--join=127.0.0.1' -RedirectStandardOutput "$tmp\net_client.log" -RedirectStandardError "$tmp\net_client.err" -PassThru -NoNewWindow
$null = $c.Handle
$c.WaitForExit(90000) | Out-Null
$h.WaitForExit(60000) | Out-Null
# WaitForExit(timeout) в Windows PowerShell не заполняет ExitCode — добираем без таймаута
foreach ($p in @($h, $c)) { if ($p.HasExited) { $p.WaitForExit() } else { $p.Kill() } }
"--- HOST"
Get-Content "$tmp\net_host.log","$tmp\net_host.err" | Where-Object { $_ -match "\[net\]|SCRIPT ERROR" }
"--- CLIENT"
Get-Content "$tmp\net_client.log","$tmp\net_client.err" | Where-Object { $_ -match "\[net\]|SCRIPT ERROR" }
Pop-Location
"--- EXIT host=$($h.ExitCode) client=$($c.ExitCode)"
exit ([int]($h.ExitCode -ne 0) + [int]($c.ExitCode -ne 0))
