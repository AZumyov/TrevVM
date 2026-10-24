#!/usr/bin/env python3
"""TrevVM installer.

Two ways to use it:

* ``python3 installer.py`` opens the interactive Textual UI.
* ``python3 installer.py --defaults --output options.json`` writes the
  default selection without a terminal (used by ``install.sh -y`` and CI).

The resulting ``options.json`` is consumed by ``root/install-de.sh`` and
``root/installapps.sh`` inside the image build.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Sequence

INSTALLER_VERSION = "3.1.0"
SCHEMA = 2
DEFAULT_DE = "cinnamon"
DEFAULT_OUTPUT = Path("options.json")


# --------------------------------------------------------------------------
# Catalog
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Package:
    id: str
    label: str
    script: str = ""
    description: str = ""
    default: bool = False


@dataclass(frozen=True)
class Group:
    key: str
    title: str
    packages: tuple[Package, ...]

    def ids(self) -> tuple[str, ...]:
        return tuple(package.id for package in self.packages)


@dataclass(frozen=True)
class Desktop:
    id: str
    label: str
    script: str = ""


def load_catalog(path: Path | None = None) -> tuple[tuple[Group, ...], tuple[Desktop, ...]]:
    """Read the app/desktop catalog from apps.json, the single source of truth."""
    manifest = path or Path(__file__).with_name("apps.json")
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except OSError as error:
        raise SystemExit(f"error: cannot read {manifest}: {error}") from error
    except ValueError as error:
        raise SystemExit(f"error: {manifest} is not valid JSON: {error}") from error

    groups = []
    for raw_group in data.get("groups", []):
        packages = tuple(
            Package(
                id=raw["id"],
                label=raw.get("label", raw["id"]),
                script=raw.get("script", f"{raw['id']}.sh"),
                description=raw.get("description", ""),
                default=bool(raw.get("default", False)),
            )
            for raw in raw_group.get("packages", [])
        )
        groups.append(Group(key=raw_group["key"], title=raw_group.get("title", raw_group["key"]), packages=packages))

    desktops = tuple(
        Desktop(id=raw["id"], label=raw.get("label", raw["id"]), script=raw.get("script", ""))
        for raw in data.get("desktops", [])
    )
    if not groups or not desktops:
        raise SystemExit(f"error: {manifest} has no groups or desktops")
    return tuple(groups), desktops


GROUPS, DESKTOPS = load_catalog()
DESKTOP_IDS = tuple(desktop.id for desktop in DESKTOPS)
PACKAGE_IDS = tuple(package.id for group in GROUPS for package in group.packages)
PACKAGE_LABELS = {package.id: package.label for group in GROUPS for package in group.packages}
DEFAULTS = {group.key: [package.id for package in group.packages if package.default] for group in GROUPS}

INTRO = """
# TrevVM Installer

Choose a desktop and apps. Cinnamon is the safest default; larger selections
take longer to build.

