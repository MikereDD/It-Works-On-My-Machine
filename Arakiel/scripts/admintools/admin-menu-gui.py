#!/usr/bin/env python3
#
# file:    admin-menu-gui.py
# author:  Mike Redd
# version: 0.1-dev.1
# desc:    GTK4 desktop dashboard for Arakiel administration.
#

from __future__ import annotations

import os
import platform
import shutil
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gtk


APP_ID = "xyz.typezero.ArakielAdminTools"

CONFIG_HOME = Path(
    os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")
)
DATA_HOME = Path(
    os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")
)

THEME_CONFIG = CONFIG_HOME / "typezero/themeengine"
THEME_DATA = DATA_HOME / "typezero/themeengine"


FALLBACK_THEME = {
    "THEME_NAME": "Arakiel Dark",
    "BG": "#1f1f28",
    "SURFACE": "#181820",
    "SURFACE_ALT": "#2a2a37",
    "FOCUSED_BG": "#2a2a37",
    "BORDER": "#625e5a",
    "TEXT": "#dcd7ba",
    "MUTED": "#727169",
    "ACCENT": "#c4b28a",
    "ACCENT_BRIGHT": "#e6c384",
    "SUCCESS": "#699469",
    "WARNING": "#c4b28a",
    "ERROR": "#c4746e",
    "SECONDARY": "#a292a3",
    "INFO": "#658594",
}


def read_theme() -> dict[str, str]:
    theme = dict(FALLBACK_THEME)

    try:
        current_file = THEME_CONFIG / "current-theme"
        theme_id = current_file.read_text(encoding="utf-8").strip()
        theme_file = THEME_DATA / "themes" / theme_id / "theme.conf"

        for raw in theme_file.read_text(encoding="utf-8").splitlines():
            line = raw.strip()

            if not line or line.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            theme[key.strip()] = value

        theme["THEME_ID"] = theme_id

    except (OSError, ValueError):
        theme["THEME_ID"] = "fallback"

    return theme


def install_theme(theme: dict[str, str]) -> None:
    css = f"""
    window {{
        background: {theme['BG']};
        color: {theme['TEXT']};
    }}

    .topbar {{
        background: {theme['SURFACE']};
        border-bottom: 1px solid {theme['BORDER']};
        padding: 14px 18px;
    }}

    .title {{
        color: {theme['ACCENT_BRIGHT']};
        font-size: 20px;
        font-weight: 700;
    }}

    .subtitle {{
        color: {theme['MUTED']};
        font-size: 12px;
    }}

    .sidebar {{
        background: {theme['SURFACE']};
        border-right: 1px solid {theme['BORDER']};
        padding: 12px;
    }}

    .nav-button {{
        background: transparent;
        color: {theme['TEXT']};
        border: 0;
        border-radius: 8px;
        padding: 10px 14px;
    }}

    .nav-button:hover {{
        background: {theme['SURFACE_ALT']};
    }}

    .nav-active {{
        background: {theme['FOCUSED_BG']};
        color: {theme['ACCENT_BRIGHT']};
        border-left: 3px solid {theme['ACCENT']};
    }}

    .page {{
        padding: 28px;
    }}

    .page-title {{
        color: {theme['ACCENT_BRIGHT']};
        font-size: 26px;
        font-weight: 700;
    }}

    .page-subtitle {{
        color: {theme['MUTED']};
        font-size: 13px;
    }}

    .card {{
        background: {theme['SURFACE']};
        border: 1px solid {theme['BORDER']};
        border-radius: 10px;
        padding: 18px;
    }}

    .card-title {{
        color: {theme['INFO']};
        font-weight: 700;
    }}

    .metric {{
        color: {theme['TEXT']};
        font-family: monospace;
        font-size: 13px;
    }}

    .action-button {{
        background: {theme['SURFACE_ALT']};
        color: {theme['TEXT']};
        border: 1px solid {theme['BORDER']};
        border-radius: 8px;
        padding: 8px 14px;
    }}

    .action-button:hover {{
        border-color: {theme['ACCENT']};
        color: {theme['ACCENT_BRIGHT']};
    }}

    .danger-button {{
        background: {theme['SURFACE_ALT']};
        color: {theme['ERROR']};
        border: 1px solid {theme['ERROR']};
        border-radius: 8px;
        padding: 8px 14px;
    }}

    .statusbar {{
        background: {theme['SURFACE']};
        color: {theme['MUTED']};
        border-top: 1px solid {theme['BORDER']};
        padding: 7px 14px;
        font-size: 11px;
    }}
    """

    provider = Gtk.CssProvider()
    provider.load_from_data(css.encode("utf-8"))

    display = Gdk.Display.get_default()
    if display:
        Gtk.StyleContext.add_provider_for_display(
            display,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )


