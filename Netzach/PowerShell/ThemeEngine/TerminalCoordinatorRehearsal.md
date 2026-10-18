# Coordinator fixture apply and restore rehearsal

Milestone **57F.23.10.09.09.03**, based on
`6092038910b3e223d5675813a6af2016baa659fa` on
`feature/themeengine-font-management` in `MikereDD/It-Works-On-My-Machine`.

The separate function-only module
`TerminalCoordinatorRehearsal-WindowsTerminal.ps1` rehearses replacements of
the seven synthetic coordinator targets. It consumes a journal produced by the
existing locked preparer. It never loads `ThemeEngine.ps1` or registers a live
entry point. `RecoveryAuthorized` and `LiveActivationAuthorized` remain false.

## Scope and reused contracts

The existing guarded preflight and locked preparer validate the seven synthetic
originals and candidates and seal the version 1 coordinator manifest. The
rehearsal reuses the FontWriter transaction boundary, exclusive lock, bounded
single-link byte reads, SHA-256 and content checks. The existing coordinator
recovery inspector, lifecycle assessment and receipt verifier remain the
authority for their respective observations. The narrow Terminal transaction
APIs retain their existing fixture path contracts.

Only a local NTFS directory directly under the current process's TEMP, named
`typezero-font-recovery-test-` plus 32 lowercase hexadecimal characters, can be
used. The root must have the existing protected current-user/SYSTEM ACL. All
seven names are fixed: `settings.json`, `vim-main.vim`, `vim-lightline.vim`,
`shell-current.ps1`, `appearance.mock`, `history-previous.txt`, and
`history-current.txt`. Candidates are byte arrays, including mock appearance and
history slots; no external provider or live history operation is performed.

The expected SHA-256 pins the exact sealed `coordinator.dpapi` bytes returned by
preparation. It is required again for every apply and restore call. Never
recalculate that pin to bless changed evidence.

## Invocation

The regression scripts load all required function-only modules themselves. For
manual inspection or use, load the dependencies in the same order as the
regression script. Bind `$prepared` to the actual output of
`New-TypezeroFreshCoordinatorFixtureJournal` for a newly created synthetic
fixture; never substitute a live directory or historical evidence archive.

```powershell
$arguments = @{
    TestRoot = $prepared.Root
    TransactionId = $prepared.TransactionId
    ExpectedJournalSha256 = $prepared.JournalSHA256
}

# Default preview and WhatIf do not replace files.
Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments
Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments -Execute -WhatIf

# Explicitly rehearse replacements only in this private fixture.
Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments -Execute -Confirm:$false
Restore-TypezeroCoordinatorFixtureRehearsal @arguments -Execute -Confirm:$false

$assessment = Get-TypezeroCoordinatorFixtureLifecycleAssessment `
    -TestRoot $prepared.Root -TransactionId $prepared.TransactionId
$assessment | Format-List
```

The manifest's recorded state remains `Prepared`. The inspector should observe
`Applied` after seven apply replacements. Exact restoration yields
`OriginalUnresolved`; a separately verified published receipt reports
`ReceiptStatus=Valid`. That combination is intentional and does not confer
recovery or activation authorization. A partial rehearsal cannot claim a full
seven-target restoration receipt without all required displacement evidence.

## Failure and evidence handling

Replacements use `File.Replace` and retain the actual displaced bytes. Immutable
before and candidate artifacts are not consumed. Apply follows canonical target
order; restore follows reverse order so intermediate target positions remain
compatible with the existing recovery classifier. There is no automatic rollback
that could overwrite a concurrent edit. Corrupt or unrecognized evidence and
foreign target bytes cause refusal.

An interrupted apply may be explicitly resumed with the same journal pin when
all current positions and displacement evidence agree. A partial apply may also
be explicitly restored; the full recovery receipt remains absent for targets
that were never applied. Once any restore displacement exists, reapply is
refused. A completed restore is idempotent and preserves its receipt bytes.
The debug stage names are generated internally and cannot be supplied by a caller.
A process killed after stage flush leaves that stage intact and blocks subsequent
apply/restore. A process killed after replacement can be explicitly resumed only
if the target and actual displacement validate. A pending receipt is never
automatically promoted or overwritten. The crash report's `AutomaticResumeAllowed`
field denotes that explicit fixture resumption was supported and tested; the
module does not run an automatic recovery service.

`-InterruptAfterReplacement` provides deterministic exception injection at
boundaries 0 through 7. The separate process-crash suite terminates an isolated
worker at stable debug checkpoints to exercise process death. These are distinct
tests. All fixtures and interrupted evidence are retained for inspection.

The operation is not a seven-file atomic transaction, atomic compare-and-swap,
or power-loss durability guarantee. DPAPI CurrentUser and private ACLs do not
defend against malicious code running as the same user or an administrator.
The read-only lifecycle assessment is not an atomic snapshot. Exact fixture
byte restoration does not certify global system restoration or original input
authenticity.

## NETZACH validation

Use PowerShell 7.3 or later as the current Windows user, outside the Codex
filesystem sandbox. Existing private fixture ACLs exclude sandbox identities,
and the sandbox can block NTFS replacement. No administrator elevation is
required by the suite. Use a new report filename for each run.

```powershell
$engine = 'G:\Forgejo\It-Works-On-My-Machine\Netzach\PowerShell\ThemeEngine'
$run = Join-Path $env:TEMP ('typezero-57F23010090903-reports-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null

& (Join-Path $engine 'tests\Test-TypezeroCoordinatorFixtureRehearsal.ps1') `
    -ReportPath (Join-Path $run 'rehearsal.json')
& (Join-Path $engine 'tests\Test-TypezeroCoordinatorFixtureProcessCrash.ps1') `
    -ReportPath (Join-Path $run 'process-crash.json')
& (Join-Path $engine 'tests\Test-TypezeroCoordinatorFixtureLifecycle.ps1') `
    -ReportPath (Join-Path $run 'lifecycle.json')
& (Join-Path $engine 'tests\Test-TerminalTransactionV2Lifecycle.ps1')
```

The guarded entry pins exact LF bytes for the existing
`TypezeroIntegrationPreflight.ps1`, whereas the repository's general `.ps1`
checkout rule requests CRLF. NETZACH's existing file matches the pin
`692B00314712FAF97DE941CAADFFECD923E3A55E0E453D4D879C08143AFE72AD`.
Verify that hash before running. The overlay does not alter that file or its
guard; a fresh clone may need the canonical tracked LF bytes restored after
verifying the original commit blob. Never change the pinned hash to bypass a
mismatch. The historical checkpoint-specific safety harness is unchanged and
is not a substitute for these independent suites.
