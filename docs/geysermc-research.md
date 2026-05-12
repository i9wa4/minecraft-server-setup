# GeyserMC Research Notes

Date: 2026-05-12

## Goal

Evaluate a future `mjs` design where macOS Java Edition players and Bedrock
clients can play together.

This is a Java-server cross-play design. Geyser lets Bedrock clients join a
Java server. It does not let Java clients join the existing Bedrock server.

## Current Repository Fit

The existing repo already separates server flavors:

- `mbs`: Bedrock dedicated server
- `mjs`: Java server

The Geyser path should stay under `mjs`. That keeps the current Bedrock server
simple and avoids turning `mbs` into a mixed-purpose entrypoint.

## Candidate Designs

| Design                         | Summary                                                                                                                        | Fit                                           |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- |
| Paper plugin in `mjs`          | Run `itzg/minecraft-server` with `TYPE=PAPER`, install Geyser and Floodgate as plugins, expose Java TCP and Bedrock UDP ports. | Best first implementation.                    |
| Standalone Geyser sidecar      | Run Geyser as a separate process/container pointing at `mjs`. Floodgate needs key sharing from the Java server plugin.         | Useful later if isolation matters.            |
| Proxy layer                    | Put Velocity/Bungee in front, install Geyser on the proxy.                                                                     | Too much for the current single-server setup. |

## Recommended First Implementation

Use the Paper plugin model inside `compose.mjs.yml`.

Expected shape:

- keep `mjs` as `itzg/minecraft-server`
- set Java server type to Paper
- auto-download Geyser and Floodgate through the image `PLUGINS` mechanism
- publish Java TCP for Java clients
- publish one Bedrock-facing UDP port for Geyser
- set Geyser `auth-type` to `floodgate`
- keep the Java server in online mode
- keep the Geyser/Floodgate generated secrets host-local and untracked

If `mbs` is running on the same host, do not publish the same Bedrock UDP port
from both `mbs` and `mjs`. Either stop `mbs` during Geyser testing or configure
`mjs` to use a different Bedrock-facing UDP port.

## World Implications

Geyser does not bridge into the current Bedrock world. Cross-play happens in a
Java world served by `mjs`.

Possible paths:

- start a new `mjs` Java world for cross-play
- keep `mbs` as the existing Bedrock world and use `mjs` separately
- investigate Bedrock-to-Java world conversion as a separate migration project

The conversion path should be treated as risky until tested on a copy of the
world data.

## Operations Notes

- Bedrock clients connect to the Geyser UDP port, not to the `mbs` Bedrock
  server port.
- Nintendo Switch still needs a custom-server workaround such as
  BedrockConnect for non-featured servers.
- The Home Manager service model can stay unchanged because `mjs up` still
  delegates to Docker Compose.
- `mjs host-init` currently opens only `PORT_SERVER` with one protocol. A
  Geyser design probably needs a second configurable port/protocol pair for
  Bedrock UDP.
- Java world backups should be solved before relying on `mjs` as the main
  world. `itzg/mc-backup` is a good fit because it coordinates with Java RCON.

## Source Notes

- Official Minecraft store page says Java Edition runs on Windows, macOS, and
  Linux, while Bedrock cross-play covers Windows 10/11, Xbox, Switch, PS5, and
  mobile. Source: <https://www.minecraft.net/store/minecraft>
- Geyser setup docs describe Geyser as a Bedrock-facing UDP listener that sends
  players to a Java server. Source:
  <https://geysermc.org/wiki/geyser/setup/>
- Geyser FAQ says Geyser does not allow Java players to connect to a Bedrock
  server. Source: <https://geysermc.org/wiki/geyser/faq/>
- Floodgate docs say Floodgate lets Bedrock accounts join Java servers without
  a paid Java account and is installed in addition to Geyser. Source:
  <https://geysermc.org/wiki/floodgate/>
- Floodgate setup docs require setting Geyser `auth-type` to `floodgate` and
  warn that Floodgate keys must not be distributed. Source:
  <https://geysermc.org/wiki/floodgate/setup/>
- `itzg/minecraft-server` docs show a Paper server with Geyser and Floodgate
  installed via `PLUGINS`, publishing Java TCP and Bedrock UDP ports. Source:
  <https://docker-minecraft-server.readthedocs.io/en/latest/misc/examples/>
- `itzg/minecraft-server` Paper docs say `TYPE=PAPER` automatically downloads
  and runs Paper. Source:
  <https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/>
- `itzg/mc-backup` docs say Java backups are coordinated through RCON and that
  the tool does not support Bedrock Edition. Source:
  <https://github.com/itzg/docker-mc-backup>
