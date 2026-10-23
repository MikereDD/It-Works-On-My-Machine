# Guarded Typezero source overlays

This tool packages explicit source changes for review against one exact Git
baseline. It does not apply a theme, run the fixture runtime, activate fonts,
alter NETZACH production settings, or merge a branch. The V2 runtime in the
milestone package remains fixture-only. Installing source never supplies runtime
authorization.

## Build

Use Python 3.10+ and Git. Keep the build checkout at the requested baseline HEAD,
with the reviewed additions/changes present in its working directory. Supply
every intended source path explicitly; the builder does not infer a diff.

```powershell
python tools/overlay/build_overlay.py `
    --repository C:\Review\It-Works-On-My-Machine `
    --base 88fd5525bdfe821d65b9a053d51ed1354f7fd1da `
    --version v2-durable-hardening-1.1.1 `
    --include Netzach/PowerShell/ThemeEngine/TerminalTransactionV2Durable-WindowsTerminal.ps1 `
    --include Netzach/PowerShell/ThemeEngine/DurableTransactionV2.md `
    --include Netzach/PowerShell/ThemeEngine/DurableHardeningV11.md `
    --include Netzach/PowerShell/ThemeEngine/tests/Test-TypezeroTerminalV2Durable.ps1 `
    --include Netzach/PowerShell/ThemeEngine/tests/README.md `
    --include tools/overlay/build_overlay.py `
    --include tools/overlay/Install-Overlay.ps1 `
    --include tools/overlay/Test-Overlay.ps1 `
    --include tools/overlay/Test-BaselineProfile.py `
    --include tools/overlay/Test-PinnedOverlay.ps1 `
    --include tools/overlay/README.md `
    --output-dir C:\Review\outputs
```

The ZIP is deterministic for identical source bytes, baseline, version, Python,
and compression runtime. It contains `overlay.json`, `Install-Overlay.ps1`,
`SHA256SUMS.txt`, and `payload/`. The adjacent `.zip.sha256` records the archive
digest. Existing output filenames are refused rather than replaced. Partial
outputs after interruption are retained; use a new output directory after
inspection.

`overlay.json` binds the version, full baseline commit, installer bytes, each
payload's SHA-256/length, existing files' expected baseline SHA-256, and the four
pinned safety modules. A null baseline hash means a new file that must not
already exist. Schema 2 requires `BaselineByteProfile=TypezeroPinnedCheckoutLF-v1`.
Baseline hashes use attributes from the pinned commit, with `core.autocrlf=false`
and `core.eol=lf`; explicit repository `eol=crlf` rules still apply. Global and
system attributes are disabled. Nonempty `info/attributes` and custom filter,
ident, or working-tree encoding attributes are refused. Ambient configuration
and modified working attributes cannot silently change expected baseline bytes.
The four pinned modules cannot be payloads and
must retain their exact baseline checkout bytes.

The builder and installer apply the same filename policy: exact-case prefixes
`Netzach/PowerShell/ThemeEngine/` and `tools/overlay/`, ASCII letters/digits plus
`._-` in path segments, `/` separators, and lowercase `.ps1`, `.py`, or `.md`
extensions. Spaces, non-ASCII names, uppercase extensions, empty segments, `.`,
`..`, trailing dots, and Windows device names are refused. Case-colliding paths
and file/directory prefix collisions are also refused.

Both sides limit a package to 1-1000 files, 4 MiB per payload or baseline backup,
64 MiB total payload, and a 1 MiB manifest. The builder checks these before
creating an output archive. Settings, fonts, binaries, `.git`, absolute paths,
traversal, alternate data streams, Windows device names, case-colliding paths,
links, and hard-linked source files are excluded.

## Verify and preview

Obtain the expected ZIP SHA-256 through a trusted channel, independently of the
download. Compare it before extraction or running any packaged code:

```powershell
Get-FileHash -LiteralPath C:\Review\typezero-v2-durable-hardening-1.1.1-overlay.zip -Algorithm SHA256
Expand-Archive -LiteralPath C:\Review\typezero-v2-durable-hardening-1.1.1-overlay.zip `
    -DestinationPath C:\Review\extracted-overlay
& C:\Review\extracted-overlay\Install-Overlay.ps1 `
    -TargetRoot C:\Review\It-Works-On-My-Machine
