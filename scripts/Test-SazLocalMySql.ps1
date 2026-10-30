[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [int]$Port = 3306,
    [string]$Database = 'saz_house',
    [string]$MySqlPath = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe',
    [string]$PhpPath = 'C:\php-8.5.12-1-Win32-vs17-x64\php.exe',
    [pscredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $MySqlPath)) { throw "mysql.exe was not found: $MySqlPath" }
if (-not $Credential) { $Credential = Get-Credential -Message 'Enter the local SAZ MySQL application credential' }

function Invoke-MySqlQuery([string]$Query, [string]$TargetDatabase = '') {
    $previous = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $Credential.GetNetworkCredential().Password
        $arguments = @('--protocol=TCP', "--host=$HostName", "--port=$Port", "--user=$($Credential.UserName)", '--batch', '--skip-column-names')
        if ($TargetDatabase) { $arguments += "--database=$TargetDatabase" }
        $arguments += "--execute=$Query"
        $result = & $MySqlPath @arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($result -join [Environment]::NewLine) }
        return $result
    } finally {
        if ($null -eq $previous) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue } else { $env:MYSQL_PWD = $previous }
    }
}

$required = @('roles','users','store_state','orders','order_items','contact_messages','checkout_requests','submission_throttle','admin_audit_log','media_uploads')
Write-Host 'Connectivity and server:'
Invoke-MySqlQuery 'SELECT VERSION(), CURRENT_USER();'
Write-Host "`nRequired-table count (expected 10):"
Invoke-MySqlQuery "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN ('roles','users','store_state','orders','order_items','contact_messages','checkout_requests','submission_throttle','admin_audit_log','media_uploads');" $Database
Write-Host "`nTable, column, index, and foreign-key metadata:"
Invoke-MySqlQuery "SELECT table_name, column_name, column_type, is_nullable, column_key FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY table_name, ordinal_position;" $Database
Invoke-MySqlQuery "SELECT table_name, index_name, non_unique, seq_in_index, column_name FROM information_schema.statistics WHERE table_schema = DATABASE() ORDER BY table_name, index_name, seq_in_index;" $Database
Invoke-MySqlQuery "SELECT table_name, constraint_name, referenced_table_name FROM information_schema.key_column_usage WHERE table_schema = DATABASE() AND referenced_table_name IS NOT NULL ORDER BY table_name, constraint_name;" $Database
Write-Host "`nRequired JSON state and revisions (expected seven rows, revision >= 1):"
Invoke-MySqlQuery "SELECT \`key\`, JSON_TYPE(value), revision FROM store_state WHERE \`key\` IN ('products','product_types','coupons','settings','site_content','page_products','home_categories') ORDER BY \`key\`;" $Database

if (Test-Path -LiteralPath $PhpPath) {
    $previousHost = $env:SAZ_DB_HOST; $previousPort = $env:SAZ_DB_PORT; $previousName = $env:SAZ_DB_NAME; $previousUser = $env:SAZ_DB_USER; $previousPassword = $env:SAZ_DB_PASSWORD
    try {
        $env:SAZ_DB_HOST = $HostName; $env:SAZ_DB_PORT = "$Port"; $env:SAZ_DB_NAME = $Database; $env:SAZ_DB_USER = $Credential.UserName; $env:SAZ_DB_PASSWORD = $Credential.GetNetworkCredential().Password
        & $PhpPath -r '$db=["host"=>getenv("SAZ_DB_HOST"),"port"=>(int)getenv("SAZ_DB_PORT"),"name"=>getenv("SAZ_DB_NAME"),"user"=>getenv("SAZ_DB_USER"),"pass"=>getenv("SAZ_DB_PASSWORD")]; $pdo=new PDO(sprintf("mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4",$db["host"],$db["port"],$db["name"]),$db["user"],$db["pass"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]); echo "PHP PDO connectivity: OK\n";'
        if ($LASTEXITCODE -ne 0) { throw 'PHP PDO connectivity test failed.' }
    } finally {
        foreach ($pair in @(@('SAZ_DB_HOST',$previousHost),@('SAZ_DB_PORT',$previousPort),@('SAZ_DB_NAME',$previousName),@('SAZ_DB_USER',$previousUser),@('SAZ_DB_PASSWORD',$previousPassword))) { if ($null -eq $pair[1]) { Remove-Item "Env:$($pair[0])" -ErrorAction SilentlyContinue } else { Set-Item "Env:$($pair[0])" $pair[1] } }
    }
}

Write-Host 'Local database verification completed.'
