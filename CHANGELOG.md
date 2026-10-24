# Changelog

## Unreleased - quality-of-life pass

### Installer

* Re-runnable: an existing checkout, container or `Save/` directory no longer
  aborts the install.
* New flags: `--dry-run`, `--status`, `--update`, `--reinstall`,
  `--uninstall`, `--purge`, `--port auto`, `--de`, `--apps`, `--all`,
  `--none`, `--kvm`, `--no-kvm`.
* Checks Docker, the daemon, disk space, memory and port conflicts before
  building.
* Creates a virtual environment instead of installing into the system Python.
* Waits for the healthcheck and prints the Codespaces forwarding URL.
* Writes `trevvm-install.log` and shows the last lines on failure.
* Optional KasmVNC basic auth through `TREVVM_USER` / `TREVVM_PASSWORD`.

### Installer UI

* Fixed the Back button crash and the invalid JSON writer.
* Selections use stable package ids instead of integer offsets.
* Re-runs preselect the previous choices.
* KVM switch reflects the host instead of always being on.
* Confirmation screen, select-all/clear buttons, and a headless mode for CI.

### Runtime

* New `trevvm.sh`: start, stop, restart, status, logs, shell, update, backup,
  restore, reset, doctor, clean, uninstall and `apps`.
* `apps install ID` adds a catalog app to a running VM without rebuilding.
* Healthcheck in the image and `docker-compose.yml` for compose users.
* Save directory is resolved to an absolute path and seeded without
  overwriting existing files.

### Fixed

* App scripts had CRLF line endings, no shebang and used `sudo` inside a root
  container; several installs failed silently.
* Deprecated `apt-key` usage replaced with signed keyrings.
* Steam, Discord and Minecraft installs now resolve dependencies through apt
  and clean up their temporary .deb files.
* LXQt pointed at a start script that did not exist.
* `startwm` scripts now use `exec`, quote paths and tolerate missing tools.
* Dockerfile receives the selection as a build argument and falls back to
  Cinnamon when built by hand, adds OCI labels and a healthcheck, and no
  longer leaves installer scripts in the image.

### Tooling and docs

* `apps.json` is the single source of truth for desktops and packages.
* CI runs ShellCheck, pytest and a cached Docker build.
* `.gitattributes` enforces LF for scripts, preventing the CRLF regression.
* README, UPDATES and a new troubleshooting guide match the actual behavior.

## v3.0.1

As presented, "days work."

### What's Changed

* days work by @TrevorTesch in https://github.com/TrevorTesch/TrevVM/pull/34
* Update CHANGELOG.md by @TrevorTesch in https://github.com/TrevorTesch/TrevVM/pull/35

**Full Changelog**: https://github.com/TrevorTesch/TrevVM/compare/v3.0.0...v3.0.1

## Help Us!

You can fork the repo and make pull requests. Before reporting an issue, make a
discussion about it.

## Security

Always report any security vulnerability privately to the maintainers. Do not
open a public issue for an unpatched vulnerability.

###### (C) 2026-present [TrevVM](https://github.com/TrevorTesch/TrevVM) and its contributors.
