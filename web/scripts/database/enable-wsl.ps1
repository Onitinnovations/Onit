# Run as administrator. Installs the WSL prerequisite without a Linux user distro
# and never restarts Windows automatically. Logs stay in the ignored workspace folder.
$ErrorActionPreference = 'Stop'
$runtimeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runtimeLogDirectory = Join-Path $runtimeRoot '.local-tools'
New-Item -ItemType Directory -Path $runtimeLogDirectory -Force | Out-Null
$runtimeLog = Join-Path $runtimeLogDirectory 'wsl-setup.log'
$runtimeStatus = Join-Path $runtimeLogDirectory 'wsl-setup-status.json'
$runtimeIdentity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $runtimeIdentity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Windows administrator elevation is required to enable WSL.'
}
Start-Transcript -Path $runtimeLog -Force | Out-Null
try {
  & "$env:SystemRoot/System32/wsl.exe" --install --no-distribution --web-download
  $runtimeExitCode = $LASTEXITCODE
  $runtimeFeatures = @('VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux') | ForEach-Object {
    Get-WindowsOptionalFeature -Online -FeatureName $_ | Select-Object FeatureName,State
  }
  [ordered]@{ exitCode=$runtimeExitCode; features=$runtimeFeatures; automaticRestart=$false } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $runtimeStatus -Encoding UTF8
  if ($runtimeExitCode -notin @(0,3010)) { throw "WSL installer returned $runtimeExitCode; inspect the local setup log." }
} catch {
  if (-not (Test-Path -LiteralPath $runtimeStatus)) {
    [ordered]@{ error=$_.Exception.Message; automaticRestart=$false } |
      ConvertTo-Json | Set-Content -LiteralPath $runtimeStatus -Encoding UTF8
  }
  throw
} finally {
  Stop-Transcript | Out-Null
}
