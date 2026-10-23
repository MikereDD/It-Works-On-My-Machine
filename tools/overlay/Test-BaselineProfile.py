#!/usr/bin/env python3
"""Retained, disposable regressions for the exact overlay baseline byte profile."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
import zipfile

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("overlay_baseline_builder", Path(__file__).with_name("build_overlay.py"))
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)
PINNED = "88fd5525bdfe821d65b9a053d51ed1354f7fd1da"
PYTHON_PATH = "tools/overlay/ProfileFixture.py"
PS_PATH = "Netzach/PowerShell/ThemeEngine/ProfileFixture.ps1"
PROTECTED_PATH = BUILDER.PROTECTED[0]
PYTHON_BYTES = b"# baseline-python\nprint('fixture only')\n"
PS_BYTES = b"# baseline-powershell\n'fixture only'\n"
PROTECTED_BYTES = b"# protected-lf-fixture\n"


def git(root: Path, *args: str) -> bytes:
    environment = os.environ.copy()
    environment.update({"GIT_AUTHOR_DATE": "2020-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2020-01-01T00:00:00Z"})
    result = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *args], capture_output=True, env=environment)
    if result.returncode:
        raise AssertionError(result.stderr.decode(errors="replace"))
    return result.stdout


def write(root: Path, relative: str, data: bytes) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)


def fixture(root: Path, extra_attributes: str = "") -> str:
    root.mkdir()
    git(root, "init", "--quiet")
    for name, value in (("user.name", "Disposable Baseline Profile"), ("user.email", "profile@example.invalid"),
                        ("commit.gpgsign", "false"), ("core.autocrlf", "false"), ("core.eol", "lf")):
        git(root, "config", name, value)
    attributes = ("* text=auto\n*.ps1 text eol=crlf\n" + PROTECTED_PATH + " text eol=lf\n" + extra_attributes)
    write(root, ".gitattributes", attributes.encode())
    write(root, PYTHON_PATH, PYTHON_BYTES)
    write(root, PS_PATH, PS_BYTES)
    write(root, PROTECTED_PATH, PROTECTED_BYTES)
    write(root, "tools/overlay/Install-Overlay.ps1", b"# disposable installer content only\n")
    git(root, "add", ".")
    git(root, "commit", "--quiet", "-m", "Disposable baseline profile")
    return git(root, "rev-parse", "HEAD").decode().strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--legacy-manifest", type=Path, required=True)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    run = args.work_root.resolve() / ("baseline-profile-" + uuid.uuid4().hex)
    run.mkdir(parents=True)
    checks = []
    audit = []

    def check(condition: bool, name: str, **evidence) -> None:
        checks.append({"Name": name, "Passed": bool(condition), **evidence})
        if not condition:
            raise AssertionError(name)

    def refusal(call, phrase: str, name: str) -> None:
        try:
            call()
        except ValueError as error:
            check(phrase in str(error), name, Error=str(error))
        else:
            check(False, name)

    try:
        root = run / "profile-source"
        base = fixture(root)
        expected = {PYTHON_PATH: PYTHON_BYTES, PS_PATH: PS_BYTES.replace(b"\n", b"\r\n"),
                    PROTECTED_PATH: PROTECTED_BYTES}
        global_attributes = run / "global-attributes"
        global_attributes.write_bytes(b"*.py text eol=crlf\n*.ps1 text eol=lf\n")
        git(root, "config", "core.attributesFile", str(global_attributes))
        # The source checkout is deliberately LF for this .py file. Ambient Git
        # defaults must never turn its manifest BeforeSha256 into a CRLF digest.
        for autocrlf in ("true", "false", "input"):
            for eol in ("lf", "crlf"):
                git(root, "config", "core.autocrlf", autocrlf)
                git(root, "config", "core.eol", eol)
                for relative, data in expected.items():
                    actual = BUILDER.baseline_bytes(root, base, relative)
                    check(actual == data, f"Pinned profile {autocrlf}/{eol}: {relative}",
                          Sha256=BUILDER.digest(actual), Length=len(actual))
        (root / ".gitattributes").write_bytes(b"* -text\n*.py text eol=crlf\n*.ps1 text eol=lf\n")
        for relative, data in expected.items():
            check(BUILDER.baseline_bytes(root, base, relative) == data,
                  "Working attributes cannot change pinned baseline: " + relative)
        (root / PYTHON_PATH).write_bytes(b"# changed candidate\n")
        first = BUILDER.build(root, base, "profile-v1", [PYTHON_PATH], run / "build-one")
        git(root, "config", "core.autocrlf", "true")
        git(root, "config", "core.eol", "crlf")
        second = BUILDER.build(root, base, "profile-v1", [PYTHON_PATH], run / "build-two")
        check(first["Sha256"] == second["Sha256"], "Reproducible ZIP ignores ambient baseline checkout configuration",
              Sha256=first["Sha256"])
        with zipfile.ZipFile(first["Archive"]) as archive:
            manifest = json.loads(archive.read("overlay.json"))
        check(manifest["SchemaVersion"] == 2 and manifest["BaselineByteProfile"] == BUILDER.BASELINE_BYTE_PROFILE,
              "Schema 2 declares exactly one baseline byte profile")
        info_attributes = root / ".git/info/attributes"
        info_attributes.write_bytes(b"# even comment-only local overrides require explicit removal\n")
        refusal(lambda: BUILDER.baseline_bytes(root, base, PYTHON_PATH), "info/attributes",
                "Nonempty local info/attributes is refused")
        for attribute in ("filter=blocked-fixture", "ident", "working-tree-encoding=UTF-8"):
            blocked = run / ("blocked-" + attribute.split("=")[0])
            blocked_base = fixture(blocked, PYTHON_PATH + " " + attribute + "\n")
            marker = blocked / "filter-was-executed"
            if attribute.startswith("filter="):
                command = "python -c \"from pathlib import Path; Path('" + marker.as_posix() + "').write_text('executed')\""
                git(blocked, "config", "filter.blocked-fixture.smudge", command)
                git(blocked, "config", "filter.blocked-fixture.required", "true")
            refusal(lambda: BUILDER.baseline_bytes(blocked, blocked_base, PYTHON_PATH), "Unsupported baseline",
                    "Unsupported conversion is refused before filters: " + attribute)
            if attribute.startswith("filter="):
                check(not marker.exists(), "Configured external smudge filter is never executed")

        repository = args.repository.resolve()
        check(git(repository, "rev-parse", "HEAD").decode().strip() == PINNED, "Real audit checkout HEAD equals exact 88fd552")
        legacy = json.loads(args.legacy_manifest.read_bytes())
        check(legacy["BaselineCommit"] == PINNED and len(legacy["Files"]) == 9, "Original v1.1 manifest has nine pinned-baseline entries")
        differences = []
        for row in legacy["Files"]:
            data = BUILDER.baseline_bytes(repository, PINNED, row["Path"])
            canonical = BUILDER.digest(data) if data is not None else None
            audit.append({"Path": row["Path"], "OriginalBeforeSha256": row["BeforeSha256"],
                          "CanonicalBeforeSha256": canonical, "Length": None if data is None else len(data)})
            if canonical != row["BeforeSha256"]:
                differences.append(row["Path"])
        check(differences == ["tools/overlay/build_overlay.py"], "Exactly Python differs from original nine-row v1.1 baseline manifest",
              DifferingPaths=differences)
        python_row = next(row for row in audit if row["Path"] == "tools/overlay/build_overlay.py")
        check(python_row["CanonicalBeforeSha256"] == "C693C4A433520E87352D46DA27BCFFA450D3AFDAE31E45A6AD66F07D40E152EE",
              "Canonical Python baseline matches NETZACH-reported LF bytes")
        durable = next(row for row in audit if row["Path"].endswith("/TerminalTransactionV2Durable-WindowsTerminal.ps1"))
        check(durable["OriginalBeforeSha256"] == durable["CanonicalBeforeSha256"] ==
              "EA94E3C1E691CE583DA72887D86617C3BB4FE1A5E63EAF344E2E6A0031FF0C16",
              "Durable-module baseline already matched and is independent of Python discrepancy")
        status = "Passed"
        error = None
    except Exception as failure:
        status = "Failed"
        error = str(failure)
    report = {"Status": status, "Completed": status == "Passed", "BaselineByteProfile": BUILDER.BASELINE_BYTE_PROFILE,
              "PinnedCommit": PINNED, "RunDirectory": str(run), "PassedChecks": sum(row["Passed"] for row in checks),
              "Checks": checks, "OriginalManifestAudit": audit, "Error": error}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({key: report[key] for key in ("Status", "PassedChecks", "RunDirectory", "Error")}, indent=2))
    if status != "Passed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
