{
  self,
  system,
  pkgs,
  ...
}:
let
  legacyShellScripts = [
    ./../bin/backup-to-cloud.sh
    ./../bin/backup-to-local.sh
    ./../bin/init.sh
    ./../bin/update.sh
  ];

  testEnv = pkgs.writeText "minecraft-test.env" ''
    MY_UID=1000
    MY_GID=1000
    MY_USER_NAME=uma
    MY_TZ=Asia/Tokyo
    PORT_SERVER=19132
    PORT_SERVER_PROTO=udp
    PORT_SSH=22
    SERVER_NAME=mbs
    SERVER_MOTD=Minecraft Java Server
    WORLD_NAME=world
    DIR_ROOT=/tmp/minecraft
    DIR_REPO=${self}
    DIR_BACKUP=/tmp/minecraft/backup
    DIR_BACKUP_CORE=/tmp/minecraft/backup/core
    DIR_BACKUP_WORLDS=/tmp/minecraft/backup/worlds
    DIR_SERVER=/tmp/minecraft/server
    AWS_PROFILE=test
    S3_BACKUP_URI=s3://example/minecraft
  '';

  composeCheck =
    name: composeFile:
    pkgs.runCommand "check-${name}-compose"
      {
        nativeBuildInputs = [
          pkgs.docker-compose
        ];
      }
      ''
        export ENV_FILE=${testEnv}
        docker-compose --env-file ${testEnv} -f ${composeFile} config >/dev/null
        touch $out
      '';

  homeManagerCheck =
    pkgs.runCommand "check-home-manager-module"
      {
        nativeBuildInputs = [ pkgs.jq ];
        service = builtins.toJSON self.homeConfigurations.mc.config.systemd.user.services.mbs.Service;
        timers = builtins.toJSON self.homeConfigurations.mc.config.systemd.user.timers;
      }
      ''
        printf '%s' "$service" | jq -e '.ExecStart[0] | contains("/bin/mbs up")' >/dev/null
        printf '%s' "$timers" | jq -e 'has("mbs-update") and has("mbs-backup-local") and (has("mbs-backup-cloud") | not)' >/dev/null
        touch $out
      '';

  legacyShellCheck =
    pkgs.runCommand "check-legacy-shell"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.shellcheck
        ];
      }
      ''
        for script in ${pkgs.lib.escapeShellArgs legacyShellScripts}; do
          bash -n "$script"
          shellcheck "$script"
        done
        touch $out
      '';

  nixLintCheck =
    pkgs.runCommand "check-nix-lint"
      {
        nativeBuildInputs = [
          pkgs.deadnix
          pkgs.statix
        ];
      }
      ''
        cd ${self}
        statix check .
        deadnix --fail flake.nix nix treefmt.nix
        touch $out
      '';
in
{
  packages = self.packages.${system}.mc-server;
  mbs = self.packages.${system}.mbs;
  mjs = self.packages.${system}.mjs;
  legacy-shell = legacyShellCheck;
  nix-lint = nixLintCheck;
  compose-mbs = composeCheck "mbs" ./../compose.yml;
  compose-mjs = composeCheck "mjs" ./../compose.mjs.yml;
}
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  home-manager-module = homeManagerCheck;
}
