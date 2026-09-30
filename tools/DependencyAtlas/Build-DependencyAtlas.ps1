<#
    Build-DependencyAtlas.ps1
    ---------------------------------------------------------------------------
    Regenerates docs/atlas/DependencyAtlas.html: every Form / UserControl /
    XtraReport / class in SalesInventorySystem, cross-referenced against the SQL
    Server objects its code names (stored procedures, views, functions, tables,
    table types), plus what those objects depend on inside the database
    (sys.sql_expression_dependencies, table-type parameters).

    Read-only: the database is only queried (sys.* catalog views).

    Connection: nothing is hard-coded. Pass either
      -ConnectionString "<full connection string>"
    or
      -RegistryKey "<HKCU sub-key that holds the app's 'dbconn' value>"
    The registry value is decrypted with the app's own
    SalesInventorySystem.Classes.RegistryProtection.Unprotect (loaded from the
    built exe), so this script carries no key material of its own.
    -Catalog overrides the connection's Initial Catalog (optional).

    Example (from the repo root, Windows PowerShell 5.1):
      powershell -NoProfile -File tools\DependencyAtlas\Build-DependencyAtlas.ps1 -RegistryKey "<key from CLAUDE.md>"
#>
param(
    [string]$ConnectionString,
    [string]$RegistryKey,
    [string]$Catalog,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'
$src      = Join-Path $RepoRoot 'SalesInventorySystem'
$template = Join-Path $PSScriptRoot 'atlas-template.html'
if (-not $OutFile) { $OutFile = Join-Path $RepoRoot 'docs\atlas\DependencyAtlas.html' }

# ---------------------------------------------------------------- connection
if (-not $ConnectionString) {
    if (-not $RegistryKey) { throw 'Pass -ConnectionString or -RegistryKey.' }
    $raw = (Get-ItemProperty -Path ("HKCU:\" + $RegistryKey.TrimStart('\'))).dbconn
    if (-not $raw) { throw "No 'dbconn' value under HKCU\$RegistryKey." }
    $exe = Join-Path $src 'bin\Debug\SalesInventorySystem.exe'
    if (-not (Test-Path $exe)) { throw "Build the solution first: $exe not found (needed for RegistryProtection)." }
    Add-Type -AssemblyName System.Security
    $asm = [Reflection.Assembly]::LoadFrom($exe)
    $ConnectionString = $asm.GetType('SalesInventorySystem.Classes.RegistryProtection').GetMethod('Unprotect').Invoke($null, @([string]$raw))
}
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
if ($Catalog) { $csb["Initial Catalog"] = [string]$Catalog }
$dbName = [string]$csb["Initial Catalog"]

function Invoke-Sql([System.Data.SqlClient.SqlConnection]$con, [string]$sql) {
    $cmd = $con.CreateCommand(); $cmd.CommandTimeout = 300; $cmd.CommandText = $sql
    $dt = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter($cmd)).Fill($dt)
    return ,$dt
}

Write-Host "Reading catalog from $dbName ..."
$con = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString)
$con.Open()
try {
    # Live objects only: timestamped _OLD_ backups and *_Backup_* tables are left out.
    $objSql = @"
SET NOCOUNT ON;
SELECT o.object_id AS id, o.name,
       CASE o.type WHEN 'P' THEN 'P' WHEN 'V' THEN 'V' WHEN 'U' THEN 'U'
                   WHEN 'FN' THEN 'F' WHEN 'IF' THEN 'F' WHEN 'TF' THEN 'F' END AS t
FROM sys.objects AS o
WHERE o.type IN ('P','V','U','FN','IF','TF')
  AND o.is_ms_shipped = 0
  AND o.name NOT LIKE '%[_]OLD[_]%'
  AND o.name NOT LIKE '%[_]Backup[_]%'
UNION ALL
SELECT tt.type_table_object_id, tt.name, 'T'
FROM sys.table_types AS tt
WHERE tt.is_user_defined = 1;
"@
    $depSql = @"
SET NOCOUNT ON;
SELECT DISTINCT d.referencing_id AS a, d.referenced_id AS b
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id IS NOT NULL AND d.referencing_id <> d.referenced_id
UNION
SELECT DISTINCT p.object_id, tt.type_table_object_id
FROM sys.parameters AS p
INNER JOIN sys.table_types AS tt ON tt.user_type_id = p.user_type_id;
"@
    $colSql = @"
SET NOCOUNT ON;
SELECT DISTINCT LOWER(c.name) AS name
FROM sys.columns AS c
INNER JOIN sys.objects AS o ON o.object_id = c.object_id
WHERE o.type IN ('U','V') AND o.is_ms_shipped = 0;
"@
    $objs = Invoke-Sql $con $objSql
    $deps = Invoke-Sql $con $depSql
    $cols = Invoke-Sql $con $colSql
}
finally { $con.Close() }

# name (lower) -> index ; object_id -> index
$names = New-Object System.Collections.Generic.List[string]
$types = New-Object System.Collections.Generic.List[string]
$byName = @{}; $byId = @{}
foreach ($r in $objs.Rows) {
    $n = [string]$r.name; $k = $n.ToLowerInvariant()
    if ($byName.ContainsKey($k)) { $byId[[int]$r.id] = $byName[$k]; continue }
    $i = $names.Count; $names.Add($n); $types.Add([string]$r.t)
    $byName[$k] = $i; $byId[[int]$r.id] = $i
}
$edges = @{}
foreach ($r in $deps.Rows) {
    $a = $byId[[int]$r.a]; $b = $byId[[int]$r.b]
    if ($a -eq $null -or $b -eq $null -or $a -eq $b) { continue }
    if (-not $edges.ContainsKey($a)) { $edges[$a] = New-Object System.Collections.Generic.HashSet[int] }
    [void]$edges[$a].Add($b)
}

# Names that are safe to match anywhere inside a string literal. Anything else
# (mostly tables such as Inventory, Customers) must appear in SQL position:
# after FROM / JOIN / INTO / UPDATE / TABLE / EXEC, after dbo., or as a whole
# literal (helper calls like getMultipleQuery("Inventory", ...)). A table whose
# name is also a column name somewhere (ShipmentNo, ReferenceNumber) needs SQL
# position, so row["ShipmentNo"] doesn't count as a table reference.
$colNames = New-Object System.Collections.Generic.HashSet[string]
foreach ($r in $cols.Rows) { [void]$colNames.Add([string]$r.name) }
$loose = New-Object System.Collections.Generic.HashSet[int]
$wholeOk = New-Object System.Collections.Generic.HashSet[int]
for ($i = 0; $i -lt $names.Count; $i++) {
    $isCol = $colNames.Contains($names[$i].ToLowerInvariant())
    if ($types[$i] -ne 'U' -and -not $isCol) { [void]$loose.Add($i) }
    elseif ($types[$i] -eq 'U' -and $names[$i] -match '_' -and -not $isCol) { [void]$loose.Add($i) }
    if (-not $isCol) { [void]$wholeOk.Add($i) }
}
$sqlPrefix = '^(sp|spu|splist|sp_rpt|func|funcview|fn|view|vw)_[A-Za-z0-9_]+$'

# ---------------------------------------------------------------- source scan
$reLiteral = [regex]'(?:\$@|@\$|@)"(?:[^"]|"")*"|\$?"(?:\\.|[^"\\\r\n])*"|''(?:\\.|[^''\\\r\n])''|//[^\r\n]*|/\*[\s\S]*?\*/'
$reToken   = [regex]'(?i)(?:\b(from|join|into|update|table|exec|execute|apply|merge)\s+)?(?:\[?dbo\]?\.)?\[?([A-Za-z_][A-Za-z0-9_]*)\]?'
$reClass   = [regex]'class\s+(\w+)\s*:\s*([A-Za-z0-9_.]+)'
$scratchRe = '(^|/)(zzzDemozzz|Samples|txtBackup|OldReferenceFile)(/|$)'

$files = New-Object System.Collections.Generic.List[object]
$csFiles = Get-ChildItem -Path $src -Recurse -Filter *.cs |
    Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' -and $_.Name -notlike '*.Designer.cs' -and $_.Name -ne 'AssemblyInfo.cs' }
foreach ($f in $csFiles) {
    $rel = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
    $text = [IO.File]::ReadAllText($f.FullName)
    $designer = [IO.Path]::ChangeExtension($f.FullName, $null).TrimEnd('.') + '.Designer.cs'
    if (Test-Path $designer) { $text += "`n" + [IO.File]::ReadAllText($designer) }

    $kind = 'class'; $cls = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    foreach ($cm in $reClass.Matches($text)) {
        $base = $cm.Groups[2].Value
        if ($base -match '(XtraReport)$') { $kind = 'report'; $cls = $cm.Groups[1].Value; break }
        if ($base -match '(Form|UserControl|XtraForm|RibbonForm|XtraUserControl)$') { $kind = 'form'; $cls = $cm.Groups[1].Value; break }
    }

    $direct = New-Object System.Collections.Generic.HashSet[int]
    $missing = New-Object System.Collections.Generic.HashSet[string]
    foreach ($lm in $reLiteral.Matches($text)) {
        $lit = $lm.Value
        if ($lit.StartsWith('//') -or $lit.StartsWith('/*') -or $lit.StartsWith("'")) { continue }
        $body = $lit.Substring($lit.IndexOf('"') + 1).TrimEnd('"')
        if ($body.Length -lt 3) { continue }
        $whole = $body.Trim().Trim('[', ']').ToLowerInvariant()
        if ($whole.StartsWith('dbo.')) { $whole = $whole.Substring(4).Trim('[', ']') }
        foreach ($tm in $reToken.Matches($body)) {
            $tok = $tm.Groups[2].Value
            $k = $tok.ToLowerInvariant()
            if ($byName.ContainsKey($k)) {
                $i = $byName[$k]
                $inSqlPos = $tm.Groups[1].Success -or $tm.Value -match '(?i)dbo\]?\.' -or ($whole -eq $k -and $wholeOk.Contains($i))
                if ($loose.Contains($i) -or $inSqlPos) { [void]$direct.Add($i) }
            }
            elseif ($tok -match $sqlPrefix -and $tok.Length -gt 6) { [void]$missing.Add($tok) }
        }
    }
    $group = if ($rel.Contains('/')) { $rel.Substring(0, $rel.IndexOf('/')) } else { '(root)' }
    $files.Add([ordered]@{
        n = $cls; p = $rel; g = $group; k = $kind
        s = [int]($rel -match $scratchRe)
        d = @($direct | Sort-Object)
        m = @($missing | Sort-Object)
    })
}

# ---------------------------------------------------------------- write page
# JSON written by hand: PowerShell's wrapped arrays don't serialize cleanly in 5.1.
function J([string]$s) {
    '"' + $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t').Replace('</', '<\/') + '"'
}
function JArr($items, [scriptblock]$fmt) { '[' + ((@($items) | ForEach-Object $fmt) -join ',') + ']' }
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('{"generated":' + (J (Get-Date).ToString('yyyy-MM-dd HH:mm')) + ',"db":' + (J $dbName))
[void]$sb.Append(',"names":' + (JArr $names { J $_ }))
[void]$sb.Append(',"types":' + (J ($types -join '')))
$edgeParts = foreach ($k in ($edges.Keys | Sort-Object)) { '"' + $k + '":[' + ((@($edges[$k]) | Sort-Object) -join ',') + ']' }
[void]$sb.Append(',"edges":{' + ($edgeParts -join ',') + '}')
$fileParts = foreach ($f in $files) {
    '{"n":' + (J $f.n) + ',"p":' + (J $f.p) + ',"g":' + (J $f.g) + ',"k":' + (J $f.k) + ',"s":' + $f.s +
    ',"d":[' + ($f.d -join ',') + '],"m":' + $(if ($f.m.Count) { JArr $f.m { J $_ } } else { '[]' }) + '}'
}
[void]$sb.Append(',"files":[' + ($fileParts -join ',') + ']}')
$json = $sb.ToString()

$html = [IO.File]::ReadAllText($template).Replace('/*__ATLAS_DATA__*/null', $json)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
[IO.File]::WriteAllText($OutFile, $html, (New-Object System.Text.UTF8Encoding($false)))

$withDeps = @($files | Where-Object { $_.d.Count -gt 0 }).Count
Write-Host ("Wrote {0}: {1} files ({2} forms, {3} with SQL references), {4} SQL objects in {5}." -f $OutFile, $files.Count, @($files | Where-Object { $_.k -eq 'form' }).Count, $withDeps, $names.Count, $dbName)
