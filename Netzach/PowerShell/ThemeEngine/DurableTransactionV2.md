# Durable transaction V2: disposable fixtures

This additive milestone authenticates a fixed transaction phase sequence and couples an authorized fixture restore to a one-time grant reservation. Hardening v1.1 adds complete byte-size preflight and a private deadline-aware RESTORE replacement routine. It does not change the V1 transaction implementation, the pinned replacement or patch modules, the existing V2 expiry fix, theme/preview behavior, or live activation gates. It never resolves a production Windows Terminal settings path.

**Crash-safe recovery here means fail-closed assessment and an explicitly authorized restore of a previously completed durable APPLY.** Interrupted or uncertain APPLY/RESTORE operations are preserved for fresh independent review. There is no resume, repair, cleanup, journal promotion, or automatic rollback API. An old receipt, evidence seal, reservation, caller Boolean, or observed settings hash cannot establish a durable phase.

## Dependencies and entry points

Use Windows, PowerShell 7, and local NTFS disposable fixtures accepted by `Get-TypezeroOfflineTerminalTransactionPaths`: an exact immediate TEMP child named `typezero-terminal-txn-<32 lowercase hexadecimal characters>`. Settings remain under the synthetic fixture's `Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`. The established path, reparse-point, single-link, staging, and native verified replacement checks remain mandatory.

Dot-source these files in order from the ThemeEngine directory:

```powershell
foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1',
    'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1',
    'TerminalTransaction-WindowsTerminal.ps1',
    'TerminalReplace-WindowsTerminal.ps1',
    'TerminalTransactionV2-WindowsTerminal.ps1',
    'TerminalEvidenceSealV2-WindowsTerminal.ps1',
    'TerminalRecoveryAuthorizationV2-WindowsTerminal.ps1',
    'TerminalRecoveryGrantV2-WindowsTerminal.ps1',
    'TerminalRecoveryReplayV2-WindowsTerminal.ps1',
    'TerminalTransactionV2Durable-WindowsTerminal.ps1'
)) { . (Join-Path $engine $name) }
```

The new script imports a private dynamic module and exports exactly three functions:

| Function | Purpose |
| --- | --- |
| `Invoke-TypezeroOfflineTerminalV2Durable` | Preview or execute a combined fixture APPLY using an independent 32-byte evidence key. |
| `Restore-TypezeroOfflineTerminalV2Durable` | Preview or execute RESTORE after independently reviewing the exact grant, approval MAC, evidence, current settings, replay state, and completed durable source. |
| `Get-TypezeroOfflineTerminalV2DurableAssessment` | Read-only authentication and observation of a particular durable transaction. |

The phase writer is private. Entry points accept neither a caller-supplied phase nor a callback. The RESTORE API accepts the actual `GrantJson`, `AuthorizationMac`, `ApprovalKey`, and `EvidenceKey`; it does not accept a review result or authorization Boolean. Approval and evidence keys must be distinct 32-byte values under the existing grant contract. Keys remain caller-managed memory and are never written into fixture evidence. Do not use the synthetic keys in the tests outside disposable fixtures.

Given an already initialized synthetic fixture, valid theme dictionary, and independent evidence key, the following previews, executes, and assesses APPLY:

```powershell
$arguments = @{
    TestRoot = $fixtureRoot
    Theme = $theme
    FontFace = 'JetBrainsMono Nerd Font'
    FontSize = 12
    FontWeight = 'semi-bold'
    IndependentKey = $evidenceKey
}
Invoke-TypezeroOfflineTerminalV2Durable @arguments
$applied = Invoke-TypezeroOfflineTerminalV2Durable @arguments -Execute -Confirm:$false
Get-TypezeroOfflineTerminalV2DurableAssessment -TestRoot $fixtureRoot `
    -BackupDirectory $applied.BackupDirectory -IndependentKey $evidenceKey
