$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:RUNNER_TEMP 'FrameStudioInstalled'
$installer = @(Get-ChildItem 'release/*-Setup.exe')
$portable = @(Get-ChildItem 'release/*-Portable.exe')
if ($installer.Count -ne 1 -or $portable.Count -ne 1) { throw 'Expected exactly one installer and one portable package.' }
$install = Start-Process -FilePath $installer[0].FullName -ArgumentList @('/S', "/D=$installDir") -PassThru -Wait
if ($install.ExitCode -ne 0) { throw "Installer exited with $($install.ExitCode)." }
$installedExe = Join-Path $installDir 'FrameStudio.exe'
if (!(Test-Path $installedExe)) { throw 'Installed executable is missing.' }

function Test-Application([string] $Executable, [string] $Name) {
  $resultFile = Join-Path $env:RUNNER_TEMP "FrameStudio-$Name-smoke.json"
  $env:FRAME_STUDIO_USER_DATA = Join-Path $env:RUNNER_TEMP "FrameStudio-$Name-session"
  $process = Start-Process -FilePath $Executable -ArgumentList "--smoke-test=$resultFile" -PassThru
  $deadline = (Get-Date).AddSeconds(90)
  while (!(Test-Path $resultFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
  if (!(Test-Path $resultFile)) { throw "$Name startup did not produce a result within 90 seconds." }
  $result = Get-Content $resultFile -Raw | ConvertFrom-Json
  if (!$result.ok -or $result.platform -ne 'win32' -or $result.arch -ne 'x64') { throw "$Name failed: $(Get-Content $resultFile -Raw)" }
  if (!$process.WaitForExit(30000)) { throw "$Name did not exit after its smoke test." }
  if ($process.ExitCode -ne 0) { throw "$Name exited with $($process.ExitCode)." }
  Write-Output "$Name package: startup, local renderer, preview and isolation passed."
}
Test-Application $installedExe 'installed'
Test-Application $portable[0].FullName 'portable'