def read_mem_total() -> str:
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                kib = int(line.split()[1])
                return f"{kib / 1024 / 1024:.1f} GB"
    except (OSError, ValueError):
        pass

    return "Unknown"


def read_uptime() -> str:
    try:
        seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
        days, seconds = divmod(seconds, 86400)
        hours, seconds = divmod(seconds, 3600)
        minutes = seconds // 60

        if days:
            return f"{days}d {hours}h {minutes}m"

        return f"{hours}h {minutes}m"
    except (OSError, ValueError, IndexError):
        return "Unknown"


def read_temperature() -> str:
    try:
        raw = Path("/sys/class/thermal/thermal_zone0/temp").read_text().strip()
        return f"{int(raw) / 1000:.1f} °C"
    except (OSError, ValueError):
        return "Unavailable"


def run_command(*args: str) -> str:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        return result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def run_lines(*args: str) -> list[str]:
    output = run_command(*args)

    return [
        line.strip()
        for line in output.splitlines()
        if line.strip()
    ]


def format_bytes(value: int) -> str:
    units = ("B", "KB", "MB", "GB", "TB")
    size = float(value)

    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{size:.1f} {unit}"

        size /= 1024

    return f"{value} B"


def read_default_gateway() -> str:
    output = run_command("ip", "route")

    for line in output.splitlines():
        parts = line.split()

        if parts and parts[0] == "default":
            if "via" in parts:
                return parts[parts.index("via") + 1]

    return "Unavailable"


def read_primary_ip() -> str:
    output = run_command("hostname", "-I")

    if output:
        return output.split()[0]

    return "Unavailable"


def read_interface_summary() -> str:
    lines = run_lines("ip", "-brief", "addr")

    useful = [
        line
        for line in lines
        if not line.startswith("lo ")
    ]

    return " | ".join(useful) if useful else "Unavailable"


def read_failed_services() -> tuple[str, str]:
    lines = run_lines(
        "systemctl",
        "--failed",
        "--no-legend",
        "--plain",
    )

    if not lines:
        return "0", "All services healthy"

    names = [
        line.split()[0]
        for line in lines
        if line.split()
    ]

    return str(len(names)), ", ".join(names[:5])


def read_update_count() -> tuple[str, str]:
    if shutil.which("checkupdates"):
        try:
            result = subprocess.run(
                ["checkupdates"],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )

            lines = [
                line
                for line in result.stdout.splitlines()
                if line.strip()
            ]

            return str(len(lines)), "Official repositories"
        except (OSError, subprocess.SubprocessError):
            pass

    return "Unknown", "checkupdates unavailable"


def read_aur_updates() -> tuple[str, str]:
    helper = shutil.which("paru") or shutil.which("yay")

    if not helper:
        return "0", "No AUR helper"

    try:
        result = subprocess.run(
            [helper, "-Qua"],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )

        lines = [
            line
            for line in result.stdout.splitlines()
            if line.strip()
        ]

        return str(len(lines)), Path(helper).name
    except (OSError, subprocess.SubprocessError):
        return "Unknown", Path(helper).name




def read_pi_model() -> str:
    try:
        raw = Path("/proc/device-tree/model").read_bytes()
        return raw.rstrip(b"\0").decode("utf-8", errors="replace")
    except OSError:
        return "Unknown"


def read_fan_rpm() -> str:
    for path in Path("/sys/class/hwmon").glob("hwmon*/fan1_input"):
        try:
            return f"{int(path.read_text().strip()):,} RPM"
        except (OSError, ValueError):
            continue

    return "Unavailable"


def read_cpu_governor() -> str:
    path = Path(
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    )

    try:
        return path.read_text().strip()
    except OSError:
        return "Unavailable"