```

Preview and `-WhatIf` do not initialize a store, reserve a grant, create a lock, or write a stage. Execution requires both `-Execute` and `ShouldProcess` authorization. A successful APPLY returns `Status=VERIFIED`; a successful RESTORE returns `Status=RESTORED`. Both return `OperationPhase=COMPLETE` only after evidence revalidation.

Before RESTORE, explicitly initialize the existing disposable replay store using `Initialize-TypezeroOfflineTerminalV2ReplayStore`. The independently issued grant follows the unchanged `Get-TypezeroOfflineTerminalV2GrantPayload`/`Get-TypezeroOfflineTerminalV2GrantReview` contract and binds this APPLY's receipt, backup, seal, exact fixture/folder identity, current applied settings hash, operation, grant ID, issue time, and expiry time. The source must be a completed authenticated durable APPLY whose current settings still match the applied result. Legacy transactions remain ineligible for this writer.

```powershell
$restoreArguments = @{
    TestRoot = $fixtureRoot
    BackupDirectory = $applied.BackupDirectory
    GrantJson = $independentlyIssuedGrantJson
    AuthorizationMac = $independentlyIssuedMac
    ApprovalKey = $approvalKey
    EvidenceKey = $evidenceKey
}
Restore-TypezeroOfflineTerminalV2Durable @restoreArguments
$restored = Restore-TypezeroOfflineTerminalV2Durable @restoreArguments `
    -Execute -Confirm:$false
```

These examples assume the caller already has independently reviewed authorization material. This module provides no grant issuer or shortcut around that authorization boundary.

## Immutable evidence layout and authenticated phases

The fixed fixture-root store is `.typezero-terminal-v2-durable`. Its `.fixture` marker must contain exactly `TYPEZERO-V2-DURABLE-FIXTURE-1`. Each transaction gets a journal subdirectory named exactly like its owned V2 backup directory. A journal directory is created before the transaction's backup directory, stage, grant reservation, or settings replacement. An empty or partial journal therefore remains a fence after interruption.

The only journal filenames, in required contiguous order, are:

1. `000001.intent.json`: exact immutable transaction identity and intended hashes; for RESTORE this also permanently claims its source APPLY.
2. `000002.prepared.json`: stage and receipt have been written; for RESTORE the grant ID has already been reserved and exact authorization evidence copied.
3. `000003.replaced.json`: the established replacement primitive returned verified replacement and preserved-backup results.
4. `000004.complete.json`: receipt, backup, seal, absent consumed stage, and current settings result were revalidated before completion; RESTORE also revalidates its source chain and reservation.

Each record has exactly these case-sensitive fields:

```text
Version, Sequence, Phase, PreviousSha256, Kind,
FixtureRoot, BackupDirectory, Operation, ParentBackupDirectory,
GrantId, GrantSha256, AuthorizationMacSha256, ReservationSha256,
SourceChainSha256, SettingsPath, BeforeSha256, AfterSha256,
StageFileName, BackupFileName, ReceiptSha256, HmacSha256
```

`Version` and `Sequence` must be literal nonnegative JSON integers, with version 2 and the expected sequence 1 through 4. All other fields are strings. Duplicate, case-ambiguous, unknown, missing, wrongly typed, noncanonical, out-of-order, truncated, or extra evidence is refused. JSON property order, encoding, escaping, and whitespace must match the writer's exact compact UTF-8 representation. SHA-256 fields use uppercase hexadecimal; grant IDs use 32 lowercase hexadecimal characters. APPLY has empty parent/grant-related fields and cannot claim recovery authority.

HMAC-SHA256 uses the independent evidence key over the fixed field order, excluding `HmacSha256`, under domain `TYPEZERO-V2-DURABLE-PHASE-1`. Each UTF-8 value is prefixed with its little-endian Int32 byte length. `PreviousSha256` is SHA-256 of the preceding record's exact persisted bytes; the first uses 64 zeroes. The strict canonical-byte check also protects the last record's representation, which has no successor digest. Metadata must remain identical across all four phases. The chain binds the exact fixture root, backup folder, settings path, operation, receipt hash, intended stage hash, preserved backup hash, and, for RESTORE, source chain, grant bytes, approval-MAC bytes, and reservation bytes.

