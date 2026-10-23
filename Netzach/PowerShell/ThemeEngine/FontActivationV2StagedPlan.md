# Guarded V2 font activation: staged safety checkpoint

Baseline: GitHub `feature/themeengine-font-management`, commit `b7f36aa`.

Live Windows Terminal font activation remains disabled. The audit found that
recovery grants were review-only, replay protection was explicitly absent, and
authenticated evidence did not establish a durable operation phase. The legacy
V2 writer could still be called directly even though the CLI rejected live
apply/restore. Enabling it would bypass the newer safety model.

## Implemented protections

- Legacy V2 activation and RESTORE reject `-Execute` before planning, provider
  lookup, confirmation, or I/O. Enabled mappings and `-Confirm:$false` do not
  grant authority. Read-only previews remain available.
- A separate read-only readiness API reads the selected saved V2 preference,
  checks strict JSON fields and types, rejects duplicate/case-ambiguous keys,
  invalid IDs, unsupported overrides, invalid font sizes/weights/families,
  malformed UTF-8 and BOMs, and reports full config/settings SHA-256 snapshots.
  Optional expected hashes reject stale selections/settings. Input file
  snapshots reject redirected/hard-linked paths. They are observations,
  never authorization or filesystem race immunity for a later live writer.
- The fixture mapping adapter pins the complete configuration, takes the same
  fixed V2 transaction lock, validates the config again, and retains a read
  handle denying writes/deletion through candidate preparation and replacement.
  A changed mapping, integration flag, or unrelated config byte is refused.
- Fixture grant reservation freshly revalidates the authenticated grant,
  evidence, settings, and expiry under the shared V2 lock. A fixed fixture-local
  store uses immutable `CreateNew` reservations and flushed bytes. Existing,
  partial, corrupt, or crash-surviving reservations are never recycled. No
  restoration, arbitrary callback, key persistence, or live target is supported.
- Four hash-pinned safety modules explicitly use canonical LF checkout bytes.
  Their expected hashes and source content are unchanged. The interruption
  harness normalizes its instrumentation anchor to the same newline convention
  and still requires a unique exact match.

The existing theme switcher, preview UI, selection consent, mapping Enabled
state, V2 ownership guard, byte-exact backups, and fixture path fences remain.
No live settings were used as fixture input or changed during validation.

## Read-only readiness usage

Load these modules from the audited checkout; pass explicit paths. This function
does not initialize application directories or invoke providers/theme commands.

```powershell
. .\TerminalReplace-WindowsTerminal.ps1
. .\FontWriter-WindowsTerminal.ps1
. .\FontActivationReadinessV2-WindowsTerminal.ps1

$plan = Get-TypezeroTerminalFontActivationReadinessV2 `
    -ThemeId kanagawa-paper `
    -ConfigPath (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\font-windows-terminal.json') `
    -SettingsPath (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
$plan
```

Config and settings snapshots are captured independently; they do not prove
simultaneous/current state, installed-font availability, or a valid theme/color
pair. A future writer must validate those again under its live transaction lock.

The result is always `Status=BLOCKED`, `ReadOnly=True`,
`FontActivated=False`, `RecoveryAuthorized=False`,
`ReplayProtectionEstablished=False`, `LiveActivationAuthorized=False`, and
`OperationPhase=UNKNOWN`. Disabled integration and existing V2/foreign font
ownership add blockers. There is no execution/authorization switch. A saved
preference, successful fixture run, valid review, or returned plan must never
be accepted as a live grant.

## Fixture replay reservation contract

Load the dependencies used by `Test-TypezeroTerminalV2RecoveryReplay.ps1`.
`Initialize-TypezeroOfflineTerminalV2ReplayStore` previews by default and
requires `-Execute` plus ShouldProcess to initialize a fresh fixed store.
`Reserve-TypezeroOfflineTerminalV2RecoveryGrant` also previews by default and
requires an already initialized store, independent approval/evidence keys,
the grant JSON and MAC, `-Execute`, and ShouldProcess to reserve an ID.

A successful reservation reports `RESERVED_FIXTURE_ONLY`,
`GrantReserved=True`, `GrantConsumed=False`,
`ReplayProtectionScope=CooperatingFixtureProcessesOnly`, and
`TrustedDurableProductionLedger=False`. The replay flag applies only to that
fixture reservation. Every result keeps `RecoveryAllowed=False`,
`RecoveryAuthorized=False`, and `LiveActivationAuthorized=False`.

This fixture store is neither deletion/rollback resistant nor an independent
production authority. Path checks/locks protect cooperating fixture processes;
hostile ancestor renames and arbitrary filesystem mutation remain outside that
guarantee. Do not remove/recreate a store to retry a grant. Preserve all evidence
after uncertainty, including an empty reservation left by a terminated worker.
The original read-only grant-review API and its false flags are unchanged.

## Required stages before any production enablement

1. Design an independent production grant issuer/key custody and a trusted,
   durable ledger resistant to deletion/rollback. Bind authorization to exact
   config, theme/colors, settings/profile identity, evidence, operation and
   expiry. Never trust Boolean flags supplied by a caller.
2. Implement fixture-only authorized recovery that couples one-time grant
   reservation and durable authenticated operation transitions under the same
   lock. Uncertain/crashed operations must require review and preserve evidence;
   a receipt hash or HMAC over bytes alone cannot certify phase/completion.
3. Rehearse the full selected-preference apply/recovery lifecycle with actual
   process termination before/after reservation, staging, backup, replacement,
   verification and completion. Exercise wrong keys, stale/foreign changes,
   duplicate fields, links, concurrent config/settings edits, replay, rollback,
   partial evidence, denied consent, disabled integration and WhatIf.
4. Implement the guarded live transaction only after those contracts pass review:
   pin target/ancestor identity through native handles, serialize all cooperating
   writers, revalidate the complete input and consent under lock, preserve
   exact original bytes and authenticated evidence, use verified replacement,
   and verify resulting font plus all unrelated settings. Existing V2 or foreign
   ownership requires separately authorized recovery; never remove its marker
   or use the legacy writer to force a new selection.
5. Review fixture evidence and prepare an explicit NETZACH opt-in rollout with
   a verified backup and separately authorized recovery procedure. Keep the
   production gate false until these prerequisites and authorization are met.
   No merge to main is part of this checkpoint.

## Verification

Use PowerShell 7 on Windows with local NTFS and current-user permissions. Native
replacement/link/ACL suites may require execution outside the Codex filesystem
sandbox; their destinations remain fenced disposable fixtures. Retain the
fixture directories and test logs. Never weaken an integrity pin to make a test
pass. `Test-TypezeroFixtureSafety.ps1` pins historical private evidence and is
not a current-checkout regression runner.

Relevant suites include readiness/legacy guards, theme selection, mapping V2,
mapping transaction adapter, V2 lifecycle/locking/evidence/interruption,
recovery assessment/grant review, fixture replay reservation, and coordinator
lifecycle/rehearsal/process-crash suites. Report actual outcomes from each run;
passing fixture tests grants no production authorization.
