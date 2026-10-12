# Offline interrupted-transaction diagnostics

`Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic` observes a single transaction
inside a disposable Windows Terminal fixture. Use PowerShell 7 or later. It has no
`Execute` parameter, never invokes apply/restore, and does not create, repair,
promote, delete, or rewrite settings, receipts, backups, or staging files.

Dot-source `TerminalTransaction-WindowsTerminal.ps1`, then inspect an existing
fixture with its explicit backup directory:

```powershell
Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic `
    -TestRoot $fixtureRoot -BackupDirectory $fixtureBackupDirectory
```

The root must be an existing direct child of `%TEMP%` named
`typezero-terminal-txn-<32 lowercase hexadecimal GUID characters>`. The backup
directory must be an immediate child of that fixture's
`Typezero\ThemeEngine\backups\terminal-combined` directory. All evidence paths are
derived from the fixture. Receipt path fields and optional metadata are never
followed. Real Terminal settings and private configurations cannot be selected
through this interface.

The current apply order is: create transaction directory, copy/check original
backup, write candidate stage, write receipt, recheck settings, replace settings,
verify applied checksum. Restore stages the original backup, rechecks settings,
replaces settings, and verifies the original checksum. Version 1 receipts do not
record a durable phase or stage filename, and restore does not update the receipt.

| State | Evidence and meaning |
| --- | --- |
| `TRANSACTION_MISSING` | Selected directory is absent. No transaction phase can be inferred. |
| `EVIDENCE_INCOMPLETE` | Receipt or original backup is absent. Includes an empty directory and backup-only or receipt-only interruptions. |
| `INVALID_RECEIPT` | Receipt is malformed, ambiguous, unsupported, points elsewhere, or has invalid/distinctness-failing checksums. |
| `BACKUP_HASH_MISMATCH` | Original backup differs from the valid receipt's before checksum. Settings interpretation remains untrusted. |
| `SETTINGS_MISSING` | Valid receipt and matching backup exist, but settings are absent. |
| `ORIGINAL_BYTES_PRESENT` | Settings match the before checksum. Could mean never applied or already restored. |
| `APPLIED_BYTES_PRESENT` | Settings match the after checksum. Completion of verification or restoration cannot be established. |
| `SETTINGS_CONFLICT` | Settings match neither recorded checksum. Could be an external edit, corruption, or another transaction. |

Every returned result sets `ReadOnly = $true` and `RecoveryAllowed = $false`.
`ReceiptState`, `BackupIntegrity`, and `SettingsState` describe evidence separately;
`Detail` explains the uncertainty. A malformed receipt takes precedence over
incomplete backup evidence. The diagnostic interprets settings hashes only after
the receipt and original backup agree. A valid receipt requires one strict JSON
object with an integer `Version` of 1, exact `Kind` of `TypezeroOfflineCombined`,
matching string `SettingsPath`, and two distinct 64-character hexadecimal SHA256
strings. Duplicate or case-ambiguous keys are rejected. Font metadata and unknown
fields are ignored. Receipts larger than 64 KiB are rejected with an error.

The diagnostic inventories only immediate settings-directory entries named exactly
`.typezero-combined-<guid>.tmp` or `.typezero-combined-restore-<guid>.tmp`. Each stage
reports its path, kind, checksum, and comparison with valid receipt hashes.
`Association = 'UNPROVEN'` always: matching bytes cannot associate a stage with this
transaction or prove that it is abandoned. Without a valid receipt, comparison is
`UNVERIFIED`. The diagnostic never recurses into other directories to find stages.

Redirected paths, nonfile evidence, nondirectory ancestors, access/sharing failures,
and detected changes between observations throw rather than return a usable state.
Files are opened read-only without write/delete sharing while their checksums are
read. A final reread checks hashes/existence and staging inventory. These are
observations, not a lock spanning all files; changes after observation or changes
that revert between observations remain possible. Consistent checksums do not
authenticate a receipt or backup. No diagnostic authorizes automatic recovery.

## Fixture regression checks

From the repository, run under PowerShell 7:

```powershell
& .\Netzach\PowerShell\ThemeEngine\tests\Test-TerminalRecovery.ps1
& .\Netzach\PowerShell\ThemeEngine\tests\Test-TerminalTransactionLifecycle.ps1
```

Both runners create new synthetic disposable `%TEMP%` roots and retain them for
inspection. They do not copy live settings or load private configurations. The
recovery runner invokes diagnostics only and checks file/tree/hash/metadata
preservation around diagnostic calls. Its redirected targets are also new
disposable roots. The lifecycle runner invokes the existing offline apply/restore
functions only against its new fixture to verify compatibility and corruption
guards. Neither runner deploys or executes ThemeEngine's live CLI or legacy writer.