`Tab` moves, `Space` toggles, `Ctrl+S` reviews, `Esc` goes back.
"""


# --------------------------------------------------------------------------
# Options model
# --------------------------------------------------------------------------


@dataclass
class Options:
    desktop: str = DEFAULT_DE
    kvm: bool = False
    selected: dict[str, list[str]] = field(
        default_factory=lambda: {key: list(values) for key, values in DEFAULTS.items()}
    )

    def package_ids(self) -> list[str]:
        ordered: list[str] = []
        for group in GROUPS:
            chosen = set(self.selected.get(group.key, ()))
            ordered.extend(package.id for package in group.packages if package.id in chosen)
        return ordered

    def summary(self) -> str:
        lines = [
            f"Desktop: {desktop_label(self.desktop)}",
            f"KVM acceleration: {'enabled' if self.kvm else 'disabled'}",
        ]
        for group in GROUPS:
            chosen = self.selected.get(group.key, [])
            if chosen:
                labels = ", ".join(PACKAGE_LABELS.get(item, item) for item in chosen)
                lines.append(f"{group.title}: {labels}")
            else:
                lines.append(f"{group.title}: none")
        lines.append("")
        lines.append("The first build usually takes 10-30 minutes depending on the host.")
        return "\n".join(lines)


def desktop_label(desktop_id: str) -> str:
    for desktop in DESKTOPS:
        if desktop.id == desktop_id:
            return desktop.label
    return desktop_id


def validate_desktop(value: str) -> str:
    normalized = value.strip().lower()
    aliases = {
        "kde plasma (heavy)": "kde",
        "kde plasma": "kde",
        "plasma": "kde",
        "xfce4 (lightweight)": "xfce",
        "xfce4": "xfce",
        "i3 (very lightweight)": "i3",
        "gnome 42 (very heavy)": "gnome",
        "gnome": "gnome",
        "cinnamon (recommended)": "cinnamon",
        "lxqt (broken)": "lxqt",
    }
    if normalized in DESKTOP_IDS:
        return normalized
    if normalized in aliases:
        return aliases[normalized]
    raise ValueError(f"unknown desktop {value!r}; choose from: {', '.join(DESKTOP_IDS)}")


def options_to_payload(options: Options) -> dict:
    payload = {
        "schema": SCHEMA,
        "installer_version": INSTALLER_VERSION,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "DE": options.desktop,
        "enablekvm": bool(options.kvm),
        "packages": options.package_ids(),
    }
    for group in GROUPS:
        payload[group.key] = [item for item in options.selected.get(group.key, []) if item in group.ids()]
    return payload


def write_options(path: Path, payload: dict) -> Path:
    """Write ``options.json`` atomically so a crash cannot leave half a file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=str(path.parent), prefix=".options-", suffix=".json", delete=False
    )
    try:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    finally:
        handle.close()
    os.replace(handle.name, path)
    return path


def load_existing(path: Path) -> Options | None:
    """Read a previous selection so re-runs start where the user left off.

    Supports both the current string ids and the legacy integer indexes.
    """
    path = Path(path)
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(payload, dict):
        return None

    selected: dict[str, list[str]] = {}
    has_group_arrays = any(isinstance(payload.get(group.key), list) for group in GROUPS)
    flat = payload.get("packages")
    flat_ids = {item for item in flat if isinstance(item, str)} if isinstance(flat, list) else set()

    for group in GROUPS:
        raw = payload.get(group.key)
        if not isinstance(raw, list):
            # A hand-written file may only carry the flat package list.
            selected[group.key] = [package.id for package in group.packages if package.id in flat_ids]
            continue
        values: list[str] = []
        for item in raw:
            if isinstance(item, str) and item in group.ids():
                values.append(item)
            elif isinstance(item, int) and 0 <= item < len(group.packages):
                values.append(group.packages[item].id)
        selected[group.key] = values

    if not has_group_arrays and flat_ids:
        for group in GROUPS:
            selected[group.key] = [package.id for package in group.packages if package.id in flat_ids]

    desktop = DEFAULT_DE
    raw_de = payload.get("DE")
    if isinstance(raw_de, str):
        try:
            desktop = validate_desktop(raw_de)
        except ValueError:
            desktop = DEFAULT_DE

    return Options(desktop=desktop, kvm=bool(payload.get("enablekvm", False)), selected=selected)


def kvm_supported() -> bool:
    """True only when the host exposes a usable /dev/kvm."""
    if not sys.platform.startswith("linux"):
        return False
    device = Path("/dev/kvm")
    return device.exists() and os.access(device, os.R_OK | os.W_OK)


