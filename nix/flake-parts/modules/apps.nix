{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      mc-server = lib.getExe config.packages.mc-server;
      mbs = lib.getExe config.packages.mbs;
      mjs = lib.getExe config.packages.mjs;
      mkApp =
        package: command:
        let
          app = pkgs.writeShellApplication {
            name = "mc-${command}";
            text = ''
              exec ${package} ${command} "$@"
            '';
          };
        in
        {
          type = "app";
          program = "${app}/bin/mc-${command}";
          meta.description = "Run ${command}";
        };
    in
    {
      apps = {
        default = {
          type = "app";
          program = mc-server;
          meta.description = "Run the Minecraft server operations CLI";
        };
        mc-server = {
          type = "app";
          program = mc-server;
          meta.description = "Run the Minecraft server operations CLI";
        };
        mbs = {
          type = "app";
          program = mbs;
          meta.description = "Run the Minecraft Bedrock server operations CLI";
        };
        mjs = {
          type = "app";
          program = mjs;
          meta.description = "Run the Minecraft Java server operations CLI";
        };
        mbs-doctor = mkApp mbs "doctor";
        mbs-host-setup = mkApp mbs "host-setup";
        mbs-host-init = mkApp mbs "host-init";
        mbs-init = mkApp mbs "init";
        mbs-up = mkApp mbs "up";
        mbs-down = mkApp mbs "down";
        mbs-stop = mkApp mbs "stop";
        mbs-restart = mkApp mbs "restart";
        mbs-update = mkApp mbs "update";
        mbs-ps = mkApp mbs "ps";
        mbs-logs = mkApp mbs "logs";
        mbs-timers = mkApp mbs "timers";
        mbs-backup-local = mkApp mbs "backup-local";
        mbs-backup-cloud = mkApp mbs "backup-cloud";
        mjs-doctor = mkApp mjs "doctor";
        mjs-host-setup = mkApp mjs "host-setup";
        mjs-host-init = mkApp mjs "host-init";
        mjs-init = mkApp mjs "init";
        mjs-up = mkApp mjs "up";
        mjs-down = mkApp mjs "down";
        mjs-stop = mkApp mjs "stop";
        mjs-restart = mkApp mjs "restart";
        mjs-update = mkApp mjs "update";
        mjs-ps = mkApp mjs "ps";
        mjs-logs = mkApp mjs "logs";
        mjs-timers = mkApp mjs "timers";
        mjs-backup-local = mkApp mjs "backup-local";
        mjs-backup-cloud = mkApp mjs "backup-cloud";
      };
    };
}
