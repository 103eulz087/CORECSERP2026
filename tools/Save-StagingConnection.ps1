<#
    Saves a STAGING connection for Claude's read-only checks / approved deploys, on THIS PC and
    THIS Windows user only. Run it yourself in a PowerShell window (it asks for the password
    with hidden input; the password is never shown, logged or written in clear text):

        powershell -NoProfile -ExecutionPolicy Bypass -File tools\Save-StagingConnection.ps1

    Stored at HKCU\AAITCRE\ConnSettingsStaging, value "dbconn": the connection string
    encrypted with Windows DPAPI (CurrentUser, entropy 'CORECS-ConnSettings-v1' -- the same
    protection the app uses for its own keys, Classes/RegistryProtection.cs). The app's own
    keys (ConnSettingsMain / ConnSettingsServer) are not touched.

    To remove it later:  Remove-Item 'HKCU:\AAITCRE\ConnSettingsStaging' -Recurse
#>
Add-Type -AssemblyName System.Security

$server = Read-Host 'Server name (Enter = corex.itcoreapps.com)'
if ([string]::IsNullOrWhiteSpace($server)) { $server = 'corex.itcoreapps.com' }
$db = Read-Host 'Database (Enter = CORECSJFC2026_STAGING)'
if ([string]::IsNullOrWhiteSpace($db)) { $db = 'CORECSJFC2026_STAGING' }
$user = Read-Host 'SQL login'
$sec = Read-Host 'Password' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { $pwd = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$b['Data Source'] = $server; $b['Initial Catalog'] = $db; $b['User ID'] = $user; $b['Password'] = $pwd
$b['Connect Timeout'] = 20; $b['TrustServerCertificate'] = $true
$cs = $b.ConnectionString

# test before saving
try {
    $con = New-Object System.Data.SqlClient.SqlConnection($cs); $con.Open()
    $cmd = $con.CreateCommand()
    $cmd.CommandText = "SELECT @@SERVERNAME, @@SERVICENAME, DB_NAME(), SUSER_SNAME(), IS_ROLEMEMBER('db_owner'), HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'VIEW DEFINITION')"
    $r = $cmd.ExecuteReader(); [void]$r.Read()
    "Connected: server {0} / instance {1} / database {2} / login {3} / db_owner {4} / view definition {5}" -f $r[0], $r[1], $r[2], $r[3], $r[4], $r[5]
    $r.Close(); $con.Close()
} catch {
    "Connection FAILED, nothing saved: " + $_.Exception.Message
    exit 1
}

$enc = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($cs), [Text.Encoding]::UTF8.GetBytes('CORECS-ConnSettings-v1'), 'CurrentUser')
$key = 'HKCU:\AAITCRE\ConnSettingsStaging'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name 'dbconn' -Value ([Convert]::ToBase64String($enc))
Set-ItemProperty -Path $key -Name 'servername' -Value $server
Set-ItemProperty -Path $key -Name 'dbname' -Value $db
"Saved (encrypted) to $key. Tell Claude it's done."