def build_selection(
    *,
    desktop: str = DEFAULT_DE,
    kvm: bool = False,
    packages: Iterable[str] | None = None,
    select_all: bool = False,
    select_none: bool = False,
) -> Options:
    selected = {group.key: [] for group in GROUPS}
    if select_all:
        selected = {group.key: list(group.ids()) for group in GROUPS}
    elif packages is not None:
        wanted = {item.strip() for item in packages if item and item.strip()}
        unknown = sorted(wanted.difference(PACKAGE_IDS))
        if unknown:
            raise ValueError(f"unknown package(s): {', '.join(unknown)}; valid: {', '.join(PACKAGE_IDS)}")
        for group in GROUPS:
            selected[group.key] = [package.id for package in group.packages if package.id in wanted]
    elif select_none:
        selected = {group.key: [] for group in GROUPS}
    else:
        selected = {key: list(values) for key, values in DEFAULTS.items()}
    return Options(desktop=validate_desktop(desktop), kvm=bool(kvm), selected=selected)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def positive_path(value: str) -> Path:
    return Path(value).expanduser()


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="installer.py",
        description="Choose the TrevVM desktop and apps, then write options.json.",
    )
    parser.add_argument("--output", type=positive_path, default=DEFAULT_OUTPUT, help="where to write options.json")
    parser.add_argument("--defaults", action="store_true", help="skip the UI and use the default selection")
    parser.add_argument("--all", action="store_true", help="select every optional package")
    parser.add_argument("--none", action="store_true", help="select no optional packages")
    parser.add_argument("--apps", metavar="ID[,ID...]", help="comma separated package ids (see --list)")
    parser.add_argument("--de", metavar="ID", default=None, help=f"desktop environment ({', '.join(DESKTOP_IDS)})")
    parser.add_argument("--kvm", dest="kvm", action="store_true", help="enable KVM acceleration")
    parser.add_argument("--no-kvm", dest="kvm", action="store_false", help="disable KVM acceleration")
    parser.set_defaults(kvm=None)
    parser.add_argument("--list", action="store_true", help="list package and desktop ids, then exit")
    parser.add_argument("--version", action="version", version=f"TrevVM installer {INSTALLER_VERSION}")
    return parser.parse_args(argv)


def print_catalog() -> None:
    print("Desktops:")
    for desktop in DESKTOPS:
        print(f"  {desktop.id:<10} {desktop.label}")
    for group in GROUPS:
        print(f"\n{group.title}:")
        for package in group.packages:
            default = " (default)" if package.default else ""
            print(f"  {package.id:<16} {package.label}{default}")


def has_selection_flags(args: argparse.Namespace) -> bool:
    return bool(args.defaults or args.all or args.none or args.apps)


def run_headless(args: argparse.Namespace) -> int:
    try:
        selection = build_selection(
            desktop=args.de or DEFAULT_DE,
            kvm=bool(args.kvm),
            packages=args.apps.split(",") if args.apps else None,
            select_all=args.all,
            select_none=args.none,
        )
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    payload = options_to_payload(selection)
    path = write_options(args.output, payload)
    print(selection.summary())
    print(f"\nWrote {path}")
    return 0


# --------------------------------------------------------------------------
# TUI
# --------------------------------------------------------------------------