Journal, receipt, seal, stage, grant-copy, MAC-copy, and reservation writes use the existing immutable `CreateNew` plus `Flush(true)` primitive or an equivalent explicit `FileStream` sequence. APPLY uses the pinned native replacement primitive. RESTORE uses a private copy retaining every validation and verification from that primitive and adding a mandatory UTC grant deadline immediately before the native call. The original pinned file remains unchanged. The writer never overwrites a journal record. Failure paths retain all surviving evidence.

Before opening the persistent fixture lock, the writer prepares the actual receipt, transaction identity, and all four canonical chained authenticated phase records entirely in memory. RESTORE also prepares its exact grant-copy, reservation, reverse receipt, and hash-checked source bytes. Preparation is repeated under the shared lock. Both passes enforce inclusive encoded-byte limits: settings, stage and backup 16 MiB; receipt 65,536; phase record and reservation 32,768; grant 16,384 UTF-8 bytes; evidence/approval keys, MAC and seal exactly 32 bytes. Bounds include JSON escaping and multibyte UTF-8 encoding. An oversized input or generated candidate is refused before INTENT, reservation, stage, backup or settings writes; initial size refusal creates no lock. Phase advancement writes only the preflighted exact record bytes. Bounded evidence reads retain a handle denying write/delete while checking length and reading.

An APPLY backup folder contains exactly `receipt.json`, `settings-pre-replace.json`, and `evidence.seal` after completion. The receipt remains compatible with the established V2 evidence/grant readers, while the durable reader additionally rejects unknown receipt fields. Its automatically created legacy seal authenticates exact receipt and backup bytes; that seal alone continues to prove no phase.

A completed RESTORE folder also contains exact `grant.json` and `authorization.mac`. Its sealed receipt binds the reverse before/after hashes and source folder name. The original APPLY receipt, backup, seal, and journal remain untouched. Completion revalidates both the source chain and the reservation's exact hash and schema.

## Lock, expiration, and replay contract

All executing durable APPLY and RESTORE operations hold the same fixed `.typezero-terminal-v2.lock` as cooperating V2 writers. The lock is never caller-selected. Paths, prior durable evidence, candidate bytes, source ownership, grant authentication, and replay state are rechecked while holding it. An occupied lock causes refusal.

RESTORE serializes the exact reservation tombstone and all phase records and parses the authenticated grant expiry before INTENT. It then persists its authenticated INTENT/source claim while holding the lock and checks current UTC immediately before opening the reservation with `CreateNew`. A surviving empty or partial reservation remains spent. The expiration check occurs after serialization, preserving the earlier V2 expiry fix's ordering. Expiration is checked again before replacement preparation and, after all final path/link/hash validation, as the immediately preceding executable statement before native `File.Replace`. A pause before this final check that carries the operation past expiry causes refusal, retains PREPARED evidence and the spent grant, and creates no native displacement backup. This is not an atomic clock/filesystem operation: the operating system can schedule the process between the check and call. A grant expiring after INTENT leaves an uncertain transaction for review; it is never silently retried.

The durable writer uses the existing replay-store marker, filename, and reservation schema. It does not call a reserve operation that releases the lock before replacement. The reservation, source claim, preparation, replacement, and completion occur within one lock lifetime. Another cooperating process cannot reserve or execute the same grant concurrently. A completed RESTORE permanently claims its source, so supplying a different grant or manually putting applied settings bytes back does not authorize a second restore of the same source.

Before each durable operation, all durable journals are authenticated and completed snapshots are revalidated. Any incomplete/invalid journal, unexpected store or folder entry, uncertain stage, or replay reservation not associated with exactly one completed durable RESTORE blocks future durable writes across the fixture. This includes a crash before reservation, after `CreateNew` but before writing the tombstone, during staging, or on either side of native replacement. There is no evidence deletion/reset API and no automatic reuse of an old grant.

