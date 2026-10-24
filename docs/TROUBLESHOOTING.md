# Troubleshooting

Start with the built-in diagnostics:

```bash
./trevvm.sh doctor
./trevvm.sh logs --tail 100
./trevvm.sh status
```

The installer also writes `trevvm-install.log` in the directory you ran it
from.

## Docker problems

**`docker: command not found`**
Install Docker Engine, or open the codespace from a devcontainer image that
includes it. On Linux, `sudo apt-get install docker.io docker-compose-v2`.

**`permission denied while trying to connect to the Docker daemon socket`**
Add your user to the `docker` group and start a new shell:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

**`Cannot connect to the Docker daemon`**
Start Docker (`sudo systemctl start docker`) or start Docker Desktop. The
installer refuses to continue when the daemon is unreachable.

## Port problems

**`Port 3000 is already in use`**
Use another port, or let the installer choose one:

```bash
./install.sh --port 3001
./install.sh --port auto
```

If the old TrevVM container owns the port, `./trevvm.sh status` will show it.
`./trevvm.sh restart` reuses the existing container.

## Build problems

**`docker build` succeeds but the desktop has no apps**
A plain `docker build` uses Cinnamon with no optional apps. Run `./install.sh`
to choose a desktop and apps, or pass the selection explicitly:

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python installer.py --defaults --de xfce --output options.json
./install.sh --reinstall
```

**The build stops while installing an app**
Third-party repositories go down. The installer records the failure and keeps
going (set `TREVVM_STRICT_APPS=1` to make failures fatal). Inspect the app log:

```bash
./trevvm.sh shell
tail -n 100 /config/trevvm-apps.log
```

**`No space left on device`**
Codespaces disks are small. Remove unused images and build cache:

```bash
./trevvm.sh clean
docker system df
```

`./trevvm.sh clean` asks before pruning the builder cache.

## The page loads but the desktop is black

1. Wait 30-60 seconds; the first start configures the session.
2. `./trevvm.sh logs --tail 200` and look for `startwm` errors.
3. Try a lighter desktop: `./install.sh --reinstall --de xfce -y`.
4. Check that `/dev/kvm` is not being passed through on a host that lacks it.

If the container is `unhealthy`, the healthcheck could not open port 3000.
`docker inspect TrevVM --format '{{json .State.Health}}'` shows the probe log.

## KVM

`/dev/kvm` is optional. Without it the desktop runs in software mode, which is
slower but works. `--kvm` on a host without the device does not create it; the
installer warns and continues without acceleration.

## Authentication

KasmVNC starts without a login. To require one, recreate the container with:

```bash
TREVVM_USER=me TREVVM_PASSWORD='a-long-password' ./install.sh --reinstall -y
```

The password is stored in the container's environment, so treat it like any
other local secret and do not reuse an important password.

## Save data

Everything persistent lives in `Save/` (mounted at `/config`). If the desktop
resets, check that the mount is still there:

```bash
./trevvm.sh status
docker inspect TrevVM --format '{{json .Mounts}}'
```

Permissions problems usually mean `PUID`/`PGID` do not match your user. The
installer passes the current `id -u` and `id -g`.

## Codespaces

* The forwarded port is private by default. Open the Ports tab and use the
  browser URL; do not share the `-3000` URL publicly.
* A codespace stops after inactivity. `./trevvm.sh start` brings the container
  back without rebuilding.
* If the codespace was deleted, `Save/` is gone too unless you backed it up
  with `./trevvm.sh backup`.

## Still stuck

Open a discussion with:

* the output of `./trevvm.sh doctor`
* `./trevvm.sh logs --tail 200`
* the installer log
* your desktop choice and whether `/dev/kvm` exists
