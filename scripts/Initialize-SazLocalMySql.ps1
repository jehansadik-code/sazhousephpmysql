[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$HostName = '127.0.0.1',
    [int]$Port = 3306,
    [string]$Database = 'saz_house',
    [string]$AppUser = 'saz_house_app',
    [string]$MySqlPath = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe',
    [string]$MySqlDumpPath = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe',
    [pscredential]$AdminCredential,
    [pscredential]$AppCredential,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Apply) { throw 'This script is dry by default. Re-run with -Apply after reviewing the parameters.' }
if (-not (Test-Path -LiteralPath $MySqlPath)) { throw "mysql.exe was not found: $MySqlPath" }
if (-not $AdminCredential) { $AdminCredential = Get-Credential -Message 'Enter a local MySQL administrator credential' }
if (-not $AppCredential) { $AppCredential = Get-Credential -UserName $AppUser -Message 'Set or enter the SAZ application-user password' }
if ($AppCredential.UserName -ne $AppUser) { throw 'The application credential username must match -AppUser.' }

function Escape-MySqlLiteral([string]$Value) { return $Value.Replace("'", "''") }
function Invoke-AdminMySql([string]$Query, [string]$TargetDatabase = '') {
    $previous = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $AdminCredential.GetNetworkCredential().Password
        $arguments = @('--protocol=TCP', "--host=$HostName", "--port=$Port", "--user=$($AdminCredential.UserName)", '--show-warnings')
        if ($TargetDatabase) { $arguments += "--database=$TargetDatabase" }
        $arguments += "--execute=$Query"
        $output = & $MySqlPath @arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
        return $output
    } finally { if ($null -eq $previous) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue } else { $env:MYSQL_PWD = $previous } }
}
function Invoke-SqlFile([string]$Path, [switch]$WithoutDatabase) {
    $previous = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $AdminCredential.GetNetworkCredential().Password
        $arguments = @('--protocol=TCP', "--host=$HostName", "--port=$Port", "--user=$($AdminCredential.UserName)")
        if (-not $WithoutDatabase) { $arguments += "--database=$Database" }
        $output = Get-Content -LiteralPath $Path -Raw | & $MySqlPath @arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
        Write-Host "Applied $(Split-Path $Path -Leaf)"
    } finally { if ($null -eq $previous) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue } else { $env:MYSQL_PWD = $previous } }
}

$root = Split-Path $PSScriptRoot -Parent
$completeSetup = Join-Path $root 'database\SAZ_HOUSE_COMPLETE_SETUP.sql'
if ($Database -ne 'saz_house') { throw 'The complete setup script intentionally targets only saz_house. Use a copied script with a different database name for disposable testing.' }
$databaseLiteral = Escape-MySqlLiteral $Database
$exists = (Invoke-AdminMySql "SELECT SCHEMA_NAME FROM information_schema.schemata WHERE schema_name='$databaseLiteral';") -match [regex]::Escape($Database)
if ($exists) {
    $tableCount = [int]((Invoke-AdminMySql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$databaseLiteral';") | Select-Object -Last 1)
    if ($tableCount -gt 0) {
        if (-not (Test-Path -LiteralPath $MySqlDumpPath)) { throw 'Existing data was found, but mysqldump.exe is unavailable; refusing to alter the database without a backup.' }
        $backupDirectory = Join-Path $root 'backups'
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backup = Join-Path $backupDirectory ("$Database-local-before-migrations-$(Get-Date -Format 'yyyyMMdd-HHmmss').sql")
        $previous = $env:MYSQL_PWD
        try { $env:MYSQL_PWD = $AdminCredential.GetNetworkCredential().Password; & $MySqlDumpPath '--protocol=TCP' "--host=$HostName" "--port=$Port" "--user=$($AdminCredential.UserName)" '--single-transaction' '--routines' '--events' $Database | Out-File -LiteralPath $backup -Encoding utf8; if ($LASTEXITCODE -ne 0) { throw 'mysqldump failed.' } } finally { if ($null -eq $previous) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue } else { $env:MYSQL_PWD = $previous } }
        Write-Host "Backup created: $backup"
    }
}

Invoke-SqlFile $completeSetup -WithoutDatabase
$appPassword = Escape-MySqlLiteral $AppCredential.GetNetworkCredential().Password
$appUserLiteral = Escape-MySqlLiteral $AppUser
Invoke-AdminMySql "CREATE USER IF NOT EXISTS '$appUserLiteral'@'127.0.0.1' IDENTIFIED BY '$appPassword'; ALTER USER '$appUserLiteral'@'127.0.0.1' IDENTIFIED BY '$appPassword'; GRANT SELECT, INSERT, UPDATE, DELETE ON \`$Database\`.* TO '$appUserLiteral'@'127.0.0.1'; CREATE USER IF NOT EXISTS '$appUserLiteral'@'localhost' IDENTIFIED BY '$appPassword'; ALTER USER '$appUserLiteral'@'localhost' IDENTIFIED BY '$appPassword'; GRANT SELECT, INSERT, UPDATE, DELETE ON \`$Database\`.* TO '$appUserLiteral'@'localhost';"
Write-Host "Database '$Database' is initialized and '$AppUser' has application-only DML privileges for both local TCP and localhost PDO connections. Use Test-SazLocalMySql.ps1 with the application credential to verify it."