Existing legacy writers retain their original contracts and are not retroactively upgraded by importing this module. The additive durable writer's fence applies when using its entry points. Production use must not rely on legacy APIs obeying new durable evidence rules.

## Read-only assessment and crash boundary

Assessment always reports `ReadOnly=true`, `FixtureOnly=true`, `RecoveryAllowed=false`, `RecoveryAuthorized=false`, `LiveActivationAuthorized=false`, and `TrustedDurableProductionLedger=false`.

| Decision | Meaning |
| --- | --- |
| `COMPLETE` | All four authenticated canonical records and immutable transaction evidence revalidate; the current fixture settings match this transaction's after hash. |
| `COMPLETE_HISTORICAL` | The completed chain and immutable historical evidence revalidate, but current settings are before/other/missing. This is not authorization and does not permit recovery. |
| `REVIEW_REQUIRED` | A valid authenticated chain is incomplete. The reported phase is the last recorded phase, not proof that a later native action did or did not happen. |
| `INVALID_EVIDENCE` | Required evidence, schema, path, link count, canonical bytes, hash, key, reservation, or authentication could not be established. |

`ChainAuthenticated` describes the journal validation only. It can remain true when independent snapshot validation subsequently fails; only `EvidenceComplete` together with the decision and observed `SettingsState` describes a completed proof. Assessment may recognize a valid historical transaction without authorizing it. Legacy receipts and seals without a new authenticated journal retain `OperationPhase=UNKNOWN`.

An interruption after native replacement but before the next record must remain uncertain even if settings happen to match the intended result. Assessment does not append completion, recreate a missing seal, delete a stage, reverse settings, or resume with either the old grant or a replacement grant. Review must independently decide what to do with the disposable fixture; this milestone deliberately offers no API to clear its fence.

The durability and locking claims cover cooperating fixture processes and tested process termination boundaries on local Windows/NTFS. `Flush(true)` does not establish directory-entry fsync, a power-loss guarantee, remote-filesystem correctness, protection against a privileged hostile process, or a tamper-proof production ledger. HMAC protects changes without the independent key; it does not prevent someone from deleting or rolling back the entire fixture, journal store, or replay store together. No external monotonic store, operating-system authorization policy, or key vault is implemented.

## Deterministic validation

`tests/Test-TypezeroTerminalV2Durable.ps1` creates synthetic TEMP fixtures only. It covers preview/WhatIf, strict keys and grants, completed APPLY and authorized RESTORE, exact-byte and schema tampering, evidence and settings conflicts, path/link refusal, fixed-lock contention, same-grant concurrency, replay, permanent source ownership, expiry, and actual child-process termination around journal, reservation, staging, sealing, and replacement boundaries.

The test harness temporarily and reversibly instruments unique inert comments in memory. Separate reversible instrumentation of the pinned replacement dependency exercises the actual native replacement boundary. Production sources contain no callable crash hook or caller callback. Child identity is checked before termination, and only harness-owned fixture workers are stopped. Native hard-link and replacement tests require a Windows environment that permits those operations. Consult the generated verification report for the exact test count, observed boundaries, and environment of a given overlay build.

The original v1.0 native Windows run recorded 106 checks, including 23 actual child-process termination boundaries, with 47 synthetic fixtures retained for evidence. These historical counts do not describe v1.1. Consult the v1.1 verification report for actual executed results and source/artifact hashes. The expanded suite checks inclusive byte boundaries, completed RESTORE tampering, permanent source ownership with fresh grants, competing grant IDs, exact completion states, actual termination during partial INTENT/COMPLETE writes, and expiry at the final native boundary. A report with `Completed=false` is not a passing suite.

No test or API enables live Windows Terminal font activation, edits NETZACH production settings, bypasses authorization gates, or merges a branch.
