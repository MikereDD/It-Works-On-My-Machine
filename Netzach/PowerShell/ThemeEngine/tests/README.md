# Typezero ThemeEngine Safety Tests

## Historical fixture-safety harness

Test-TypezeroFixtureSafety.ps1 preserves the original
57F.23.10.09.06 safety validation checkpoint.

Historical HEAD: 637354b66c757827830dd164e2a62115e11ce04c

The harness intentionally pins the original Git status,
source SHA-256 values, and private fixture environment.
It is not a general-purpose test runner and must not be
modified merely to pass against a newer checkout.

## Validated behavior

- Nine foreign-edit and stale-input refusal cases.
- Three journal-corruption refusal cases.
- Protected-path integrity verification.
- Historical journal preservation.
- No recovery or live activation authorization.

## Development checkpoint

Commit 4b34552 contains the guarded coordinator and font
development foundation.

Milestone 57F.23.10.09.08 completed a separate installed-copy
regression with twelve passing fixture-only cases.

The final regression harness and report are retained in
the private NETZACH evidence archive, not in this repository.

RecoveryAuthorized=False
LiveActivationAuthorized=False

## Lifecycle assessment suite

`Test-TypezeroCoordinatorFixtureLifecycle.ps1` covers milestone
57F.23.10.09.09.02 with newly created, isolated synthetic fixtures. It accepts
optional `-ReportPath` for a JSON report and retains fixtures without cleanup.
Run on Windows with PowerShell 7.3 or later and local NTFS TEMP storage.
The assessment reports journal observations, receipt validity, artifact
consistency, and blockers; it keeps both authorization flags false.
See [TerminalCoordinatorLifecycle.md](../TerminalCoordinatorLifecycle.md) for
contracts, NETZACH inspection usage, and the existing preflight LF hash pin.
Validation outcomes belong in the report from the actual suite run.

## Coordinator apply and restore rehearsal suites

Milestone `57F.23.10.09.09.03` adds the separate fixture-only runner
`Test-TypezeroCoordinatorFixtureRehearsal.ps1` and actual worker-termination
runner `Test-TypezeroCoordinatorFixtureProcessCrash.ps1`. Each creates fresh
synthetic private TEMP fixtures, retains evidence, accepts a new `-ReportPath`,
and verifies source hashes. Run as the current Windows user with PowerShell
7.3+ and local NTFS TEMP, outside the Codex filesystem sandbox.
See [TerminalCoordinatorRehearsal.md](../TerminalCoordinatorRehearsal.md) for
the API, dependency contracts, failure semantics, and NETZACH commands.
Neither runner grants recovery or live activation authorization.

## Selected V2 preference activation safety checkpoint

`Test-TypezeroFontActivationReadinessV2.ps1` checks strict read-only snapshot
validation, stale preference/settings refusal, ownership blockers, false
authorization flags, and legacy V2 Execute refusal before provider lookup.
It uses synthetic files and inert legacy provider stubs only.

`Test-TypezeroFontMappingV2TransactionAdapter.ps1` additionally checks full
configuration binding under the shared transaction lock and a retained config
read handle. Changed Enabled, selected/unrelated mapping bytes, preview and
WhatIf are covered while production settings remain unchanged.

`Test-TypezeroTerminalV2RecoveryReplay.ps1` tests explicit fixture-store
initialization and one-time authenticated grant reservations. It includes
cross-process replay/races, occupied locks, stale grants, partial/corrupt
tombstones, worker termination after CreateNew, and linked-path refusal.
Reservations grant no recovery or live activation permission. Production
deletion/rollback-resistant replay storage is still required.

See [FontActivationV2StagedPlan.md](../FontActivationV2StagedPlan.md).
