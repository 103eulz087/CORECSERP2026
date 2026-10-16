param(
    [Parameter(Mandatory)] [string]$Key,          # registry key under HKCU\AAITCRE, e.g. ConnSettingsServer
    [string]$Catalog,                             # optional Initial Catalog override
    [string]$Sql,                                 # query text
    [string]$SqlFile,                             # or a file holding it
    [string]$OutFile,                             # write the first column of the first row here (for definitions)
    [switch]$Info,                                # print server / catalog only
    [switch]$NonQuery,                            # run as a batch (GO-split), print messages
    [int]$Timeout = 300
)
Add-Type -AssemblyName System.Security
$enc = [string](Get-ItemProperty "HKCU:\AAITCRE\$Key").dbconn
try { $plain = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($enc), [Text.Encoding]::UTF8.GetBytes("CORECS-ConnSettings-v1"), "CurrentUser")) } catch { $plain = $enc }
$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $plain
if ($Catalog) { $b["Initial Catalog"] = [string]$Catalog }
Write-Output ("# " + $b["Data Source"] + " / " + $b["Initial Catalog"])
if ($Info) { return }
if ($SqlFile) { $Sql = [IO.File]::ReadAllText($SqlFile) }
$c = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
$c.add_InfoMessage({ param($s, $e) Write-Output ("MSG: " + $e.Message) })
$c.FireInfoMessageEventOnUserErrors = $false
$c.Open()
try {
    if ($NonQuery) {
        $batches = [regex]::Split($Sql, '^\s*GO\s*$', [Text.RegularExpressions.RegexOptions]::Multiline -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($bt in $batches) {
            if ($bt.Trim().Length -eq 0) { continue }
            $cmd = $c.CreateCommand(); $cmd.CommandTimeout = $Timeout; $cmd.CommandText = $bt
            $rd = $cmd.ExecuteReader()
            do { $dt = New-Object System.Data.DataTable; $dt.Load($rd); if ($dt.Columns.Count -gt 0) { $dt | Format-Table -AutoSize | Out-String -Width 400 } } while (-not $rd.IsClosed)
        }
        return
    }
    $cmd = $c.CreateCommand(); $cmd.CommandTimeout = $Timeout; $cmd.CommandText = $Sql
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $ds = New-Object System.Data.DataSet; [void]$da.Fill($ds)
    if ($OutFile) { [IO.File]::WriteAllText($OutFile, [string]$ds.Tables[0].Rows[0][0]); Write-Output "saved $OutFile"; return }
    foreach ($t in $ds.Tables) { $t | Format-Table -AutoSize | Out-String -Width 400 }
} finally { $c.Close() }
