# Updating TrevVM

## Recommended

```bash
./trevvm.sh update
```

This pulls the latest source with `git pull --ff-only`, rebuilds the image and
recreates the container. `Save/` is preserved.

## If you installed from the standalone script

```bash
cd TrevVM
./install.sh --update
```

## Start an existing install

```bash
./trevvm.sh start
```

## What is preserved

* `Save/` - the desktop home directory and configuration.
* `options.json` - your desktop and app selection.

## What is replaced

* The `trevvm` image.
* The `TrevVM` container (same name, same port).
