# Portable PostgreSQL tools only: no Windows service, boot change or restart.
$ErrorActionPreference = 'Stop'
$nativeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../.local-tools/postgres17'))
New-Item -ItemType Directory -Path $nativeRoot -Force | Out-Null
$nativeArchive = Join-Path $nativeRoot 'postgresql-17.11-5-windows-x64-binaries.zip'
$nativeUrl = 'https://get.enterprisedb.com/postgresql/postgresql-17.11-5-windows-x64-binaries.zip'
$nativeExpected = '80379b2c04d51c30225532e0ae04509899141e9957ed096fe749d7fd9df8f82f'
if (-not (Test-Path -LiteralPath $nativeArchive)) {
  $ProgressPreference = 'SilentlyContinue'
  Invoke-WebRequest -Uri $nativeUrl -OutFile $nativeArchive -UseBasicParsing
}
$nativeActual = (Get-FileHash -LiteralPath $nativeArchive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($nativeActual -ne $nativeExpected) { throw 'PostgreSQL archive failed the publisher checksum check.' }
if (-not (Test-Path -LiteralPath (Join-Path $nativeRoot 'pgsql/bin/pg_dump.exe'))) {
  Expand-Archive -LiteralPath $nativeArchive -DestinationPath $nativeRoot
}
& (Join-Path $nativeRoot 'pgsql/bin/pg_dump.exe') --version
& (Join-Path $nativeRoot 'pgsql/bin/pg_restore.exe') --version
Write-Output 'Portable PostgreSQL archive verified against publisher SHA-256. Tools remain in ignored workspace storage.'
