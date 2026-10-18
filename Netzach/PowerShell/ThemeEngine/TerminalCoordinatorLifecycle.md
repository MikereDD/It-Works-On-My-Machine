# Coordinator fixture lifecycle assessment

Milestone **57F.23.10.09.09.02** adds
`Get-TypezeroCoordinatorFixtureLifecycleAssessment` in
`TerminalCoordinatorLifecycle-WindowsTerminal.ps1`. This separate, function-only
module observes one existing synthetic fixture journal. It does not prepare a
journal, publish a receipt, create a lock, recover files, or activate a theme.
The guarded entry continues to permit inspection only.

## Source contracts and boundaries

- `TypezeroIntegrationPreflight.ps1` checks the seven synthetic baseline files,
  their expected hashes, and its private preflight marker. The guarded entry
  pins that module's exact bytes and reports no preparation or authorization.
- `TypezeroFreshCoordinatorFixtureJournal-Locked.ps1` is the separate locked
  preparer. It validates a clean recovery fixture and all seven candidates,
  creates a fresh journal without overwriting evidence, and records `Prepared`.
- `TerminalCoordinatorRecovery-WindowsTerminal.ps1` validates the DPAPI journal,
  immutable before/candidate bytes, current targets, and displacement evidence.
  Its observed state is independent of the manifest's recorded `Prepared` state.
- `TerminalCoordinatorReceipt-WindowsTerminal.ps1` validates a published receipt
  against that journal and complete apply/restore evidence for all seven files.
  Receipt verification is separate from journal state classification.

The assessment reuses those readers. It requires PowerShell 7.3 or later on
Windows and a local NTFS fixture directly under the current process's TEMP
directory, named `typezero-font-recovery-test-` followed by 32 lowercase hex
characters. The existing root validator requires a protected ACL owned by the
current user, with permitted access limited to that user and SYSTEM. Redirected
paths, alternate streams, hard links, unsafe entries, and oversized files are
refused or reported through the existing readers. A transaction ID must contain
exactly 32 lowercase hex characters. Invalid root boundaries throw before a
report is returned.

## Reading the report

| Fields | Meaning |
| --- | --- |
| `JournalStatus` | `Valid`, `Missing`, or `Invalid`; describes the manifest contract. |
| `RecordedState` | `Prepared` for a valid version 1 manifest; otherwise null. It is never rewritten. |
| `ObservedState` | Existing recovery classification: `Prepared`, `PartiallyApplied`, `Applied`, `OriginalUnresolved`, or `Conflicted`; `Unavailable` if inspection cannot complete. |
| `JournalInventoryValid` | Whether journal entries have recognized exact names and pass bounded plain-file reads. |
| `ArtifactConsistency` | `Consistent`, `Conflicted`, or `Unverified`; combines recovery observations with journal inventory validity. |
| `Artifacts` | Per-target `Position`, `ApplyEvidenceValid`, and `RestoreEvidenceValid` from the recovery inspector. |
| `ReceiptStatus` / `ReceiptValid` | `Valid`, `Invalid`, `Pending`, `Missing`, or `NotVerified`; only the published receipt verifier can set validity true. |
| `PublishedReceiptPresent` / `PendingReceiptPresent` | Presence observations, including an entry whose contents or form are unsafe. |
| `Blockers` / `Issues` | Stable blocker codes plus detailed issue objects containing `Code`, `Artifact`, and `Message`. |

A fresh `Prepared` journal normally has no recovery receipt: it has not produced
the complete recovery evidence required by the receipt verifier. The report
therefore retains `ReceiptMissing`; this does not make `Prepared` an invalid
journal. `OriginalUnresolved` alone also does not establish a verified recovery
receipt. A valid receipt leaves the manifest recorded as `Prepared` and reports
its own validity separately.

`receipt.pending` is never decrypted as a published receipt or promoted. Its
presence always adds `PendingReceipt`, including when a valid `receipt.dpapi`
also exists. An unexpected name, wrong-case name, subdirectory, reparse point,
hard link, or unreadable/oversized journal entry adds `JournalInventoryInvalid`.
Artifact conflicts, invalid or missing journals, failed artifact inspection, and
invalid, missing, or unverified receipts add their corresponding blocker codes.
`RecoveryNotAuthorized` and `LiveActivationNotAuthorized` are always present.

Every result has `FixtureOnly=True`, `ReadOnly=True`, `RecoveryAuthorized=False`,
and `LiveActivationAuthorized=False`. `AtomicSnapshot=False`: readers do not
take a transaction lock, and concurrent changes are not excluded. The report
does not authenticate original inputs or cross-root evidence, invoke an
external provider, or certify global restoration. Those four assurances remain
false. DPAPI CurrentUser does not protect against malicious code running as the
same user.

## NETZACH inspection

Use the newly created synthetic fixture for this milestone. The example assumes
`$newFixtureJournal` already holds its locked preparer result (`Root` and
`TransactionId`). Bind that variable to the actual retained result if necessary;
do not substitute a production path or a historical evidence archive. The
assessment does not create a fixture.

```powershell
$module = 'G:\Forgejo\It-Works-On-My-Machine\Netzach\PowerShell\ThemeEngine'
. (Join-Path $module 'FontWriter-WindowsTerminal.ps1')
. (Join-Path $module 'TerminalCoordinatorRecovery-WindowsTerminal.ps1')
. (Join-Path $module 'TerminalCoordinatorReceipt-WindowsTerminal.ps1')
. (Join-Path $module 'TerminalCoordinatorLifecycle-WindowsTerminal.ps1')

$assessment = Get-TypezeroCoordinatorFixtureLifecycleAssessment `
    -TestRoot $newFixtureJournal.Root `
    -TransactionId $newFixtureJournal.TransactionId
$assessment | Format-List
```

## Isolated regression suite

`tests/Test-TypezeroCoordinatorFixtureLifecycle.ps1` creates separate synthetic
fixtures and accepts optional `-ReportPath` for a JSON report. Fixtures are
retained for inspection; the suite performs no cleanup. Run it with PowerShell
7.3 or later on Windows from the intended development checkout. On NETZACH, the
runner must execute as the current user outside the Codex filesystem sandbox:
the required owner/SYSTEM fixture ACL excludes the sandbox identity. Its fixture
construction and tampering are test operations, separate from the read-only
assessment itself. Test results must be taken from the actual run and report.

The existing guarded entry pins canonical LF bytes for
`TypezeroIntegrationPreflight.ps1`, while `.gitattributes` requests CRLF for
PowerShell checkout files. The isolated development clone used for this
milestone normalizes that preflight file to the exact tracked LF blob before
running the existing guard. NETZACH's original file already has those LF bytes.
Do not change the guard's pinned hash to bypass a mismatch; first verify the
file's bytes against the tracked source. This milestone changes no guarded
operation authorization and grants no production, merge, or push approval.
