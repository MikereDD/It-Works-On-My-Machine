from pathlib import Path
import argparse
import os
import re
import runpy
import shutil
import subprocess
import sys
import textwrap

ROOT = Path(__file__).resolve().parent
WIDTH = 43
GAP = 4
ANSI = re.compile(r"\x1b\[[0-9;]*m")

def load_system():
    collector = ROOT / "lib/collectors.sh"

    script = r"""
source "$1"
infocat_collect

printf 'InfoCat v2 — %s@%s\n' "$INFOCAT_USER" "$INFOCAT_HOST"
printf 'OS           %s\n' "$INFOCAT_OS"
printf 'Board        %s\n' "$INFOCAT_BOARD"
printf 'Kernel       %s\n' "$INFOCAT_KERNEL"
printf 'Architecture %s\n' "$INFOCAT_ARCH"
printf 'Uptime       %s\n' "$INFOCAT_UPTIME"
printf 'CPU          %s cores\n' "$INFOCAT_CORES"
printf 'Temperature  %s\n' "$INFOCAT_TEMPERATURE"
printf 'Memory       %s\n' "$INFOCAT_MEMORY"
printf 'Root         %s\n' "$INFOCAT_ROOT"
printf 'NVMe         %s\n' "$INFOCAT_NVME"
printf 'Packages     %s\n' "$INFOCAT_PACKAGES"
printf 'LAN          %s\n' "$INFOCAT_LAN"
"""

    proc = subprocess.run(
        ["bash", "-c", script, "infocat-collector", str(collector)],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.splitlines()


def load_art(name):
    if name == "cat":
        rows = (ROOT / "art/cat.txt").read_text().splitlines()
        return rows, None

    if name == "rpi-arch":
        # Reuse the approved v3 artwork without running its main().
        from importlib.util import spec_from_file_location, module_from_spec
        path = ROOT / "lib/artwork_rpi_arch.py"
        spec = spec_from_file_location("artwork_rpi_arch", path)
        art_module = module_from_spec(spec)
        spec.loader.exec_module(art_module)
        chars, colors = art_module.build_canvas()
        return ["".join(row) for row in chars], colors

    return [], None

def render_colored(row, colors):
    if colors is None or not sys.stdout.isatty() or "NO_COLOR" in os.environ:
        return row

    palette = {
        "blue": "\033[38;2;23;147;209m",
        "green": "\033[38;2;92;180;95m",
        "red": "\033[38;2;205;45;80m",
        "light": "\033[38;2;245;105;130m",
    }
    # The v3 source supplies actual ANSI strings for each cell.
    out = []
    active = ""
    for ch, color in zip(row, colors):
        if color != active:
            out.append(color or "\033[0m")
            active = color
        out.append(ch)
    if active:
        out.append("\033[0m")
    return "".join(out)

def wrapped(lines, width):
    for line in lines:
        for part in textwrap.wrap(
            line, width=width, break_long_words=True,
            break_on_hyphens=False, replace_whitespace=False,
            drop_whitespace=False
        ) or [""]:
            print(part)

def main():
    parser = argparse.ArgumentParser(
        description="ARAKIEL InfoCat v2 development renderer"
    )
    parser.add_argument(
        "--logo", choices=["cat", "rpi-arch", "none"],
        default="cat"
    )
    parser.add_argument("--compact", action="store_true")
    parser.add_argument("--no-color", action="store_true")
    args = parser.parse_args()

    if args.no_color:
        os.environ["NO_COLOR"] = "1"

    columns = int(
        os.environ.get("INFOCAT_COLUMNS")
        or shutil.get_terminal_size((80, 24)).columns
    )
    if columns < 1:
        raise SystemExit("Invalid terminal width")

    info = load_system()
    if args.compact:
        info = info[:10]

    art, colors = load_art(args.logo)

    if not art or columns < 60:
        wrapped(info, columns)
        return

    art_width = max(len(row) for row in art)
    info_width = max(map(len, info), default=0)

    if art_width + GAP + info_width > columns:
        for i, row in enumerate(art):
            print(render_colored(
                row.rstrip(),
                colors[i][:len(row.rstrip())] if colors else None
            ))
        print()
        wrapped(info, columns)
        return

    total = max(len(art), len(info))
    for i in range(total):
        raw = art[i].rstrip() if i < len(art) else ""
        color_row = (
            colors[i][:len(raw)]
            if colors is not None and i < len(colors)
            else None
        )
        left = render_colored(raw, color_row)
        right = info[i] if i < len(info) else ""
        padding = " " * (art_width + GAP - len(raw))
        print(left + padding + right)

if __name__ == "__main__":
    main()