def read_cpu_frequency() -> str:
    path = Path(
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    )

    try:
        khz = int(path.read_text().strip())
        return f"{khz / 1000:.0f} MHz"
    except (OSError, ValueError):
        return "Unavailable"


def read_throttle() -> tuple[str, str]:
    device = Path("/dev/vcio_gencmd")

    if not device.exists():
        return "Firmware interface unavailable", ""

    if not os.access(device, os.R_OK | os.W_OK):
        return "Firmware interface permission denied", ""

    raw = run_command("vcgencmd", "get_throttled")

    if "=" not in raw:
        return "Unavailable", ""

    value_text = raw.split("=", 1)[1].strip()

    try:
        value = int(value_text, 16)
    except ValueError:
        return "Unavailable", value_text

    current = []

    if value & 0x1:
        current.append("under-voltage")
    if value & 0x2:
        current.append("frequency capped")
    if value & 0x4:
        current.append("throttled")
    if value & 0x8:
        current.append("soft temperature limit")

    past = []

    if value & 0x10000:
        past.append("under-voltage")
    if value & 0x20000:
        past.append("frequency capped")
    if value & 0x40000:
        past.append("throttled")
    if value & 0x80000:
        past.append("soft temperature limit")

    if current:
        status = ", ".join(current)
    else:
        status = "OK"

    history = ", ".join(past) if past else "none"

    return status, f"{value_text} • since boot: {history}"


def read_core_voltage() -> str:
    if not Path("/dev/vcio_gencmd").exists():
        return "Firmware interface unavailable"

    if not os.access("/dev/vcio_gencmd", os.R_OK | os.W_OK):
        return "Firmware interface permission denied"

    raw = run_command("vcgencmd", "measure_volts", "core")

    if "=" in raw:
        return raw.split("=", 1)[1].strip()

    return "Unavailable"



def find_boot_config() -> Path | None:
    for candidate in (
        Path("/boot/firmware/config.txt"),
        Path("/boot/config.txt"),
    ):
        if candidate.is_file():
            return candidate

    return None


def read_boot_order() -> str:
    output = run_command("vcgencmd", "bootloader_config")

    for line in output.splitlines():
        line = line.strip()

        if line.startswith("BOOT_ORDER="):
            return line.split("=", 1)[1].strip()

    return "Unavailable"


def read_bootloader_status() -> str:
    output = run_command("vcgencmd", "bootloader_version")

    if not output:
        return "Unavailable"

    lines = [
        line.strip()
        for line in output.splitlines()
        if line.strip()
    ]

    if not lines:
        return "Unavailable"

    date = lines[0]
    release = ""

    for line in lines[1:]:
        if line.startswith("version "):
            parts = line.split()

            if len(parts) >= 2:
                release = parts[1][:12]

            if "(release)" in line:
                release = f"{release} • release"

            break

    if release:
        return f"{date} • {release}"

    return date



def read_performance_overrides() -> str:
    config = find_boot_config()

    if not config:
        return "config.txt unavailable"

    keys = (
        "arm_freq=",
        "gpu_freq=",
        "over_voltage=",
        "over_voltage_delta=",
        "force_turbo=",
        "dtparam=pciex1_gen=",
        "dtparam=pciex1=",
    )

    try:
        values = [
            line.strip()
            for line in config.read_text(
                encoding="utf-8",
                errors="replace",
            ).splitlines()
            if line.strip().startswith(keys)
        ]
    except OSError:
        return "Unreadable"

    return " • ".join(values) if values else "Stock / no overrides"



