# Typezero ThemeEngine - Windows Terminal Fonts

Status: EXPERIMENTAL / OPT-IN

Windows Terminal font management is separate from
ThemeEngine's existing color and theme management.

## Commands

| Command | Behavior |
| --- | --- |
| `font list` | Inspect installed fonts |
| `font current` | Inspect current Terminal font |
| `font test <theme-id>` | Inspect theme.conf font metadata |
| `font plan <theme-id>` | Structured typography preview |
| `font preview <theme-id>` | Readable typography comparison |
| `font status` | Inspect integration status |
| `font mappings` | Inspect configured mappings |
| `font map <theme-id> "<font family>"` | Write a V1 mapping |
| `font theme-preview` | Preview themes/fonts; explicitly apply a theme and optionally save a V2 preference |
| `font check-apply <theme-id>` / `font check-restore` | Inspect an in-memory font candidate/restoration |
| `font apply <theme-id> --fixture` / `font restore --fixture <test-root>` | Disposable fixture operations only |

Run commands through ThemeEngine.ps1 in PowerShell 7.

Planning and previewing do not activate fonts.

The main ThemeEngine script may initialize its
application directory, even for inspection commands.

The `font map` command changes mapping configuration.
It may also create a configuration backup.

## Mapping configuration

Default location:

`%LOCALAPPDATA%\Typezero\ThemeEngine\font-windows-terminal.json`

Mappings contain an integration-enabled flag.

V1 maps theme IDs to font-family names. Font size
and weight are preserved in the V1 planning model.

V2 supports family, size, and weight. It remains
experimental and requires a separate configuration
path for its backend activation interface.

`font map` writes V1 mappings. The theme/font preview's optional preference
checkbox saves V2 family, size, and weight while preserving `Enabled`. New
preferences default to disabled. Saving a preference does not activate it.

Theme metadata inspection and Terminal mapping
inspection are separate operations.

## Activation

The main CLI refuses live font apply and RESTORE. Its `--fixture` commands
target disposable test data. The theme/font selection workflow continues to
use the existing public theme command and never invokes font activation or
recovery. An active `TYPEZERO_FONT_V2` marker blocks theme selection before
broader appearance writes, and the legacy Terminal color guard remains intact.

The historical V2 activation and RESTORE entry points now unconditionally
refuse `-Execute`, including `-WhatIf`, before provider lookup or filesystem
access. Their read-only previews remain available. Confirmation and an enabled
mapping cannot authorize the old writer. V1 is unchanged.

The existing Terminal color writer must preserve
the TYPEZERO_FONT_V2 ownership-marker guard.

## Backup and RESTORE

V1 and V2 have separate backup and RESTORE paths.

RESTORE replaces the complete Windows Terminal
settings document, not just its font properties.

Receipt authenticity is not independently verified.

Known limitations include:

- Unauthenticated receipt provenance
- Ancestor-path and filesystem race conditions
- Concurrent changes to Terminal settings
- Incomplete transaction recovery
- V1 JSON document reserialization

Existing link, checksum and snapshot checks reduce
certain risks but do not eliminate these limitations.

Recovery must not depend on the current mapping's
integration-enabled flag.

## Verification

Synthetic regressions have validated:

- V1 and V2 font planning and previews
- Disabled-integration execution rejection
- Enabled-integration WhatIf handling
- Preservation of live settings during testing

Production font activation and RESTORE were not
performed in these Phase 56 milestones.

No automatic font switching is permitted by the
new plan and preview commands.

Keep this feature experimental until its remaining
safety limitations are resolved.

## Guarded V2 development checkpoint

See [FontActivationV2StagedPlan.md](FontActivationV2StagedPlan.md) for the audit,
read-only readiness API, fixture replay reservation, validation, and release
prerequisites. No production activation or recovery is enabled at this checkpoint.
