<#
    Build-ProcessTrace.ps1
    ---------------------------------------------------------------------------
    Regenerates docs/process-trace/ProcessTrace.html: step-by-step traces of
    real transactions through each module's tables, with the linking keys
    color-coded so a value can be followed from table to table.

    One module = modules/<Name>.json (steps, tables, key families, sample
    scenarios, findings) + modules/<Name>.sql (read-only trace query taking
    @Ids and returning result sets whose first column _t names the table).
    Add a module by adding that pair; every *.json in modules/ is built.

    Read-only. Customer and user names are replaced with pseudonyms unless
    -NoMask is passed; amounts and keys are real.

    Connection: nothing is hard-coded. Pass -ConnectionString, or -RegistryKey
    (the HKCU sub-key holding the app's 'dbconn' value, decrypted through the
    built exe's RegistryProtection). -Catalog overrides Initial Catalog.

      powershell -NoProfile -File tools\ProcessTrace\Build-ProcessTrace.ps1 -RegistryKey "<key from CLAUDE.md>"
#>
param(
    [string]$ConnectionString,
    [string]$RegistryKey,
    [string]$Catalog,
    [string[]]$Modules,
    [switch]$NoMask,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'
$modDir   = Join-Path $PSScriptRoot 'modules'
$template = Join-Path $PSScriptRoot 'trace-template.html'
if (-not $OutFile) { $OutFile = Join-Path $RepoRoot 'docs\process-trace\ProcessTrace.html' }

# ---------------------------------------------------------------- connection
if (-not $ConnectionString) {
    if (-not $RegistryKey) { throw 'Pass -ConnectionString or -RegistryKey.' }
    $raw = (Get-ItemProperty -Path ("HKCU:\" + $RegistryKey.TrimStart('\'))).dbconn
    if (-not $raw) { throw "No 'dbconn' value under HKCU\$RegistryKey." }
    $exe = Join-Path $RepoRoot 'SalesInventorySystem\bin\Debug\SalesInventorySystem.exe'
    if (-not (Test-Path $exe)) { throw "Build the solution first: $exe not found (needed for RegistryProtection)." }
    Add-Type -AssemblyName System.Security
    $asm = [Reflection.Assembly]::LoadFrom($exe)
    $ConnectionString = $asm.GetType('SalesInventorySystem.Classes.RegistryProtection').GetMethod('Unprotect').Invoke($null, @([string]$raw))
}
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
if ($Catalog) { $csb["Initial Catalog"] = [string]$Catalog }
$dbName = [string]$csb["Initial Catalog"]

# ---------------------------------------------------------------- JSON helpers
$inv = [Globalization.CultureInfo]::InvariantCulture
function J([string]$s) {
    '"' + $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t').Replace('</', '<\/') + '"'
}
function JVal($v) {
    if ($v -eq $null -or $v -is [DBNull]) { return 'null' }
    if ($v -is [bool]) { return $(if ($v) { 'true' } else { 'false' }) }
    if ($v -is [datetime]) {
        if ($v.TimeOfDay.TotalSeconds -eq 0) { return J $v.ToString('yyyy-MM-dd') }
        return J $v.ToString('yyyy-MM-dd HH:mm')
    }
    if ($v -is [decimal] -or $v -is [double] -or $v -is [single] -or $v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) {
        return ([decimal]$v).ToString($inv)
    }
    return J ([string]$v).TrimEnd()
}

$peopleCols = @('CreatedBy', 'ReversedBy', 'EnteredBy', 'TransactedBy', 'PreparedBy', 'ApprovedBy', 'CheckedBy', 'RequestedBy', 'ProcessedBy', 'UserID')

$con = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString)
$con.Open()
$moduleParts = New-Object System.Collections.Generic.List[string]
try {
    # modules appear in business-flow order: the optional "order" field, then file name
    $defs = Get-ChildItem -Path $modDir -Filter *.json |
        Sort-Object @{ Expression = { $o = ([IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json).order; if ($o -ne $null) { [int]$o } else { 999 } } }, Name
    if ($Modules) { $defs = $defs | Where-Object { $Modules -contains $_.BaseName } }
    foreach ($defFile in $defs) {
        $defText = [IO.File]::ReadAllText($defFile.FullName)
        $def = $defText | ConvertFrom-Json
        $sql = [IO.File]::ReadAllText((Join-Path $modDir $def.sql))
        Write-Host "Module $($def.title) ..."

        # pseudonyms are shared across one module's scenarios so the same customer keeps one name
        $custMap = @{}; $userMap = @{}
        $scenParts = New-Object System.Collections.Generic.List[string]
        foreach ($sc in $def.scenarios) {
            $cmd = $con.CreateCommand(); $cmd.CommandTimeout = 300; $cmd.CommandText = $sql
            [void]$cmd.Parameters.Add('@Ids', [Data.SqlDbType]::NVarChar, 4000)
            $cmd.Parameters['@Ids'].Value = [string]$sc.ids
            $ds = New-Object System.Data.DataSet
            [void](New-Object System.Data.SqlClient.SqlDataAdapter($cmd)).Fill($ds)

            # pass 1: collect names to mask
            foreach ($t in $ds.Tables) {
                if ($t.Rows.Count -eq 0) { continue }
                $tid = [string]$t.Rows[0]['_t']
                $masks = @($def.tables.$tid.mask)
                foreach ($r in $t.Rows) {
                    foreach ($mc in $masks) {
                        if (-not $mc -or -not $t.Columns.Contains($mc)) { continue }
                        $v = ([string]$r[$mc]).Trim()
                        if ($v.Length -lt 2) { continue }
                        if ($peopleCols -contains $mc) { if (-not $userMap.ContainsKey($v)) { $userMap[$v] = 'User ' + ($userMap.Count + 1) } }
                        elseif (-not $custMap.ContainsKey($v)) { $custMap[$v] = 'Customer ' + [char](65 + ($custMap.Count % 26)) + $(if ($custMap.Count -ge 26) { [int]($custMap.Count / 26) } else { '' }) }
                    }
                }
            }
            $replace = @(); foreach ($k in $custMap.Keys) { $replace += ,@($k, $custMap[$k]) }; foreach ($k in $userMap.Keys) { $replace += ,@($k, $userMap[$k]) }
            $replace = $replace | Sort-Object { - $_[0].Length }

            # pass 2: serialize
            $tblParts = New-Object System.Collections.Generic.List[string]
            foreach ($t in $ds.Tables) {
                if ($t.Columns.Count -eq 0 -or $t.Columns[0].ColumnName -ne '_t') { continue }
                if ($t.Rows.Count -eq 0) { continue }
                $tid = [string]$t.Rows[0]['_t']
                $cols = @($t.Columns | Where-Object { $_.ColumnName -ne '_t' } | ForEach-Object { $_.ColumnName })
                $rowParts = foreach ($r in $t.Rows) {
                    $vals = foreach ($c in $cols) {
                        $v = $r[$c]
                        if (-not $NoMask -and $v -is [string] -and $v.Trim().Length -gt 0) {
                            $s = $v.Trim()
                            foreach ($p in $replace) { if ($s.IndexOf($p[0], [StringComparison]::OrdinalIgnoreCase) -ge 0) { $s = [regex]::Replace($s, [regex]::Escape($p[0]), $p[1], 'IgnoreCase') } }
                            $v = $s
                        }
                        JVal $v
                    }
                    '[' + ($vals -join ',') + ']'
                }
                $tblParts.Add((J $tid) + ':{"c":[' + (($cols | ForEach-Object { J $_ }) -join ',') + '],"r":[' + ($rowParts -join ',') + ']}')
            }
            $scenParts.Add((J $sc.id) + ':{' + ($tblParts -join ',') + '}')
            Write-Host ("  scenario {0}: {1} tables with rows" -f $sc.id, $tblParts.Count)
        }
        $moduleParts.Add('{"def":' + $defText.Trim() + ',"data":{' + ($scenParts -join ',') + '}}')
    }
}
finally { $con.Close() }

$json = '{"generated":' + (J (Get-Date).ToString('yyyy-MM-dd HH:mm')) + ',"db":' + (J $dbName) + ',"masked":' + $(if ($NoMask) { 'false' } else { 'true' }) +
        ',"modules":[' + ($moduleParts -join ',') + ']}'
$html = [IO.File]::ReadAllText($template).Replace('/*__TRACE_DATA__*/null', $json.Replace('</', '<\/'))
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
[IO.File]::WriteAllText($OutFile, $html, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $OutFile from $dbName ($($moduleParts.Count) module(s))."
