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