```

SHA-256 provides byte integrity when the expected hash is trusted. This package
has no digital signature and makes no publisher-authentication or production
authorization claim. The digest beside a ZIP is useful for transfer checks but
is not an independent trust channel.

The installer requires local Windows directories, PowerShell 7.3+, and Git.
Use a disposable, exact-baseline checkout for initial review. It defaults to a
read-only dry-run and verifies the repository root/HEAD, clean tracked files,
every touched baseline/new-file expectation, pinned files, installer hash,
payload hashes/lengths, strict manifest schema, and ordinary file identities.
Manifest rows are materialized into validated scalar records; null means an
absent new file and never an empty hash. A baseline failure reports every
mismatching row, the resolved target root and file, and expected/observed hashes.
Compare the reported target with the directory independently audited. In
particular, a stale `$stage` variable can point to an older staging checkout.
An existing untracked file at any new payload path is a collision and is refused.
Directory junctions, symlinks, reparse ancestors, and hard-linked files are
refused. All payload bytes are validated before execution.
All verification Git calls use `--no-optional-locks`, including both status
checks, so dry-run and `-Execute -WhatIf` preserve `.git/index` and other Git
metadata even when unchanged tracked files have new timestamps. Read-only
previews create no lock or backup directory.

## Execute and roll back

Execution requires `-Execute` and PowerShell `ShouldProcess` approval:

```powershell
$installed = & C:\Review\extracted-overlay\Install-Overlay.ps1 `
    -TargetRoot C:\Review\It-Works-On-My-Machine -Execute
$installed.BackupDirectory

& C:\Review\extracted-overlay\Install-Overlay.ps1 `
    -TargetRoot C:\Review\It-Works-On-My-Machine `
    -Action Rollback -BackupDirectory $installed.BackupDirectory

& C:\Review\extracted-overlay\Install-Overlay.ps1 `
    -TargetRoot C:\Review\It-Works-On-My-Machine `
    -Action Rollback -BackupDirectory $installed.BackupDirectory -Execute
```

`-Execute -WhatIf` remains a dry-run. Automation may use `-Confirm:$false` only
when the operator has already authorized the reviewed source overlay.

Execution holds an exclusive cooperative writer lock. It creates a unique
`.typezero-overlay-backups/<version>-<random-id>/` inside the explicit target.
Original bytes, the package manifest, an immutable target-bound plan, and
per-file events use `CreateNew` and durable flushes. Every original is backed up
before the first target replacement. A sibling temporary file is durably written
before replacement; original/candidate hashes are checked immediately before and
after writes. Existing backups are never overwritten. The stable lock filename
remains after release; the open exclusive handle owns the lock.

Failures retain backups and interruption evidence. Inspect the reported backup
directory, then use the same trusted package and explicit `Rollback` action.
Rollback verifies the backup plan/manifest and every original backup, then
preflights every current target before reverting anything. Each current file
must match either its exact baseline bytes or exact overlay bytes. Conflicts
refuse rollback and preserve evidence. Only an exact newly added overlay file is
deleted. Baseline files are restored from verified original bytes. Repeated
rollback is idempotent, including recovery after an interrupted partial install.
Empty newly created directories and forensic evidence remain for review.

The installer is a source-overlay utility for a trusted local operator and
cooperating writers. Hash prechecks and atomic file moves are not operating-system
compare-and-swap: hostile processes can race directory/file replacement between
checks. Its logs are local evidence, not an authenticated external audit ledger.
There is no automatic rollback, stale-lock deletion, or recovery inferred solely
from event filenames. Disk loss, malicious administrators, power-loss directory
metadata durability, and noncooperating filesystem races are outside its claim.

## Disposable verification

The v1.1.1 baseline regression also checks differing checkout defaults, frozen
committed attributes, custom-conversion refusal, and the original nine manifest
entries. Supply the retained original v1.1 manifest for that historical audit.
The full-artifact regression uses a private Git repository with a read-only
alternate object store and fresh detached linked worktrees. Its source repository
is only read. An optional `-OriginalArchive` reproduces both original failures.

```powershell
& tools/overlay/Test-Overlay.ps1 `
    -WorkRoot C:\Review\overlay-fixtures `
    -ReportPath C:\Review\overlay-verification.json

& tools/overlay/Test-PinnedOverlay.ps1 `
    -Repository C:\Review\It-Works-On-My-Machine `
    -Archive C:\Review\typezero-v2-durable-hardening-1.1.1-overlay.zip `
    -WorkRoot C:\Review\pinned-fixtures `
    -ReportPath C:\Review\pinned-verification.json
```

The test creates unique local repositories and retained evidence below the
specified work root. It checks reproducible ZIPs, output overwrite refusal,
builder/installer filename-policy parity (including spaces, uppercase extensions,
Unicode, device names, and traversal), package size limits, default dry-run,
`WhatIf`, complete `.git` byte/timestamp preservation for both install and rollback
previews, explicit install, exact rollback and replay,
collision/dirty/HEAD guards, payload/manifest/backup tampering, hard links,
junctions, cooperative concurrency, and a real child-process termination after
a deterministic partial install. The optional installer interruption barrier is
accepted only when the explicit target contains the exact disposable fixture
marker and has no Git remotes. It does not accept a production target.

Reports use `CreateNew`. Choose a fresh report filename for each run. NTFS link
and file-replacement checks can require an ordinary current-user process outside
an app filesystem sandbox; they require no administrator elevation. Retain a
failed run and inspect the reported fixture path before retrying. Keep fixture
paths short enough for Windows path-length limits.

The normal suite is strict: inability to create a link fixture fails the run.
In an app sandbox that denies native hard-link or junction creation, the explicit
test-only `-RecordUnavailableLinkTests` option may continue after that creation
step reports Access Denied. It never skips an installer validation failure or
another filesystem error. Its report records the unavailable checks and reasons,
sets `Completed=false`, and uses `Status=PassedWithUnavailableChecks`; this is
qualified verification, not a full pass. Rerun without that option on ordinary
Windows before treating the NTFS link guards as verified for this checkpoint.
