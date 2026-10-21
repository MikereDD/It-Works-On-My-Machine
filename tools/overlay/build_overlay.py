#!/usr/bin/env python3
"""Build a deterministic, explicit-file source overlay. Uses only Python stdlib."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import zipfile

PROTECTED = (
    "Netzach/PowerShell/ThemeEngine/TypezeroIntegrationPreflight.ps1",
    "Netzach/PowerShell/ThemeEngine/TerminalTransactionV2-WindowsTerminal.ps1",
    "Netzach/PowerShell/ThemeEngine/TerminalReplace-WindowsTerminal.ps1",
    "Netzach/PowerShell/ThemeEngine/TerminalEvidenceSealV2-WindowsTerminal.ps1",
)
PREFIXES = ("Netzach/PowerShell/ThemeEngine/", "tools/overlay/")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def git(root: Path, *args: str, check: bool = True) -> bytes:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
    if check and result.returncode:
        raise ValueError(result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def safe_path(value: str) -> str:
    parts = PurePosixPath(value).parts
    if (not value or "\\" in value or ":" in value or value.startswith("/")
            or str(PurePosixPath(value)) != value
            or any(p in (".", "..") or p.endswith((".", " ")) for p in parts)
            or any(re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\..*)?", p) for p in parts)
            or not value.startswith(PREFIXES)
            or PurePosixPath(value).suffix.lower() not in (".ps1", ".py", ".md")):
        raise ValueError(f"Forbidden overlay path: {value!r}")
    if value in PROTECTED:
        raise ValueError(f"Pinned module cannot be overlaid: {value}")
    return value


def regular_bytes(root: Path, relative: str) -> bytes:
    candidate = root / relative
    for path in (candidate, *candidate.parents):
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError(f"Link/reparse point forbidden: {path}")
        if path == root:
            break
    info = candidate.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError(f"Expected ordinary single-link file: {candidate}")
    if info.st_size > 4 * 1024 * 1024:
        raise ValueError(f"File too large: {candidate}")
    return candidate.read_bytes()


def baseline_bytes(root: Path, base: str, relative: str) -> bytes | None:
    tracked = git(root, "ls-tree", "-z", base, "--", relative)
    if not tracked:
        return None
    if not tracked.startswith(b"100644 ") and not tracked.startswith(b"100755 "):
        raise ValueError(f"Baseline path is not an ordinary Git file: {relative}")
    return git(root, "cat-file", "--filters", f"--path={relative}", f"{base}:{relative}")


def build(root: Path, base: str, version: str, includes: list[str], output: Path) -> dict:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", version):
        raise ValueError("Version must be 1-80 safe filename characters.")
    base = git(root, "rev-parse", "--verify", f"{base}^{{commit}}").decode().strip()
    if git(root, "rev-parse", "HEAD").decode().strip() != base:
        raise ValueError("Build checkout HEAD must equal the requested baseline.")
    paths = sorted(safe_path(x) for x in includes)
    if not paths or len({x.casefold() for x in paths}) != len(paths):
        raise ValueError("Explicit include list must be nonempty and case-insensitively unique.")
    for i, path in enumerate(paths):
        if any(other.casefold().startswith(path.casefold() + "/") for other in paths[i + 1:]):
            raise ValueError("File/directory prefix collision.")
    payload: dict[str, bytes] = {}
    entries = []
    for relative in paths:
        data = regular_bytes(root, relative)
        before = baseline_bytes(root, base, relative)
        if before == data:
            raise ValueError(f"Unchanged file in overlay: {relative}")
        entries.append({"Path": relative, "BeforeSha256": digest(before) if before is not None else None,
                        "AfterSha256": digest(data), "Length": len(data)})
        payload[f"payload/{relative}"] = data
    protected = []
    for relative in PROTECTED:
        before = baseline_bytes(root, base, relative)
        if before is not None:
            if digest(regular_bytes(root, relative)) != digest(before):
                raise ValueError(f"Pinned baseline module changed: {relative}")
            protected.append({"Path": relative, "Sha256": digest(before)})
    installer = regular_bytes(root, "tools/overlay/Install-Overlay.ps1")
    manifest = {"SchemaVersion": 1, "Kind": "TypezeroGuardedSourceOverlay", "Version": version,
                "BaselineCommit": base, "FixtureOnlyRuntime": True, "LiveFontActivation": False,
                "InstallerSha256": digest(installer), "ProtectedFiles": protected, "Files": entries}
    payload["overlay.json"] = (json.dumps(manifest, indent=2, ensure_ascii=True) + "\n").encode()
    payload["Install-Overlay.ps1"] = installer
    sums = "".join(f"{digest(data)}  {name}\n" for name, data in sorted(payload.items()))
    payload["SHA256SUMS.txt"] = sums.encode("ascii")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"typezero-{version}-overlay.zip"
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    if archive.exists() or checksum.exists():
        raise ValueError("Output already exists; choose a new version/output directory.")
    # Exclusive create also prevents silently replacing an earlier deliverable.
    try:
        with archive.open("xb") as stream, zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED,
                                                         compresslevel=9) as bundle:
            for name, data in sorted(payload.items()):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, data, compresslevel=9)
        with checksum.open("x", encoding="ascii", newline="\n") as stream:
            stream.write(f"{digest(archive.read_bytes())}  {archive.name}\n")
    except BaseException:
        # Preserve partial outputs as interruption evidence; never overwrite them.
        raise
    return {"Archive": str(archive.resolve()), "Sha256": digest(archive.read_bytes()),
            "ManifestSha256": digest(payload["overlay.json"]), "Files": len(entries),
            "BaselineCommit": base, "Version": version}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--include", action="append", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build(args.repository.resolve(), args.base, args.version, args.include, args.output_dir.resolve())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Overlay build refused: {error}\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
