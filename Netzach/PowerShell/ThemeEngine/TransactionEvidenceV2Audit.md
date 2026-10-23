# Typezero V2 transaction/evidence baseline audit

Audited source: `MikereDD/It-Works-On-My-Machine`, draft PR #1 head
`35ad8fd38b247dd36ce0f8621fe2a102861bacdd`. This is a source audit, not a
production authorization. No NETZACH settings, installed fonts, or providers were
accessed. Baseline core source was not modified.

## Existing boundaries and reusable primitives

- `TerminalTransaction-WindowsTerminal.ps1` resolves only an existing direct
  child of the process TEMP directory named `typezero-terminal-txn-<32 hex>`.
  The fixed synthetic settings and backup paths reject redirected ancestors and
  the resolver explicitly prohibits real Windows Terminal settings.
- `TerminalReplace-WindowsTerminal.ps1` adds native Windows single-link checks,
  exact owned stage/backup names, pre-replacement hashes, collision refusal,
  `File.Replace`, and verification of both destination and displaced original.
  The code correctly describes its last-moment checks as reductions in exposure,
  not atomic compare-and-swap or protection against hostile ancestor renames.
- `TerminalTransactionV2-WindowsTerminal.ps1` uses `CreateNew`, exclusive file
  sharing, and `Flush(true)` for stage/receipt files. It retains all evidence on
  failure. Apply/restore use new, separate backup folders; restore retains the
  apply receipt and original backup. Existing diagnostic APIs intentionally
  report `OperationPhase=UNKNOWN` and never authorize recovery.
- `TerminalTransactionV2Lock-WindowsTerminal.ps1`, the mapping adapter, and replay
  reservation use the fixed `.typezero-terminal-v2.lock` with `FileShare.None`.
  Cooperating writer serialization is available; the lower-level V2 functions
  themselves remain callable without that wrapper.
- `TerminalEvidenceSealV2-WindowsTerminal.ps1` authenticates exact receipt and
  original backup bytes with a 32-byte independent key, domain-separated
  length-prefixed HMAC-SHA-256, and fixed-time verification. Key bytes are not
  stored. Authentication currently follows apply and does not establish phase.
- `TerminalRecoveryGrantV2-WindowsTerminal.ps1` rejects unknown, duplicate and
  case-ambiguous fields; binds exact fixture/folder identity, operation, receipt,
  backup, seal and expected settings hashes; requires distinct approval/evidence
  keys; verifies MAC and a maximum 15-minute UTC window. A valid grant remains
  review-only.
- `TerminalRecoveryReplayV2-WindowsTerminal.ps1` explicitly initializes a fixed
  marked fixture store, permanently reserves grant IDs using `CreateNew` and
  `Flush(true)`, and treats empty/corrupt entries as spent. It performs fresh
  locked grant/evidence/settings review, then repeats expiry validation after
  serialization immediately before reservation. Reservations authorize no
  recovery. The ledger is explicitly not deletion/rollback resistant.
- `FontMappingV2TransactionAdapter-WindowsTerminal.ps1` hashes the entire mapping
  file, rechecks it under the fixed lock, and holds a read handle denying
  write/delete through preparation and replacement. Preserve that invariant.

## Durable transition/recovery gap

An intent receipt and a correct receipt/backup seal cannot distinguish a prepared
candidate, an attempted replacement, a verified replacement, and a completed
recovery. The current code has no authenticated append-only phase journal, no
strict phase adjacency, no journal sequence/previous-record binding, no recovery
execution API, and no atomic coupling between grant reservation and a recovery
phase. A crash after replacement but before verification/completion necessarily
leaves phase unknown. Existing observation APIs correctly refuse to infer phase
from filenames or observed matching hashes.

The evidence MAC does not independently bind transaction folder identity or a
phase history; moving compatible receipt/backup/seal evidence can therefore not
serve as durable transaction identity proof. The existing apply receipt parser
rejects duplicate fields but accepts extra fields; new durable records should
instead require an exact schema and use strict encoding. Existing parsers and
result semantics should remain unchanged for compatibility.

## Requirements for the next fixture milestone

1. Add a separate fixture-only module. Bind authenticated records to version,
   canonical fixture/folder identity, operation, exact source/candidate evidence,
   monotonically increasing sequence, predecessor digest, and explicit phase.
   Require exact schemas and valid adjacent transitions. Never promote an old
   receipt, seal, or reservation into proof of durable completion.
2. Perform executed transitions under the shared fixed lock after `-Execute`
   and ShouldProcess; previews and WhatIf must create no lock/evidence files.
   Revalidate all evidence/state under lock and retain uncertainty after partial
   writes or interruption. Reject collisions, links, malformed and extra entries.
3. Require distinct independent approval/evidence authority for recovery, preserve
   the final expiry check immediately before spending a grant, spend each ID once,
   and record authenticated intent before settings mutation. An interrupted ID
   stays spent. Resume must be bound to that recorded operation and must never
   accept a fresh grant as a way to overwrite ambiguous prior evidence.
4. Recovery must preserve the original apply evidence and a separate displaced
   applied backup. Verify both sides and journal completion only after successful
   verification. Matching bytes after a crash support conservative assessment;
   they cannot by themselves certify completed phase or authorization.
5. Scope guarantees accurately: process interruption and cooperating-process
   serialization on local Windows NTFS; file flushing is not a portable directory
   fsync or guarantee against power loss, hostile rename, or ledger rollback.

## Useful deterministic regression patterns

- `Test-TypezeroTerminalV2RecoveryReplay.ps1` already demonstrates copied-function
  instrumentation with unique reversible anchors; fake clock interposition
  tests expiry under the held lock after evidence review and serialization.
  Production APIs expose no clock/callback bypass parameters.
- The replay, interruption and seal interruption suites start explicit child
  processes with hidden windows and validate nonce + PID + process start time
  before terminating only the test-owned worker. Extend this pattern around
  reservation, durable intent, replacement, verification, and completion.
- Reuse complete fixture tree snapshots to prove preview, WhatIf, refusal and
  malformed inputs do not mutate settings or evidence. Keep tampering cases for
  record/payload/MAC, wrong keys, cross-folder copies, unknown/duplicate/case
  fields, gaps/order/truncation, partial new files, conflicting settings/backup,
  occupied/shared locks, concurrent same grant attempts, expired grants and
  replay across processes.
- Preserve `Test-TypezeroV1RestoreOwnership.ps1`, readiness/legacy execute guards,
  theme selection/preview, complete mapping binding, V2 lifecycle/locking/seal/
  recovery suites and coordinator suites. Do not run or weaken the historical
  `Test-TypezeroFixtureSafety.ps1` pins.

## Preservation checks

V1 ownership fixes are in `FontActivation-WindowsTerminal.ps1`: editable V1
receipts never own `TYPEZERO_FONT_V2`, and ownership is rechecked after review.
V2 expiry fixes are in the locked replay reservation final UTC check. Pinned
modules, production live gates, theme/preview features and NETZACH settings must
remain unchanged. This milestone confers no live font activation authority and
does not include merging to main.
