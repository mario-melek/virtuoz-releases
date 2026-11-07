# Runs Virtuoz's own self test (start, database, window, tools, a short demo export) in a sandbox folder.
#   powershell -File build/selftest.ps1 [-Exe <path to Virtuoz.exe>] [-SkipExport]
param([string]$Exe = (Join-Path $env:LOCALAPPDATA 'Programs\virtuoz\Virtuoz.exe'), [switch]$SkipExport)
$ErrorActionPreference = 'Stop'
$sb = Join-Path $env:TEMP ('virtuoz-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path "$sb\userdata", "$sb\workspace" | Out-Null
$report = Join-Path $sb 'report.json'
$env:CZ_USERDATA = "$sb\userdata"; $env:CZ_WORKSPACE = "$sb\workspace"; $env:CZ_HIDDEN = '1'; $env:CZ_SELF_TEST = '1'
# the runtime (ffmpeg, Python) Virtuoz may have set up at home, like tools/selftest.mjs
$rt = Join-Path $env:APPDATA 'Virtuoz\runtime'; if (Test-Path $rt) { $env:CZ_RUNTIME_DIR = $rt }
Write-Host "self test of $Exe (sandbox $sb)"
$p = Start-Process -FilePath $Exe -ArgumentList "--self-test=$report", "--cz-sandbox=$sb", '--mute-audio' -PassThru
if (-not $p.WaitForExit(600000)) { Write-Host 'still running after 10 minutes: stopped'; $p.Kill() }
Write-Host "exit code $($p.ExitCode)"
$log = Get-ChildItem "$sb\userdata" -Recurse -Filter main.log -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not (Test-Path $report)) { Write-Host 'FAILED: no report'; if ($log) { Get-Content $log.FullName -Tail 60 }; exit 1 }
$r = Get-Content $report -Raw | ConvertFrom-Json
$bad = @()
foreach ($s in @($r.steps)) { if ($s -and $s.ok -eq $false) { $bad += $s.name; Write-Host "FAIL start · $($s.name) $($s.error)" } }
if ($r.db.ok -eq $false) { $bad += 'database' }; Write-Host ("{0} database {1}" -f $(if ($r.db.ok -eq $false) { 'FAIL' } else { 'ok  ' }), $r.db.error)
if ($r.paint -eq 'blank') { $bad += 'paint' }; Write-Host "window paint: $($r.paint)"
foreach ($t in $r.tools.PSObject.Properties) { $ok = $t.Value.ok; if ($ok -eq $false) { $bad += $t.Name }; Write-Host ("{0} tool {1} {2}" -f $(if ($ok -eq $false) { 'FAIL' } else { 'ok  ' }), $t.Name, $t.Value.error) }
$ex = $r.export; Write-Host ("{0} demo export {1}" -f $(if ($ex.ok -eq $false) { 'FAIL' } else { 'ok  ' }), $ex.error)
if ($ex.ok -eq $false -and -not $SkipExport) { $bad += 'export' }
Write-Host "report ok: $($r.ok) | judged failures: $(if ($bad.Count) { $bad -join ', ' } else { 'none' })"
if ($log) { Write-Host '--- graphics and export lines of main.log'; Get-Content $log.FullName | Select-String -Pattern 'graphics|gpu|webgl|export|self-test' | Select-Object -Last 40 | ForEach-Object { $_.Line } }
if ($bad.Count) { exit 1 } else { exit 0 }