class AdminWindow(Gtk.ApplicationWindow):
    PAGES = (
        ("system", "System", "System overview and health"),
        ("pi5", "Pi 5", "Raspberry Pi hardware"),
        ("storage", "Storage", "Disks and NVMe"),
        ("network", "Network", "Interfaces and connectivity"),
        ("services", "Services", "systemd services"),
        ("updates", "Updates", "Arch package management"),
        ("processes", "Processes", "Running processes"),
        ("logs", "Logs", "System and application logs"),
        ("power", "Power", "Power and session controls"),
    )

    def __init__(self, app: Gtk.Application, theme: dict[str, str]) -> None:
        super().__init__(application=app)

        self.theme = theme
        self.nav_buttons: dict[str, Gtk.Button] = {}

        self.status = Gtk.Label(
            label=f"Arakiel • {theme.get('THEME_NAME', 'ThemeEngine')} • ready",
            xalign=0,
        )
        self.status.add_css_class("statusbar")

        self.set_title("Arakiel Admin Tools")
        self.set_default_size(1100, 720)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_child(root)

        root.append(self.build_header())

        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        body.set_vexpand(True)
        root.append(body)

        body.append(self.build_sidebar())

        self.stack = Gtk.Stack()
        self.stack.set_hexpand(True)
        self.stack.set_vexpand(True)

        for page_id, title, subtitle in self.PAGES:
            if page_id == "system":
                page = self.build_system_page(title, subtitle)
            elif page_id == "pi5":
                page = self.build_pi_page(title, subtitle)
            elif page_id == "storage":
                page = self.build_storage_page(title, subtitle)
            elif page_id == "network":
                page = self.build_network_page(title, subtitle)
            elif page_id == "services":
                page = self.build_services_page(title, subtitle)
            elif page_id == "updates":
                page = self.build_updates_page(title, subtitle)
            elif page_id == "processes":
                page = self.build_processes_page(title, subtitle)
            elif page_id == "logs":
                page = self.build_logs_page(title, subtitle)
            elif page_id == "power":
                page = self.build_power_page(title, subtitle)
            else:
                page = self.build_placeholder_page(title, subtitle)

            self.stack.add_named(page, page_id)

        body.append(self.stack)

        root.append(self.status)

        self.select_page("system")

    def build_header(self) -> Gtk.Widget:
        header = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=2,
        )
        header.add_css_class("topbar")

        title = Gtk.Label(label="ARAKIEL ADMIN TOOLS", xalign=0)
        title.add_css_class("title")

        subtitle = Gtk.Label(
            label="Raspberry Pi 5 • Arch Linux • System Dashboard",
            xalign=0,
        )
        subtitle.add_css_class("subtitle")

        header.append(title)
        header.append(subtitle)

        return header

    def build_sidebar(self) -> Gtk.Widget:
        sidebar = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=4,
        )
        sidebar.set_size_request(210, -1)
        sidebar.add_css_class("sidebar")

        for page_id, title, _ in self.PAGES:
            button = Gtk.Button(label=title)
            button.set_halign(Gtk.Align.FILL)
            button.add_css_class("nav-button")
            button.connect("clicked", self.on_nav_clicked, page_id)

            sidebar.append(button)
            self.nav_buttons[page_id] = button

        return sidebar

    def on_nav_clicked(self, _button: Gtk.Button, page_id: str) -> None:
        self.select_page(page_id)

    def select_page(self, page_id: str) -> None:
        self.stack.set_visible_child_name(page_id)

        for current_id, button in self.nav_buttons.items():
            if current_id == page_id:
                button.add_css_class("nav-active")
            else:
                button.remove_css_class("nav-active")

        title = next(
            title
            for current_id, title, _ in self.PAGES
            if current_id == page_id
        )

        self.status.set_text(
            f"Arakiel • {title} • {self.theme.get('THEME_NAME', 'ThemeEngine')}"
        )

    def build_page_shell(self, title: str, subtitle: str) -> Gtk.Box:
        page = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=8,
        )
        page.add_css_class("page")

        heading = Gtk.Label(label=title, xalign=0)
        heading.add_css_class("page-title")

        description = Gtk.Label(label=subtitle, xalign=0)
        description.add_css_class("page-subtitle")

        page.append(heading)
        page.append(description)

        return page

    def build_placeholder_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        card = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=8,
        )
        card.set_margin_top(18)
        card.add_css_class("card")

        card_title = Gtk.Label(label="Foundation ready", xalign=0)
        card_title.add_css_class("card-title")

        message = Gtk.Label(
            label="This section will be wired to Arakiel's existing admin tools.",
            xalign=0,
        )
        message.add_css_class("metric")

        card.append(card_title)
        card.append(message)
        page.append(card)

        return page

    def build_storage_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        card = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        card.set_margin_top(18)
        card.add_css_class("card")

        heading = Gtk.Label(label="Mounted Storage", xalign=0)
        heading.add_css_class("card-title")
        card.append(heading)

        output = run_command(
            "df",
            "-h",
            "--output=source,size,used,avail,pcent,target",
        )

        lines = output.splitlines()

        for line in lines[:12]:
            label = Gtk.Label(label=line, xalign=0)
            label.set_selectable(True)
            label.add_css_class("metric")
            card.append(label)

        page.append(card)

        nvme = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        nvme.set_margin_top(18)
        nvme.add_css_class("card")

        heading = Gtk.Label(label="NVMe Devices", xalign=0)
        heading.add_css_class("card-title")
        nvme.append(heading)

        devices = sorted(Path("/dev").glob("nvme*n*"))

        if not devices:
            label = Gtk.Label(label="No NVMe namespaces found", xalign=0)
            label.add_css_class("metric")
            nvme.append(label)
        else:
            for device in devices:
                label = Gtk.Label(label=str(device), xalign=0)
                label.add_css_class("metric")
                nvme.append(label)

        page.append(nvme)

        return page

    def build_network_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        metrics = (
            ("Primary IPv4", read_primary_ip()),
            ("Default gateway", read_default_gateway()),
            ("Interfaces", read_interface_summary()),
        )

        card = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        card.set_margin_top(18)
        card.add_css_class("card")

        heading = Gtk.Label(label="Connectivity", xalign=0)
        heading.add_css_class("card-title")
        card.append(heading)

        for name, value in metrics:
            row = Gtk.Box(
                orientation=Gtk.Orientation.HORIZONTAL,
                spacing=18,
            )

            label = Gtk.Label(label=name, xalign=0)
            label.set_size_request(150, -1)
            label.add_css_class("page-subtitle")

            data = Gtk.Label(label=value, xalign=0)
            data.set_hexpand(True)
            data.set_wrap(True)
            data.set_selectable(True)
            data.add_css_class("metric")

            row.append(label)
            row.append(data)
            card.append(row)

        ports = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        ports.set_margin_top(18)
        ports.add_css_class("card")

        heading = Gtk.Label(label="Listening Ports", xalign=0)
        heading.add_css_class("card-title")
        ports.append(heading)

        output = run_command("ss", "-tuln")

        for line in output.splitlines()[:20]:
            label = Gtk.Label(label=line, xalign=0)
            label.set_selectable(True)
            label.add_css_class("metric")
            ports.append(label)

        page.append(card)
        page.append(ports)

        return page

    def build_services_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        count, detail = read_failed_services()

        summary = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        summary.set_margin_top(18)
        summary.add_css_class("card")

        heading = Gtk.Label(label="Service Health", xalign=0)
        heading.add_css_class("card-title")
        summary.append(heading)

        row = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=18,
        )

        label = Gtk.Label(label="Failed units", xalign=0)
        label.set_size_request(150, -1)
        label.add_css_class("page-subtitle")

        data = Gtk.Label(label=f"{count} • {detail}", xalign=0)
        data.set_hexpand(True)
        data.set_wrap(True)
        data.add_css_class("metric")

        row.append(label)
        row.append(data)
        summary.append(row)

        running = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        running.set_margin_top(18)
        running.add_css_class("card")

        heading = Gtk.Label(label="Running Services", xalign=0)
        heading.add_css_class("card-title")
        running.append(heading)

        output = run_command(
            "systemctl",
            "list-units",
            "--type=service",
            "--state=running",
            "--no-legend",
            "--plain",
        )

        for line in output.splitlines()[:20]:
            label = Gtk.Label(label=line, xalign=0)
            label.set_selectable(True)
            label.add_css_class("metric")
            running.append(label)

        page.append(summary)
        page.append(running)

        return page

    def build_updates_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        official_count, official_detail = read_update_count()
        aur_count, aur_detail = read_aur_updates()

        card = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        card.set_margin_top(18)
        card.add_css_class("card")

        heading = Gtk.Label(label="Package Status", xalign=0)
        heading.add_css_class("card-title")
        card.append(heading)

        metrics = (
            ("Official updates", f"{official_count} • {official_detail}"),
            ("AUR updates", f"{aur_count} • {aur_detail}"),
            ("Kernel", platform.release()),
        )

        for name, value in metrics:
            row = Gtk.Box(
                orientation=Gtk.Orientation.HORIZONTAL,
                spacing=18,
            )

            label = Gtk.Label(label=name, xalign=0)
            label.set_size_request(150, -1)
            label.add_css_class("page-subtitle")

            data = Gtk.Label(label=value, xalign=0)
            data.set_hexpand(True)
            data.add_css_class("metric")

            row.append(label)
            row.append(data)
            card.append(row)

        page.append(card)

        return page

    def make_text_output(self) -> tuple[Gtk.ScrolledWindow, Gtk.TextView]:
        view = Gtk.TextView()
        view.set_editable(False)
        view.set_cursor_visible(False)
        view.set_monospace(True)
        view.set_wrap_mode(Gtk.WrapMode.NONE)

        scroll = Gtk.ScrolledWindow()
        scroll.set_hexpand(True)
        scroll.set_vexpand(True)
        scroll.set_min_content_height(360)
        scroll.set_child(view)

        return scroll, view

    def set_output_text(self, view: Gtk.TextView, text: str) -> None:
        buffer = view.get_buffer()
        buffer.set_text(text if text else "No output.")

    def confirm_command(
        self,
        title: str,
        message: str,
        command: tuple[str, ...],
    ) -> None:
        dialog = Gtk.Dialog(
            title=title,
            transient_for=self,
            modal=True,
        )

        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Continue", Gtk.ResponseType.OK)

        content = dialog.get_content_area()
        content.set_spacing(12)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        label = Gtk.Label(label=message)
        label.set_wrap(True)
        label.set_xalign(0)
        content.append(label)

        def on_response(
            current_dialog: Gtk.Dialog,
            response: int,
        ) -> None:
            current_dialog.close()

            if response != Gtk.ResponseType.OK:
                return

            try:
                subprocess.Popen(command)
                self.status.set_text(
                    f"Arakiel • requested: {' '.join(command)}"
                )
            except OSError as exc:
                self.status.set_text(
                    f"Arakiel • command failed: {exc}"
                )

        dialog.connect("response", on_response)
        dialog.present()

    def build_processes_page(
        self,
        title: str,
        subtitle: str,
    ) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        toolbar = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=8,
        )
        toolbar.set_margin_top(18)

        scroll, view = self.make_text_output()

        def refresh_processes(_button=None) -> None:
            output = run_command(
                "ps",
                "-eo",
                "pid,user,pcpu,pmem,rss,comm",
                "--sort=-pcpu",
            )

            lines = output.splitlines()[:31]
            self.set_output_text(view, "\n".join(lines))

            self.status.set_text(
                "Arakiel • Processes • refreshed"
            )

        refresh = Gtk.Button(label="Refresh")
        refresh.add_css_class("action-button")
        refresh.connect("clicked", refresh_processes)

        cpu = Gtk.Button(label="Top CPU")
        cpu.add_css_class("action-button")

        def show_cpu(_button) -> None:
            output = run_command(
                "ps",
                "-eo",
                "pid,user,pcpu,pmem,comm",
                "--sort=-pcpu",
            )
            self.set_output_text(
                view,
                "\n".join(output.splitlines()[:31]),
            )

        cpu.connect("clicked", show_cpu)

        memory = Gtk.Button(label="Top Memory")
        memory.add_css_class("action-button")

        def show_memory(_button) -> None:
            output = run_command(
                "ps",
                "-eo",
                "pid,user,pcpu,pmem,rss,comm",
                "--sort=-pmem",
            )
            self.set_output_text(
                view,
                "\n".join(output.splitlines()[:31]),
            )

        memory.connect("clicked", show_memory)

        toolbar.append(refresh)
        toolbar.append(cpu)
        toolbar.append(memory)

        page.append(toolbar)
        page.append(scroll)

        refresh_processes()

        return page

    def build_logs_page(
        self,
        title: str,
        subtitle: str,
    ) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        toolbar = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=8,
        )
        toolbar.set_margin_top(18)

        log_choices = (
            "Errors this boot",
            "Recent boot",
            "Kernel",
            "Hardware warnings",
        )

        selector = Gtk.DropDown.new_from_strings(log_choices)
        selector.set_selected(0)

        service_entry = Gtk.Entry()
        service_entry.set_placeholder_text(
            "Service/unit, e.g. sshd"
        )
        service_entry.set_hexpand(True)

        scroll, view = self.make_text_output()

        def refresh_logs(_button=None) -> None:
            selected = selector.get_selected()
            choice = log_choices[selected]

            if choice == "Errors this boot":
                output = run_command(
                    "journalctl",
                    "-b",
                    "-p",
                    "err",
                    "-n",
                    "150",
                    "--no-pager",
                )

            elif choice == "Recent boot":
                output = run_command(
                    "journalctl",
                    "-b",
                    "-n",
                    "200",
                    "--no-pager",
                )

            elif choice == "Kernel":
                output = run_command(
                    "journalctl",
                    "-k",
                    "-b",
                    "-n",
                    "200",
                    "--no-pager",
                )

            else:
                output = run_command(
                    "journalctl",
                    "-k",
                    "-b",
                    "--no-pager",
                )

                keywords = (
                    "thrott",
                    "voltage",
                    "temperature",
                    "hwmon",
                    "nvme",
                    "pcie",
                    "firmware",
                )

                output = "\n".join(
                    line
                    for line in output.splitlines()
                    if any(
                        keyword in line.lower()
                        for keyword in keywords
                    )
                )

            self.set_output_text(view, output)
            self.status.set_text(
                f"Arakiel • Logs • {choice}"
            )

        def show_service(_button) -> None:
            unit = service_entry.get_text().strip()

            if not unit:
                self.set_output_text(
                    view,
                    "Enter a systemd service or unit name.",
                )
                return

            output = run_command(
                "journalctl",
                "-u",
                unit,
                "-n",
                "150",
                "--no-pager",
            )

            self.set_output_text(view, output)
            self.status.set_text(
                f"Arakiel • Logs • {unit}"
            )

        refresh = Gtk.Button(label="Refresh")
        refresh.add_css_class("action-button")
        refresh.connect("clicked", refresh_logs)

        service = Gtk.Button(label="Service Log")
        service.add_css_class("action-button")
        service.connect("clicked", show_service)

        toolbar.append(selector)
        toolbar.append(refresh)
        toolbar.append(service_entry)
        toolbar.append(service)

        page.append(toolbar)
        page.append(scroll)

        refresh_logs()

        return page

    def build_power_page(
        self,
        title: str,
        subtitle: str,
    ) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        card = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=12,
        )
        card.set_margin_top(18)
        card.add_css_class("card")

        heading = Gtk.Label(
            label="Session / Power Controls",
            xalign=0,
        )
        heading.add_css_class("card-title")
        card.append(heading)

        note = Gtk.Label(
            label=(
                "Power actions affect the running Arakiel desktop "
                "or the entire machine."
            ),
            xalign=0,
        )
        note.set_wrap(True)
        note.add_css_class("page-subtitle")
        card.append(note)

        buttons = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=10,
        )

        lock = Gtk.Button(label="Lock")
        lock.add_css_class("action-button")

        def lock_session(_button) -> None:
            try:
                subprocess.Popen(
                    ("loginctl", "lock-session")
                )
                self.status.set_text(
                    "Arakiel • lock requested"
                )
            except OSError as exc:
                self.status.set_text(
                    f"Arakiel • lock failed: {exc}"
                )

        lock.connect("clicked", lock_session)

        suspend = Gtk.Button(label="Suspend")
        suspend.add_css_class("action-button")
        suspend.connect(
            "clicked",
            lambda _button: self.confirm_command(
                "Suspend Arakiel",
                "Suspend the machine now?",
                ("systemctl", "suspend"),
            ),
        )

        logout = Gtk.Button(label="Log Out")
        logout.add_css_class("action-button")
        logout.connect(
            "clicked",
            lambda _button: self.confirm_command(
                "Log Out",
                "Exit the current i3 desktop session?",
                ("i3-msg", "exit"),
            ),
        )

        reboot = Gtk.Button(label="Reboot")
        reboot.add_css_class("danger-button")
        reboot.connect(
            "clicked",
            lambda _button: self.confirm_command(
                "Reboot Arakiel",
                "Reboot Arakiel now?",
                ("systemctl", "reboot"),
            ),
        )

        shutdown = Gtk.Button(label="Shutdown")
        shutdown.add_css_class("danger-button")
        shutdown.connect(
            "clicked",
            lambda _button: self.confirm_command(
                "Shutdown Arakiel",
                "Power off Arakiel now?",
                ("systemctl", "poweroff"),
            ),
        )

        buttons.append(lock)
        buttons.append(suspend)
        buttons.append(logout)
        buttons.append(reboot)
        buttons.append(shutdown)

        card.append(buttons)

        info = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        info.set_margin_top(18)
        info.add_css_class("card")

        info_heading = Gtk.Label(
            label="Current Session",
            xalign=0,
        )
        info_heading.add_css_class("card-title")
        info.append(info_heading)

        metrics = (
            ("User", os.environ.get("USER", "Unknown")),
            ("Host", platform.node()),
            ("Uptime", read_uptime()),
            (
                "Target",
                run_command(
                    "systemctl",
                    "get-default",
                ) or "Unknown",
            ),
        )

        for name, value in metrics:
            row = Gtk.Box(
                orientation=Gtk.Orientation.HORIZONTAL,
                spacing=18,
            )

            label = Gtk.Label(label=name, xalign=0)
            label.set_size_request(150, -1)
            label.add_css_class("page-subtitle")

            data = Gtk.Label(label=value, xalign=0)
            data.set_hexpand(True)
            data.add_css_class("metric")

            row.append(label)
            row.append(data)
            info.append(row)

        page.append(card)
        page.append(info)

        return page

    def build_pi_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        throttle, throttle_detail = read_throttle()

        groups = (
            (
                "Hardware",
                (
                    ("Model", read_pi_model()),
                    ("CPU temperature", read_temperature()),
                    ("Fan", read_fan_rpm()),
                    ("CPU governor", read_cpu_governor()),
                    ("CPU frequency", read_cpu_frequency()),
                    ("Core voltage", read_core_voltage()),
                ),
            ),
            (
                "Health",
                (
                    ("Throttle state", throttle),
                    ("Throttle history", throttle_detail or "Unavailable"),
                ),
            ),
            (
                "Boot / Performance",
                (
                    ("Bootloader", read_bootloader_status()),
                    ("Boot order", read_boot_order()),
                    ("Overrides", read_performance_overrides()),
                ),
            ),
        )

        for group_title, metrics in groups:
            card = Gtk.Box(
                orientation=Gtk.Orientation.VERTICAL,
                spacing=10,
            )
            card.set_margin_top(18)
            card.add_css_class("card")

            heading = Gtk.Label(label=group_title, xalign=0)
            heading.add_css_class("card-title")
            card.append(heading)

            for name, value in metrics:
                row = Gtk.Box(
                    orientation=Gtk.Orientation.HORIZONTAL,
                    spacing=18,
                )

                label = Gtk.Label(label=name, xalign=0)
                label.set_size_request(160, -1)
                label.add_css_class("page-subtitle")

                data = Gtk.Label(label=value, xalign=0)
                data.set_hexpand(True)
                data.set_wrap(True)
                data.set_selectable(True)
                data.add_css_class("metric")

                row.append(label)
                row.append(data)
                card.append(row)

            page.append(card)

        return page

    def build_system_page(self, title: str, subtitle: str) -> Gtk.Widget:
        page = self.build_page_shell(title, subtitle)

        root_disk = shutil.disk_usage("/")

        metrics = (
            ("Host", platform.node()),
            ("Kernel", platform.release()),
            ("Architecture", platform.machine()),
            ("Uptime", read_uptime()),
            ("Memory", read_mem_total()),
            ("CPU temperature", read_temperature()),
            (
                "Root disk",
                f"{root_disk.used / 1024**3:.1f} / "
                f"{root_disk.total / 1024**3:.1f} GB",
            ),
        )

        card = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10,
        )
        card.set_margin_top(18)
        card.add_css_class("card")

        card_title = Gtk.Label(label="System Summary", xalign=0)
        card_title.add_css_class("card-title")
        card.append(card_title)

        for name, value in metrics:
            row = Gtk.Box(
                orientation=Gtk.Orientation.HORIZONTAL,
                spacing=18,
            )

            label = Gtk.Label(label=name, xalign=0)
            label.set_size_request(150, -1)
            label.add_css_class("page-subtitle")

            data = Gtk.Label(label=value, xalign=0)
            data.set_hexpand(True)
            data.add_css_class("metric")

            row.append(label)
            row.append(data)
            card.append(row)

        page.append(card)

        return page


class AdminApplication(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)

    def do_activate(self) -> None:
        theme = read_theme()
        install_theme(theme)

        window = AdminWindow(self, theme)
        window.present()


def main() -> int:
    app = AdminApplication()
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
