# minecraft-server-setup

Nix-managed Minecraft server operations for Ubuntu.

This repository separates the server flavors by command and config:

- `mbs`: Minecraft Bedrock Server
- `mjs`: Minecraft Java Server

Docker Compose remains the runtime declaration. Nix owns the CLI packages, Home
Manager module, systemd user services/timers, formatter, and checks.

## 1. Operating Model

Host-level setup is still host-level:

- Docker daemon
- sshd
- UFW
- `loginctl enable-linger`

This repo manages the user-level Minecraft operations after those host basics
exist:

- `mbs` and `mjs` commands
- Docker Compose start/stop/update/log commands
- Home Manager user services and timers
- local backup timer for Bedrock core config
- manual cloud backup command

Cloud backup is not scheduled by default. Run it only from a shell where AWS
credentials are intentionally available.

## 2. Requirements

- Ubuntu server
- Nix with flakes enabled
- Home Manager
- Docker daemon with Compose v2
- UFW
- AWS CLI credentials, only when running manual S3 backup

Docker installation follows Docker's official Ubuntu apt repository docs:

- <https://docs.docker.com/engine/install/ubuntu/>
- <https://docs.docker.com/engine/install/linux-postinstall/>

This repo provides `host-setup` so the server setup stays with the Minecraft
operations repo instead of becoming a global dotfiles default.

## 3. Initial Setup

```sh
git clone https://github.com/i9wa4/minecraft-server-setup ~/mc/server-setup
cd ~/mc/server-setup
```

The checkout path is intentionally `~/mc/server-setup`, not `~/mbs/...`,
because this repository manages both `mbs` and `mjs`. Bedrock data defaults to
`~/mc/mbs`; Java data defaults to `~/mc/mjs`.

Create local env files. These are ignored by Git.

```sh
cp .env.mbs.example .env.mbs
cp .env.mjs.example .env.mjs
vim .env.mbs
```

Install Ubuntu host dependencies. This installs Docker Engine from Docker's
official apt repository, plus `openssh-server` and `ufw`. It also enables
`ssh`, `docker`, and `containerd`, and adds `MY_USER_NAME` to the `docker`
group.

```sh
nix run .#mbs-host-setup
```

Log out and back in after `host-setup` so Docker group membership is
re-evaluated.

Edit values for your host:

- `MY_UID`, `MY_GID`: numeric user/group IDs used by containers
- `MY_USER_NAME`: Ubuntu login user
- `PORT_SERVER`: Minecraft port
- `PORT_SERVER_PROTO`: `udp`, `tcp`, or `both`
- `PORT_SSH`: SSH port to allow in UFW
- `SERVER_NAME`: Compose project/container name
- `WORLD_NAME`: Bedrock `LEVEL_NAME` or Java `LEVEL`
- `DIR_REPO`: repo checkout path
- `DIR_SERVER`: server data directory
- `DIR_BACKUP`: backup root
- `DIR_BACKUP_CORE`: local core config backup directory
- `DIR_BACKUP_WORLDS`: Bedrock world backup directory
- `AWS_PROFILE`, `S3_BACKUP_URI`: required only for `backup-cloud`

Run doctor before changing the firewall.

```sh
nix run .#mbs-doctor
```

Initialize host firewall rules and systemd user lingering.

```sh
nix run .#mbs-host-init
```

For Java:

```sh
vim .env.mjs
nix run .#mjs-host-setup
nix run .#mjs-doctor
nix run .#mjs-host-init
```

`host-init` enables UFW. Confirm you are allowing the correct SSH port before
running it.

## 4. Start With Home Manager

The default standalone Home Manager configuration enables `mbs` and leaves
`mjs` disabled.

```sh
home-manager switch --flake .#mc
```

This creates:

- `mbs.service`
- `mbs-update.timer`
- `mbs-backup-local.timer`

The service starts Docker Compose through the `mbs` command. Timers run through
the same command, so the compose/env paths stay in one place.

Check the service and timers.

```sh
systemctl --user status mbs
systemctl --user list-timers 'mbs-*'
journalctl --user -u mbs -f
```

Start, stop, and restart through systemd:

```sh
systemctl --user start mbs
systemctl --user stop mbs
systemctl --user restart mbs
```

## 5. Manual Operations

Before Home Manager installs the packages, use `nix run`:

```sh
nix run .#mbs-up
nix run .#mbs-logs
nix run .#mbs-ps
nix run .#mbs-update
nix run .#mbs-backup-local
```

After Home Manager installs the packages, use the shorter command:

```sh
mbs up
mbs logs
mbs ps
mbs update
mbs backup-local
```

Java manual operations:

```sh
nix run .#mjs-up
nix run .#mjs-logs
nix run .#mjs-ps
nix run .#mjs-update
```

Equivalent installed commands:

