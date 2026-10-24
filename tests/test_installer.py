"""Tests for the TrevVM installer (no Docker required)."""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import installer


def run_installer(tmp_path: Path, *args: str) -> tuple[int, Path]:
    output = tmp_path / "options.json"
    code = installer.main(["--output", str(output), *args])
    return code, output


def read_options(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_defaults_payload(tmp_path: Path) -> None:
    code, output = run_installer(tmp_path, "--defaults", "--no-kvm")
    assert code == 0
    data = read_options(output)
    assert data["schema"] == installer.SCHEMA
    assert data["DE"] == installer.DEFAULT_DE
    assert data["enablekvm"] is False
    assert data["packages"] == installer.DEFAULTS["defaultapps"]


def test_explicit_apps_follow_catalog_order(tmp_path: Path) -> None:
    code, output = run_installer(tmp_path, "--apps", "vlc,wine")
    assert code == 0
    assert read_options(output)["packages"] == ["wine", "vlc"]


def test_unknown_app_is_rejected(tmp_path: Path) -> None:
    code, output = run_installer(tmp_path, "--apps", "not-a-real-app")
    assert code == 2
    assert not output.exists()


def test_desktop_aliases_are_accepted(tmp_path: Path) -> None:
    code, output = run_installer(tmp_path, "--defaults", "--de", "XFCE4 (Lightweight)")
    assert code == 0
    assert read_options(output)["DE"] == "xfce"


def test_legacy_options_are_migrated(tmp_path: Path) -> None:
    legacy = {
        "defaultapps": [0, 3],
        "programming": [2],
        "apps": [1],
        "enablekvm": True,
        "DE": "Cinnamon (Recommended)",
    }
    path = tmp_path / "options.json"
    path.write_text(json.dumps(legacy), encoding="utf-8")

    options = installer.load_existing(path)
    assert options is not None
    assert options.desktop == "cinnamon"
    assert options.kvm is True
    assert options.selected["defaultapps"] == ["wine", "discord"]
    assert options.selected["programming"] == ["vscodium"]
    assert options.selected["apps"] == ["libreoffice"]


def test_flat_package_list_is_understood(tmp_path: Path) -> None:
    path = tmp_path / "options.json"
    path.write_text(json.dumps({"DE": "i3", "packages": ["vlc", "wine"]}), encoding="utf-8")

    options = installer.load_existing(path)
    assert options is not None
    assert options.desktop == "i3"
    assert options.selected["defaultapps"] == ["wine"]
    assert options.selected["apps"] == ["vlc"]


def test_catalog_scripts_exist() -> None:
    root = Path(__file__).resolve().parents[1]
    for group in installer.GROUPS:
        for package in group.packages:
            script = root / "root" / "installable-apps" / package.script
            assert script.is_file(), f"missing {script}"
    for desktop in installer.DESKTOPS:
        assert (root / "root" / desktop.script).is_file(), desktop.script


def test_tui_actions_fit_80x24(tmp_path: Path) -> None:
    initial = installer.build_selection(kvm=False)

    async def exercise() -> None:
        app_class = installer.build_app_class()
        app = app_class(output=tmp_path / "options.json", initial=initial, kvm_available=False)
        async with app.run_test(size=(80, 24)) as pilot:
            await pilot.pause()
            actions = app.query_one("#actions")
            assert actions.region.y + actions.region.height <= app.size.height

    asyncio.run(exercise())


def test_tui_confirm_writes_file(tmp_path: Path) -> None:
    output = tmp_path / "options.json"
    initial = installer.build_selection(kvm=False)

    async def exercise() -> None:
        app_class = installer.build_app_class()
        app = app_class(output=output, initial=initial, kvm_available=False)
        async with app.run_test(size=(120, 44)) as pilot:
            await pilot.pause()
            await pilot.click("#select-all")
            await pilot.pause()
            await pilot.click("#install")
            await pilot.pause()
            await pilot.click("#confirm")
            await pilot.pause()

    asyncio.run(exercise())
    data = read_options(output)
    assert len(data["packages"]) == len(installer.PACKAGE_IDS)
    assert data["enablekvm"] is False
