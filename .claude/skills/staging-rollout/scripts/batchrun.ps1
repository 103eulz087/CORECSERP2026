param([string]$Key, [string]$Catalog, [string]$SqlFile)
Add-Type -AssemblyName System.Security
$enc = [string](Get-ItemProperty "HKCU:\AAITCRE\$Key").dbconn
try { $plain = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($enc), [Text.Encoding]::UTF8.GetBytes("CORECS-ConnSettings-v1"), "CurrentUser")) } catch { $plain = $enc }
$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $plain
if ($Catalog) { $b["Initial Catalog"] = [string]$Catalog }
"# " + $b["Data Source"] + " / " + $b["Initial Catalog"]
$c = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
$c.add_InfoMessage({ param($s, $e) Write-Output ("MSG: " + $e.Message) })
$c.Open()
$sql = [IO.File]::ReadAllText($SqlFile)
$batches = [regex]::Split($sql, '^\s*GO\s*$', [Text.RegularExpressions.RegexOptions]::Multiline -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$i = 0
foreach ($bt in $batches) {
  $i++
  if ($bt.Trim().Length -eq 0) { continue }
  try {
    $cmd = $c.CreateCommand(); $cmd.CommandTimeout = 600; $cmd.CommandText = $bt
    $rd = $cmd.ExecuteReader()
    do { $dt = New-Object System.Data.DataTable; $dt.Load($rd); if ($dt.Columns.Count -gt 0) { $dt | Format-Table -AutoSize | Out-String -Width 400 } } while (-not $rd.IsClosed)
  } catch {
    $first = ($bt.Trim() -split "`n" | Select-Object -First 3) -join ' / '
    "BATCH $i FAILED: " + $_.Exception.InnerException.Message + "  <<" + $first.Substring(0, [Math]::Min(200, $first.Length)) + ">>"
    if ($_.Exception.InnerException.Errors) { foreach ($er in $_.Exception.InnerException.Errors) { "   line " + $er.LineNumber + " proc " + $er.Procedure + ": " + $er.Message } }
    break
  }
}
$cmd = $c.CreateCommand(); $cmd.CommandText = "IF @@TRANCOUNT > 0 ROLLBACK; SELECT @@TRANCOUNT AS tc"; $cmd.ExecuteScalar() | Out-Null
$c.Close()