def build_app_class():
    """Import Textual lazily so headless usage works without the TUI deps."""
    from textual.app import App, ComposeResult
    from textual.containers import Horizontal, Vertical
    from textual.screen import ModalScreen
    from textual.widgets import Button, Footer, Header, Label, Markdown, Select, SelectionList, Static, Switch

    class ConfirmScreen(ModalScreen[bool]):
        BINDINGS = [("escape", "dismiss_false", "Back")]

        def __init__(self, summary: str) -> None:
            super().__init__()
            self.summary = summary

        def compose(self) -> ComposeResult:
            with Vertical(id="dialog"):
                yield Label("Confirm the selection", id="dialog-title")
                yield Static(self.summary, id="dialog-body")
                with Horizontal(id="dialog-actions"):
                    yield Button("Back", id="back", variant="default")
                    yield Button("Build TrevVM", id="confirm", variant="success")

        def on_mount(self) -> None:
            self.query_one("#confirm", Button).focus()

        def action_dismiss_false(self) -> None:
            self.dismiss(False)

        def on_button_pressed(self, event: Button.Pressed) -> None:
            self.dismiss(event.button.id == "confirm")

    class InstallApp(App[int]):
        CSS_PATH = "installer.tcss"
        TITLE = "TrevVM Installer"
        SUB_TITLE = f"v{INSTALLER_VERSION}"
        BINDINGS = [
            ("ctrl+s", "review", "Review"),
            ("ctrl+q", "cancel", "Cancel"),
        ]

        def __init__(self, output: Path, initial: Options, kvm_available: bool) -> None:
            super().__init__()
            self.output = Path(output)
            self.initial = initial
            self.kvm_available = kvm_available

        def compose(self) -> ComposeResult:
            yield Header()
            yield Markdown(INTRO, id="intro")

            with Horizontal(id="groups"):
                for group in GROUPS:
                    chosen = set(self.initial.selected.get(group.key, ()))
                    with Vertical(classes="group"):
                        yield Label(group.title, classes="group-title")
                        yield SelectionList(
                            *[(package.label, package.id, package.id in chosen) for package in group.packages],
                            id=f"group-{group.key}",
                        )

            with Horizontal(id="settings"):
                with Vertical(classes="setting"):
                    yield Label("Desktop environment")
                    yield Select(
                        [(desktop.label, desktop.id) for desktop in DESKTOPS],
                        value=self.initial.desktop,
                        allow_blank=False,
                        id="de",
                    )
                with Vertical(classes="setting"):
                    yield Label("KVM acceleration")
                    yield Switch(value=self.initial.kvm, id="kvm", disabled=not self.kvm_available)
                    hint = (
                        "Available on this host."
                        if self.kvm_available
                        else "Not available here; the VM will run without hardware acceleration."
                    )
                    yield Label(hint, id="kvm-hint")

            with Horizontal(id="actions"):
                yield Button("Select all", id="select-all")
                yield Button("Clear", id="clear")
                yield Button("Install", id="install", variant="success")
                yield Button("Cancel", id="cancel", variant="error")

            yield Footer()

        def on_mount(self) -> None:
            first = self.query_one("#group-defaultapps", SelectionList)
            first.focus()

        def selected_options(self) -> Options:
            selected: dict[str, list[str]] = {}
            for group in GROUPS:
                widget = self.query_one(f"#group-{group.key}", SelectionList)
                selected[group.key] = [value for value in widget.selected if isinstance(value, str)]
            desktop = self.query_one("#de", Select).value
            kvm = self.query_one("#kvm", Switch).value
            return Options(
                desktop=desktop if isinstance(desktop, str) else DEFAULT_DE,
                kvm=bool(kvm) and self.kvm_available,
                selected=selected,
            )

        def action_review(self) -> None:
            selection = self.selected_options()
            self.push_screen(ConfirmScreen(selection.summary()), self._confirmed)

        def _confirmed(self, confirmed: bool | None) -> None:
            if not confirmed:
                return
            selection = self.selected_options()
            try:
                write_options(self.output, options_to_payload(selection))
            except OSError as error:
                self.notify(f"Could not write {self.output}: {error}", severity="error", timeout=8)
                return
            self.exit(0)

        def action_cancel(self) -> None:
            self.exit(130)

        def on_button_pressed(self, event: Button.Pressed) -> None:
            button_id = event.button.id
            if button_id == "cancel":
                self.action_cancel()
            elif button_id == "install":
                self.action_review()
            elif button_id in {"select-all", "clear"}:
                for group in GROUPS:
                    widget = self.query_one(f"#group-{group.key}", SelectionList)
                    if button_id == "select-all":
                        widget.select_all()
                    else:
                        widget.deselect_all()
            event.stop()

    return InstallApp


def run_tui(output: Path, initial: Options) -> int:
    InstallApp = build_app_class()
    app = InstallApp(output=output, initial=initial, kvm_available=kvm_supported())
    result = app.run()
    return int(result) if isinstance(result, int) else 0


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list:
        print_catalog()
        return 0

    if args.kvm is None:
        args.kvm = kvm_supported()

    headless = has_selection_flags(args) or not sys.stdin.isatty()
    if headless:
        if not has_selection_flags(args) and not sys.stdin.isatty():
            print("No terminal detected; using the default selection.", file=sys.stderr)
        return run_headless(args)

    initial = load_existing(args.output)
    if initial is None:
        initial = build_selection(desktop=args.de or DEFAULT_DE, kvm=bool(args.kvm))
    else:
        initial.kvm = bool(args.kvm)
        if args.de:
            try:
                initial.desktop = validate_desktop(args.de)
            except ValueError as error:
                print(f"error: {error}", file=sys.stderr)
                return 2

    try:
        return run_tui(args.output, initial)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
