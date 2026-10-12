# Process interruption tests and read-only recovery preview

The interruption runner exercises copied offline apply/restore code in child
PowerShell processes. It creates synthetic settings and all controls inside new
direct `%TEMP%` roots named `typezero-terminal-txn-<guid>`. It copies only the four
definition-only transaction/patch modules into those fixtures. It does not load
ThemeEngine's live CLI, font activation modules, profiles, or private configs.

Checked source instrumentation adds pause calls only to each fixture-local copy.
The source transaction module contains no pause hooks or new execution controls.
At each checkpoint, the controller waits for the child's acknowledgement and
then forcibly stops only the child process it started. The pause prevents the
child from crossing another transaction boundary while the controller observes
the fixture. Forced termination prevents the transaction's `finally` cleanup from
running, leaving interrupted staging evidence for read-only diagnosis.

| Operation and completed checkpoint | Expected evidence |
| --- | --- |
| Apply: directory creation | Incomplete evidence; no receipt or backup |
| Apply: original backup copy | Incomplete evidence; backup unverified without receipt |
| Apply: candidate staging | Incomplete evidence; one unassociated apply stage |
| Apply: receipt write | Original bytes present; apply stage matches after checksum but association remains unproven |
| Apply: settings replacement | Applied bytes present; phase unknown; no stage remaining |
| Apply: verification | Applied bytes present; diagnostic still cannot infer completion |
| Restore: original backup staging | Applied bytes present; unassociated restore stage matches before checksum |
| Restore: settings replacement | Original bytes present; phase unknown; no stage remaining |
| Restore: verification | Original bytes present; diagnostic still cannot infer completion |

The runner compares fixture inventories around repeated diagnostic calls. Settings,
receipt, backup, and staged bytes are retained for inspection. The suite also
checks normal uninstrumented apply/restore behavior. No real settings are copied
into fixtures, and no recovery operation runs on an interrupted fixture.

These tests cover abrupt process termination between completed filesystem
operations. They do not interrupt a write in progress, simulate power loss, prove
storage durability, or prove that `Move-Item` replacement is atomic.

## Read-only preview

`Get-TypezeroOfflineTerminalCombinedRecoveryPreview` calls the existing diagnostic
and describes possible next actions and blockers. It has no execution parameter
and never invokes apply, restore, stage promotion, deletion, or metadata repair.
Every result is read-only and keeps recovery execution prohibited.

The preview uses observations conservatively:

- Original bytes with valid evidence need no replacement; whether an apply never
  ran or a restore finished remains unknown.
- Applied bytes with valid evidence and no stages can suggest reviewing the
  existing offline restore path. That suggestion is informational and does not
  authorize execution or preserve the validity of current observations over time.
- Missing, partial, corrupted, conflicting, or unassociated staging evidence
  requires manual inspection. Stage hashes never establish transaction ownership.

The same redirected-path, access, sharing, and evidence-change errors propagate
from the diagnostic. A preview is not an executable recovery plan.

## Running the fixture checks

From the repository under PowerShell 7:

```powershell
& .\Netzach\PowerShell\ThemeEngine\tests\Test-TerminalInterruption.ps1
& .\Netzach\PowerShell\ThemeEngine\tests\Test-TerminalRecoveryPreview.ps1
```

Use the runners' explicit `SourceDirectory` parameter when testing a staged copy.
All created fixture roots are retained. Production deployment, live transactions,
and committing/pushing/merging are separate actions requiring authorization.
