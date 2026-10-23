# Typezero V2 Durable Hardening v1.1

Baseline: `88fd5525bdfe821d65b9a053d51ed1354f7fd1da` (draft PR #1).
Overlay version: `v2-durable-hardening-1.1.1`.

This source overlay remains fixture-only. It supplies no live font activation,
production recovery authorization, grant issuer, automatic rollback, journal
repair, or production replay ledger. The ThemeEngine UI and four pinned safety
modules are preserved. No merge or push is part of this deliverable.

## Changes

1. Durable APPLY and RESTORE validate exact UTF-8 evidence/candidate byte sizes
   before opening a persistent fixture lock, then repeat preparation under the
   lock. All four actual canonical authenticated phase records are precomputed
   before INTENT. RESTORE stages retained, bounded, hash-checked source bytes.
2. Installer verification uses Git's `--no-optional-locks` so default previews
   and WhatIf do not refresh/write the Git index. Regression snapshots include
   all Git metadata bytes, file/directory entries and write/creation times.
3. Builder and installer share the same case-sensitive path grammar, lowercase
   extensions, ASCII character set, and traversal/device-name refusals. Builder
   limits also match installer payload/backup/count/aggregate/manifest limits.
4. A private RESTORE-only replacement routine preserves every pinned primitive
   guard and adds an authenticated UTC deadline check immediately before the
   native call, after final filesystem and hash validation. The pinned legacy
   replacement file is untouched. This does not claim atomic deadline/CAS or
   protection from hostile filesystem races.

## Verification

### Packaging correction in v1.1.1

The durable runtime and its regression suite retain the exact v1.1 bytes.
The overlay builder now binds baseline hashes to the pinned commit's attributes
and an explicit LF-default checkout profile; PowerShell files still follow the
repository's explicit CRLF rule. This corrects the Python builder baseline hash
that v1.1 accidentally derived from ambient Windows checkout defaults.

The NETZACH durable-module rejection was a separate, valid refusal: the actual
installer invocation targeted the older safety-staging directory, whose durable
module contained LF bytes, while the independently audited review worktree had
the expected CRLF bytes. v1.1.1 keeps exact byte validation and reports the
resolved target and all mismatching hashes. Strict scalar manifest rows and new
regressions cover null/string/type confusion. No alternate baseline hashes or
normalization of target files are accepted.

`Test-BaselineProfile.py` tests configuration-independent baseline derivation.
`Test-PinnedOverlay.ps1` tests the exact pinned baseline in fresh detached Windows
Git worktrees, including original-package refusal, new-package previews, source
installation, rollback and Git metadata preservation.

Run the durable and overlay suites in fresh Windows PowerShell 7.3+ processes on
local NTFS, with disposable fixture storage. Preserve every report and fixture.
The packaged verification report distinguishes actual passed results from any
environment-blocked attempts. Never infer a passing suite from parser checks or
historical v1.0 counts. The historical fixture-safety harness must not be weakened
or run against the new checkout merely to satisfy old integrity pins.

The expanded durable suite includes completed RESTORE grant/MAC/reservation/source
tampering; fresh-grant reuse of a completed source with applied bytes reintroduced;
different-grant process contention; exact COMPLETE/INVALID_EVIDENCE decisions;
real process termination during partial journal writes; and native-boundary expiry.

See `DurableTransactionV2.md` for the full runtime contract and
`tools/overlay/README.md` for guarded source installation and rollback. The release
includes separate NETZACH instructions, SHA-256 sums, regression logs/results,
source hashes, and a baseline-bound overlay manifest.

## Remaining boundaries

The journal/replay stores remain local and deletion/rollback-sensitive. Legacy
entry points keep their older contracts. Keys remain caller-managed memory.
Flushing files does not establish directory-entry fsync or power-loss durability.
Filesystem prechecks followed by pathname replacement are not atomic CAS. None
of these fixture limitations is promoted to a production guarantee by v1.1.
