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

### Docker Compose Shape

The expected Docker Compose direction is:

```yaml
services:
  public:
    image: itzg/minecraft-server:latest
    container_name: ${SERVER_NAME}
    user: ${MY_UID}:${MY_GID}
    restart: always
    env_file:
      - ${ENV_FILE:-.env.mjs}
    tty: true
    stdin_open: true
    ports:
      - ${PORT_SERVER}:${PORT_SERVER}/tcp
      - ${PORT_BEDROCK}:${PORT_BEDROCK}/udp
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "LATEST"
      UID: ${MY_UID}
      GID: ${MY_GID}
      TZ: ${MY_TZ}
      SERVER_NAME: ${SERVER_NAME}
      MOTD: ${SERVER_MOTD}
      LEVEL: ${WORLD_NAME}
      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
    volumes:
      - "${DIR_SERVER}:/data"
```

`PORT_SERVER` remains the Java TCP port. `PORT_BEDROCK` is the Bedrock-facing
UDP port that Geyser listens on.

The first server start generates plugin configuration under the Java server
data directory. The important Geyser settings are:

```yaml
bedrock:
  address: 0.0.0.0
  port: 19132

remote:
  auth-type: floodgate
```

The exact `bedrock.port` value should match `PORT_BEDROCK`. Keep Floodgate key
files in the ignored server data directory. Do not commit generated keys or
host-local runtime values.

### Port Options

| Option          | Shape                                                                    | Tradeoff                                                         |
| --------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| Geyser on 19132 | Stop or move `mbs`, then publish `mjs` Geyser on `19132/udp`.            | Easiest for Bedrock clients, but conflicts with current `mbs`.   |
| Geyser on 19133 | Keep `mbs` on `19132/udp`, publish `mjs` Geyser on `19133/udp`.          | Supports side-by-side testing, but clients must choose the port. |
| Move `mbs`      | Move Bedrock dedicated server to another UDP port and give Geyser 19132. | Keeps both services, but changes the existing Bedrock endpoint.  |

For initial testing, `19133/udp` is the least disruptive. For a final
Switch-friendly endpoint, `19132/udp` is simpler if the existing Bedrock server
can be stopped, moved, or retired.

### Switch Access

Nintendo Switch cannot normally add arbitrary Bedrock servers from the server
list UI. Switch access needs a custom-server workaround such as BedrockConnect
or a GeyserConnect-compatible flow.

Expected player path:

1. Configure the Switch network DNS for the chosen connector.
2. Open Minecraft on Switch and select a supported featured server entry.
3. Use the connector UI to enter the server address and Geyser UDP port.
4. Join the Paper Java server through Geyser.

The server still needs normal inbound UDP reachability for `PORT_BEDROCK`.
If the host is behind a home router, forward that UDP port to the server host.

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

## Implementation Plan

1. Add `PORT_BEDROCK` to `.env.mjs.example`.
2. Update `compose.mjs.yml` to run Paper and install Geyser plus Floodgate.
3. Publish both Java TCP and Bedrock UDP ports from the `mjs` compose service.
4. Update `mjs host-init` so it can open the Java TCP port and the Geyser UDP
   port.
5. Start `mjs` once and inspect the generated Geyser configuration.
6. Set or patch Geyser `auth-type` to `floodgate` and verify the Bedrock port.
7. Test with a Bedrock client that can directly add servers before testing
   Switch.
8. Test Switch through BedrockConnect or a GeyserConnect-compatible connector.
9. Add a Java-safe backup design, preferably with `itzg/mc-backup`, before
   treating `mjs` as the primary world.

## Open Questions

- Whether the final host should keep `mbs` and `mjs` running side by side.
- Whether Geyser should take `19132/udp` for the final Switch-friendly
  endpoint.
- Whether to manage generated Geyser config through compose-time patching or
  document a one-time host-local edit.
- Whether the existing Bedrock world should remain separate or be evaluated for
  a copied, test-only Bedrock-to-Java conversion.

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
- `itzg/minecraft-server` plugin docs describe installing plugins from URLs
  through the `PLUGINS` environment variable. Source:
  <https://docker-minecraft-server.readthedocs.io/en/latest/mods-and-plugins/>
- `itzg/mc-backup` docs say Java backups are coordinated through RCON and that
  the tool does not support Bedrock Edition. Source:
  <https://github.com/itzg/docker-mc-backup>
- BedrockConnect provides a DNS-based custom server flow for console Bedrock
  clients, including Nintendo Switch. Source:
  <https://github.com/Pugmatt/BedrockConnect>
- Geyser documents console connection workarounds for players who cannot add
  custom Bedrock servers directly. Source:
  <https://geysermc.org/wiki/geyser/using-geyser-with-consoles/>
