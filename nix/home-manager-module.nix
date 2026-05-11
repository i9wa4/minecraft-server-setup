{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrValues
    concatMapAttrs
    filterAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optionalAttrs
    types
    ;

  cfg = config.services.minecraft;
  homeDir = config.home.homeDirectory;
  system = pkgs.stdenv.hostPlatform.system;

  serverModule =
    { name, ... }:
    {
      options = {
        enable = mkEnableOption "Minecraft server ${name}";

        package = mkOption {
          type = types.package;
          default =
            if builtins.hasAttr name self.packages.${system} then
              self.packages.${system}.${name}
            else
              self.packages.${system}.mc-server;
          defaultText = "self.packages.\${pkgs.system}.${name}";
          description = "Package that provides the ${name} command.";
        };

        repoDir = mkOption {
          type = types.str;
          default = "${homeDir}/mc/server-setup";
          description = "Repository checkout used as the Docker Compose working directory.";
        };

        envFile = mkOption {
          type = types.str;
          default = "${homeDir}/mc/server-setup/.env.${name}";
          description = "Environment file used for Docker Compose interpolation and container env.";
        };

        composeFile = mkOption {
          type = types.str;
          default =
            if name == "mbs" then
              "${homeDir}/mc/server-setup/compose.mbs.yml"
            else
              "${homeDir}/mc/server-setup/compose.${name}.yml";
          description = "Docker Compose file for this server.";
        };

        startAtLogin = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to start the Docker Compose service with the user systemd target.";
        };

        updateOnCalendar = mkOption {
          type = types.nullOr types.str;
          default = "Sat 6:00:00";
          description = "systemd OnCalendar value for image updates. Set to null to disable.";
        };

        backup = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable local core-config backup service and timer.";
          };

          localOnCalendar = mkOption {
            type = types.str;
            default = "Sat 5:00:00";
            description = "systemd OnCalendar value for local backups.";
          };

          cloud = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to enable the S3 backup sync service and timer.";
            };

            onCalendar = mkOption {
              type = types.str;
              default = "Sat 5:10:00";
              description = "systemd OnCalendar value for cloud backup sync.";
            };
          };
        };
      };
    };

  enabledServers = filterAttrs (_: server: server.enable) cfg.servers;

  commandFor = name: server: "${server.package}/bin/${name}";

  serviceEnvFor = name: server: [
    "MINECRAFT_SERVER_ID=${name}"
    "MINECRAFT_REPO_ROOT=${server.repoDir}"
    "MINECRAFT_ENV_FILE=${server.envFile}"
    "MINECRAFT_COMPOSE_FILE=${server.composeFile}"
  ];

  mkServerService =
    name: server:
    nameValuePair name {
      Unit = {
        Description = "Minecraft server ${name}";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = server.repoDir;
        Environment = serviceEnvFor name server;
        ExecStart = "${commandFor name server} up";
        ExecStop = "${commandFor name server} down";
        TimeoutStartSec = "10min";
        TimeoutStopSec = "5min";
      };
      Install = mkIf server.startAtLogin {
        WantedBy = [ "default.target" ];
      };
    };

  mkUpdateService =
    name: server:
    nameValuePair "${name}-update" {
      Unit.Description = "Minecraft server ${name} update";
      Service = {
        Type = "oneshot";
        WorkingDirectory = server.repoDir;
        Environment = serviceEnvFor name server;
        ExecStart = "${commandFor name server} update";
        TimeoutStartSec = "15min";
      };
    };

  mkBackupLocalService =
    name: server:
    nameValuePair "${name}-backup-local" {
      Unit.Description = "Minecraft server ${name} local backup";
      Service = {
        Type = "oneshot";
        WorkingDirectory = server.repoDir;
        Environment = serviceEnvFor name server;
        ExecStart = "${commandFor name server} backup-local";
      };
    };

  mkBackupCloudService =
    name: server:
    nameValuePair "${name}-backup-cloud" {
      Unit = {
        Description = "Minecraft server ${name} cloud backup";
        After = [ "${name}-backup-local.service" ];
        Wants = [ "${name}-backup-local.service" ];
      };
      Service = {
        Type = "oneshot";
        WorkingDirectory = server.repoDir;
        Environment = serviceEnvFor name server;
        ExecStart = "${commandFor name server} backup-cloud";
      };
    };

  mkUpdateTimer =
    name: server:
    optionalAttrs (server.updateOnCalendar != null) {
      "${name}-update" = {
        Unit.Description = "Minecraft server ${name} update timer";
        Timer = {
          OnCalendar = server.updateOnCalendar;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };

  mkBackupTimers =
    name: server:
    optionalAttrs server.backup.enable {
      "${name}-backup-local" = {
        Unit.Description = "Minecraft server ${name} local backup timer";
        Timer = {
          OnCalendar = server.backup.localOnCalendar;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    }
    // optionalAttrs server.backup.cloud.enable {
      "${name}-backup-cloud" = {
        Unit.Description = "Minecraft server ${name} cloud backup timer";
        Timer = {
          OnCalendar = server.backup.cloud.onCalendar;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
in
{
  options.services.minecraft = {
    enable = mkEnableOption "Minecraft server management";

    servers = mkOption {
      type = types.attrsOf (types.submodule serverModule);
      default = { };
      description = "Minecraft servers keyed by command name, such as mbs or mjs.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = attrValues (
      mapAttrs' (name: server: nameValuePair name server.package) enabledServers
    );

    systemd.user.services = mkMerge [
      (mapAttrs' mkServerService enabledServers)
      (mapAttrs' mkUpdateService enabledServers)
      (mapAttrs' mkBackupLocalService (filterAttrs (_: server: server.backup.enable) enabledServers))
      (mapAttrs' mkBackupCloudService (
        filterAttrs (_: server: server.backup.cloud.enable) enabledServers
      ))
    ];

    systemd.user.timers = mkMerge [
      (concatMapAttrs mkUpdateTimer enabledServers)
      (concatMapAttrs mkBackupTimers enabledServers)
    ];
  };
}
