# Builds a rolled-back rehearsal file: BEGIN TRANSACTION + the deploy script (its "open transaction" guard
# neutralised so it runs nested) + optional earlier scripts it depends on + tests + ROLLBACK + a "what is left" line.
#   -Script   the numbered deploy script (SQL\[NN]-...sql)
#   -Before   optional: scripts to install first in the same transaction (e.g. a prerequisite not yet on the tier)
#   -Tests    optional: success-path test file (refusal tests can't share the transaction: run them live, each rolled back)
#   -Check    optional: a SELECT that shows what is left after the rollback (default: @@TRANCOUNT)
#   -Out      the rehearsal file to write (put it in the scratchpad)
param([Parameter(Mandatory)][string]$Script, [string[]]$Before = @(), [string]$Tests, [string]$Check, [Parameter(Mandatory)][string]$Out)

function Neutralise([string]$path) {
    $src = [IO.File]::ReadAllText($path)
    $name = [IO.Path]::GetFileName($path)
    $m = [regex]::Match($name, '^\[(\d+)\]')
    if ($m.Success) {
        $nn = $m.Groups[1].Value
        $rx = [regex]("IF @@TRANCOUNT <> 0(\r?\n)BEGIN(\r?\n)    RAISERROR\('\[" + $nn + "\] stopped: this session")
        if ($rx.IsMatch($src)) { $src = $rx.Replace($src, { param($x) $x.Value.Replace('IF @@TRANCOUNT <> 0', 'IF 1 = 0') }, 1) }
        else { Write-Warning "$name has no '[$nn] stopped: this session' guard; included as is" }
    }
    return $src
}

$sb = New-Object Text.StringBuilder
[void]$sb.Append("BEGIN TRANSACTION;`nGO`n")
foreach ($b in $Before) { [void]$sb.Append((Neutralise $b) + "`nGO`nSELECT 'after $([IO.Path]::GetFileName($b))' AS step, @@TRANCOUNT AS tc;`nGO`n") }
[void]$sb.Append((Neutralise $Script) + "`nGO`n")
if ($Tests) { [void]$sb.Append([IO.File]::ReadAllText($Tests) + "`nGO`n") }
[void]$sb.Append("SELECT @@TRANCOUNT AS tc_before_rollback;`nIF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;`nGO`n")
if ($Check) { [void]$sb.Append($Check + "`nGO`n") } else { [void]$sb.Append("SELECT @@TRANCOUNT AS tc_after;`nGO`n") }
[IO.File]::WriteAllText($Out, $sb.ToString())
"built $Out"
