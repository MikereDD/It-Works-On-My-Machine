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
    --base 35ad8fd38b247dd36ce0f8621fe2a102861bacdd `
    --version v2-durable-fixture-1.0.0 `
    --include Netzach/PowerShell/ThemeEngine/TerminalTransactionV2Durable-WindowsTerminal.ps1 `
    --include Netzach/PowerShell/ThemeEngine/DurableTransactionV2.md `
    --include Netzach/PowerShell/ThemeEngine/TransactionEvidenceV2Audit.md `
    --include Netzach/PowerShell/ThemeEngine/tests/Test-TypezeroTerminalV2Durable.ps1 `
    --include tools/overlay/build_overlay.py `
    --include tools/overlay/Install-Overlay.ps1 `
    --include tools/overlay/Test-Overlay.ps1 `
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
already exist. Baseline hashes use Git's checkout filters, including the
repository's line-ending rules. The four pinned modules cannot be payloads and
must retain their exact baseline checkout bytes.

Only `.ps1`, `.py`, and `.md` under `Netzach/PowerShell/ThemeEngine/` and
`tools/overlay/` are accepted. Settings, fonts, binaries, `.git`, absolute paths,
traversal, alternate data streams, Windows device names, case-colliding paths,
links, and hard-linked source files are excluded.

## Verify and preview

Obtain the expected ZIP SHA-256 through a trusted channel, independently of the
download. Compare it before extraction or running any packaged code:

```powershell
Get-FileHash -LiteralPath C:\Review\typezero-v2-durable-fixture-1.0.0-overlay.zip -Algorithm SHA256
Expand-Archive -LiteralPath C:\Review\typezero-v2-durable-fixture-1.0.0-overlay.zip `
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
An existing untracked file at any new payload path is a collision and is refused.
Directory junctions, symlinks, reparse ancestors, and hard-linked files are
refused. All payload bytes are validated before execution.

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

```powershell
& tools/overlay/Test-Overlay.ps1 `
    -WorkRoot C:\Review\overlay-fixtures `
    -ReportPath C:\Review\overlay-verification.json
```

The test creates unique local repositories and retained evidence below the
specified work root. It checks reproducible ZIPs, output overwrite refusal,
traversal, default dry-run, `WhatIf`, explicit install, exact rollback and replay,
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