```sh
mjs up
mjs logs
mjs ps
mjs update
```

Other useful commands:

```sh
mbs host-setup
mbs host-init
mbs down
mbs stop
mbs restart
mbs timers
mbs doctor
```

## 6. Enabling Java Service

`mjs` is wired into the Home Manager module but disabled in the default
standalone config. Enable it from another Home Manager config, or extend this
flake config:

```nix
{
  services.minecraft = {
    enable = true;
    servers.mjs = {
      enable = true;
      backup.enable = false;
      backup.cloud.enable = false;
    };
  };
}
```

Java world backups are disabled by default because live-copy backups can be
inconsistent. Add a Java-safe backup strategy before enabling scheduled Java
backups.

## 7. Updating

Update the repo and apply Home Manager changes:

```sh
cd ~/mc/server-setup
git pull
home-manager switch --flake .#mc
```

Pull new container images and restart the Bedrock server:

```sh
mbs update
```

The scheduled update timer runs `mbs update` using:

```nix
services.minecraft.servers.mbs.updateOnCalendar
```

Set it to `null` in a Home Manager override to disable the update timer.

## 8. Backup And Restore

World data and core config are backed up separately.

For `mbs`, world backups are handled by the `backup` service in `compose.yml`
using `kaiede/minecraft-bedrock-backup`. That container talks to the Bedrock
server and writes world backups into `DIR_BACKUP_WORLDS`.

The Nix-managed `mbs-backup-local.timer` only backs up core config files:

- `allowlist.json`
- `permissions.json`
- `server.properties`
- `valid_known_packs.json`
- `.env.mbs`

Run a local backup manually:

```sh
mbs backup-local
```

Run cloud backup manually only after intentionally logging in to AWS:

```sh
aws sso login --profile <profile>
mbs backup-cloud
```

`mbs backup-cloud` syncs `DIR_BACKUP` to `S3_BACKUP_URI`, so it uploads both
world backups and core config archives. No cloud backup timer is enabled unless
you explicitly set:

```nix
services.minecraft.servers.mbs.backup.cloud.enable = true;
```

Restore Bedrock world data:

```sh
mbs down
# restore/copy world data into "$DIR_SERVER/worlds"
# restore allowlist.json, permissions.json, server.properties if needed
mbs up
```

For `mjs`, use a Java-specific backup strategy, such as:

- RCON `save-off`, `save-all flush`, archive, then `save-on`
- a server-side backup plugin
- a short scheduled stop, archive, then start

Do not copy a live Java world directory blindly unless you accept occasional
inconsistent backups.

For stronger long-term retention, prefer a snapshot tool such as `restic` over a
plain `aws s3 sync`. `aws s3 sync` is simple and works for offsite copies, but
restic adds encryption, deduplication, retention policies, and safer restore
history.

## 9. Firewall

`mbs host-init` and `mjs host-init` set:

- default incoming policy: deny
- Minecraft server port from `PORT_SERVER` and `PORT_SERVER_PROTO`
- SSH port from `PORT_SSH`
- UFW enabled
- user lingering enabled for `MY_USER_NAME`

Inspect UFW:

```sh
sudo ufw status verbose
```

If the server IP came from DHCP, configure the fixed address at the router or OS
network layer. This repo only manages service ports, not DHCP/static IP
assignment.

## 10. Module Shape

The module is exported as:

```nix
self.homeManagerModules.default
```

The main option is:

```nix
services.minecraft.servers.<name>
```

Useful per-server options:

- `enable`
- `package`
- `repoDir`
- `envFile`
- `composeFile`
- `startAtLogin`
- `updateOnCalendar`
- `backup.enable`
- `backup.localOnCalendar`
- `backup.cloud.enable`
- `backup.cloud.onCalendar`

## 11. Troubleshooting

Check command/env/compose readiness:

```sh
mbs doctor
```

Check systemd:

```sh
systemctl --user status mbs
journalctl --user -u mbs -n 200
systemctl --user list-timers 'mbs-*'
```

Check Docker:

```sh
docker compose --env-file .env.mbs -f compose.yml -p mbs ps
docker compose --env-file .env.mbs -f compose.yml -p mbs logs --tail=100 -f
```

Check firewall:

```sh
sudo ufw status verbose
```

If `docker` exists but the daemon is unreachable, confirm Docker is running and
your user has Docker group access.

## 12. Legacy Scripts

The old `bin/init.sh`, `bin/update.sh`, and backup scripts are kept for manual
Bedrock operations. New Nix-managed usage should prefer `mbs` and `mjs`.

## 13. Development Checks

Format and validate the repo through Nix:

```sh
nix fmt
nix flake check --all-systems
nix build .#mbs .#mjs .#mc-server
```

While new flake files are still untracked:

```sh
git add <new-files>
nix fmt
nix flake check --all-systems path:$PWD
```
