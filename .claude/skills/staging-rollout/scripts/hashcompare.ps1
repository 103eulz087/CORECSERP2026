# Compares the whitespace-insensitive SHA-256 of objects (and the existence of their backups) across tiers.
#   -Objects   object names (procs, functions, triggers, views)
#   -Backup    optional backup suffix, e.g. _OLD_10152026220000: also lists those backups per tier
#   -Keys      registry keys to compare, in order; a "Key|Catalog" pair forces the catalog
# Example: hashcompare.ps1 -Objects sp_A,sp_B -Backup _OLD_10152026220000 -Keys 'ConnSettingsServer|COREX001','ConnSettingsStaging','ConnSettingsProdReadOnly'
param([Parameter(Mandatory)][string[]]$Objects, [string]$Backup, [string[]]$Keys = @('ConnSettingsServer|COREX001', 'ConnSettingsStaging', 'ConnSettingsProdReadOnly'))
$db = Join-Path $PSScriptRoot 'db.ps1'
# with powershell -File, "a,b,c" arrives as ONE string: split it
$Objects = @($Objects | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Keys = @($Keys | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$names = ($Objects | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
$sql = "SET NOCOUNT ON; SELECT o.name, CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(OBJECT_DEFINITION(o.object_id),CHAR(13),''),CHAR(10),''),CHAR(9),''),' ','')),2) AS H FROM sys.objects o WHERE o.name IN ($names)"
if ($Backup) { $sql += " OR o.name LIKE '%" + $Backup.Replace('_', '[_]') + "'" }
$sql += " ORDER BY o.name;"
$results = @{}
foreach ($k in $Keys) {
    $parts = $k.Split('|')
    # in-process call: passing the SQL to a second powershell.exe mangles its quotes
    if ($parts.Count -gt 1) { $text = & $db -Key $parts[0] -Catalog $parts[1] -Sql $sql | Out-String }
    else { $text = & $db -Key $parts[0] -Sql $sql | Out-String }
    $out = @($text -split "`r?`n" | Where-Object { $_ -match '\S' })
    $out[0]
    $rows = @{}
    foreach ($line in $out) { if ($line -match '^(\S+)\s+([0-9A-F]{64})\s*$') { $rows[$Matches[1]] = $Matches[2] } elseif ($line -match '^(\S+)\s*$' -and $line -notmatch '^(name|-+|#)') { $rows[$Matches[1]] = '(no text)' } }
    $results[$k] = $rows
}
$all = $results.Values | ForEach-Object { $_.Keys } | Sort-Object -Unique
# hashes are full SHA-256 (64 hex, = the script guards); the table shows the first 16, the full values follow
"{0,-60} {1}" -f 'object', ($Keys -join ' | ')
$full = @()
foreach ($n in $all) {
    $vals = @($Keys | ForEach-Object { if ($results[$_].ContainsKey($n)) { $results[$_][$n] } else { '-' } })
    $present = @($vals | Where-Object { $_ -ne '-' })
    $missing = @(for ($i = 0; $i -lt $Keys.Count; $i++) { if ($vals[$i] -eq '-') { $Keys[$i] } })
    if ($missing.Count -gt 0) { $verdict = 'MISSING on ' + ($missing -join ', ') + $(if (($present | Sort-Object -Unique).Count -gt 1) { '; others DIFFER' } else { '' }) }
    elseif (($vals | Sort-Object -Unique).Count -eq 1) { $verdict = 'same' }
    else { $verdict = 'DIFFERS' }
    $short = $vals | ForEach-Object { if ($_.Length -eq 64) { $_.Substring(0, 16) } else { $_ } }
    "{0,-60} {1}  {2}" -f $n, ($short -join ' | '), $verdict
    $full += "{0}: {1}" -f $n, ($vals -join ' | ')
}
''
'# full hashes'
$full
