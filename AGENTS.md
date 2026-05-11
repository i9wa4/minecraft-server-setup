# AGENTS.md - i9wa4/minecraft-server-setup

## 1. Project Overview

Repository: `i9wa4/minecraft-server-setup` - Nix-managed Minecraft server
operations for Ubuntu.

This file is the repository bootstrap checklist. Keep it small. Put durable
usage details in `README.md` and implementation rules in the relevant Nix files.

The repo separates server flavors by command and local config:

- `mbs`: Minecraft Bedrock Server
- `mjs`: Minecraft Java Server

`compose.mbs.yml` and `compose.mjs.yml` remain Docker runtime declarations. Nix
owns the CLI packages, Home Manager module, systemd user services/timers, and
checks.

## 2. Start Here

1. Run `git status --short --branch` before editing.
2. Read the relevant file before editing it.
3. Keep changes scoped. Do not reorganize unrelated host setup or backup logic.
4. Prefer Nix-managed changes over adding new shell scripts.
5. Verify with commands from Section 5 before reporting success.
6. Do not revert user changes.

## 3. Source of Truth

- `flake.nix`: flake outputs, apps, checks, and standalone Home Manager config.
- `nix/packages.nix`: generated `mc-server`, `mbs`, and `mjs` CLIs.
- `nix/home-manager-module.nix`: `services.minecraft` options and systemd user
  units.
- `nix/checks.nix`: flake checks for packages, compose config, and module
  wiring.
- `treefmt.nix`: repo formatting policy for `nix fmt` and
  `checks.*.formatting`.
- `.github/workflows/ci.yml`: GitHub Actions entrypoint; keep it thin and let
  Nix checks own repo validation.
- `.github/dependabot.yml`: dependency update policy for GitHub Actions and Nix.
- `docs/design.md`: design notes and operational boundaries.
- `compose.mbs.yml`: Bedrock runtime and Bedrock world-backup sidecar.
- `compose.mjs.yml`: Java runtime.
- `.env.mbs.example` and `.env.mjs.example`: local env templates only.
- `README.md`: human operating instructions.

Systemd unit files are generated from `nix/home-manager-module.nix`; do not add
an `etc/` unit-file source tree.

Operational scripts are generated from `nix/packages.nix`; do not add a `bin/`
script source tree for normal operations.

## 4. Operational Rules

- Ubuntu is the target server platform.
- Docker daemon, sshd, UFW, and `loginctl enable-linger` are host bootstrap
  concerns. Do not pretend Home Manager fully owns them.
- `host-setup` follows Docker's official Ubuntu apt repository installation
  flow. Do not replace it with Ubuntu's unofficial `docker.io` package.
- Runtime secrets and host-local values belong in ignored `.env.mbs` and
  `.env.mjs` files, not in Nix or committed docs.
- Do not run `mbs backup-cloud`, `nix run .#mbs-backup-cloud`, `aws sso login`,
  `aws configure`, or any AWS credential-changing command unless the user
  explicitly requests it in the current turn.
- Cloud backup is manual by default. Do not enable `backup.cloud.enable` unless
  the user explicitly asks for scheduled cloud backup.
- Bedrock world backups are owned by the `backup` service in `compose.mbs.yml`.
  `mbs backup-local` and `mjs backup-local` are for core config archives.
- Java world backups need a Java-safe strategy. Do not add blind live-copy world
  backups for `mjs`.
- Treat `mbs` and `mjs` as peer server flavors. Do not make one the default
  operational path unless the user explicitly asks.
- Future GeyserMC work belongs under `mjs`; document any extra Bedrock-facing
  UDP port and avoid port conflicts with `mbs`.

## 5. Checks

New flake files must be staged before Nix can see them:

```sh
git add <new-files>
nix fmt
```

Use `path:$PWD` while files are untracked or before committing new flake files:

```sh
nix flake check --all-systems path:$PWD
```

For focused package checks:

```sh
nix build path:$PWD#mbs path:$PWD#mjs path:$PWD#mc-server
```

For CLI smoke checks:

```sh
nix run path:$PWD#mbs -- help
nix run path:$PWD#mjs -- help
```

For Home Manager wiring checks:

```sh
nix eval path:$PWD#homeConfigurations.mbs.config.systemd.user.timers --json | jq 'keys'
nix eval path:$PWD#homeConfigurations.mjs.config.systemd.user.timers --json | jq 'keys'
nix eval path:$PWD#homeConfigurations.mc.config.systemd.user.timers --json | jq 'keys'
```

After `flake.nix` is tracked, the normal forms are acceptable:

```sh
nix fmt
nix flake check --all-systems
nix build .#mbs .#mjs .#mc-server
```

Do not require a Docker daemon for repository checks. Compose validation belongs
in `nix/checks.nix` via `docker-compose config`. Shell and Nix linting belong in
flake checks, not ad hoc local-only commands.

## 6. Before Handoff

Report:

- Which checks were run.
- Any checks skipped and why.
- Whether cloud backup behavior changed.
- Any server-side action the user must run manually.
