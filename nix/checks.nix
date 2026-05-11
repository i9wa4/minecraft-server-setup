{
  self,
  system,
  pkgs,
  ...
}:
let
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
        mbsService = builtins.toJSON self.homeConfigurations.mbs.config.systemd.user.services.mbs.Service;
        mbsTimers = builtins.toJSON self.homeConfigurations.mbs.config.systemd.user.timers;
        mjsService = builtins.toJSON self.homeConfigurations.mjs.config.systemd.user.services.mjs.Service;
        mjsTimers = builtins.toJSON self.homeConfigurations.mjs.config.systemd.user.timers;
        mcServices = builtins.toJSON self.homeConfigurations.mc.config.systemd.user.services;
        mcTimers = builtins.toJSON self.homeConfigurations.mc.config.systemd.user.timers;
      }
      ''
        printf '%s' "$mbsService" | jq -e '.ExecStart[0] | contains("/bin/mbs up")' >/dev/null
        printf '%s' "$mbsTimers" | jq -e 'has("mbs-update") and has("mbs-backup-local") and (has("mbs-backup-cloud") | not)' >/dev/null
        printf '%s' "$mjsService" | jq -e '.ExecStart[0] | contains("/bin/mjs up")' >/dev/null
        printf '%s' "$mjsTimers" | jq -e 'has("mjs-update") and has("mjs-backup-local") and (has("mjs-backup-cloud") | not)' >/dev/null
        printf '%s' "$mcServices" | jq -e 'has("mbs") and has("mjs")' >/dev/null
        printf '%s' "$mcTimers" | jq -e 'has("mbs-update") and has("mjs-update") and has("mbs-backup-local") and has("mjs-backup-local")' >/dev/null
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

  githubActionsCheck =
    pkgs.runCommand "check-github-actions"
      {
        nativeBuildInputs = [
          pkgs.actionlint
          pkgs.ghalint
          pkgs.pinact
          pkgs.zizmor
        ];
      }
      ''
        cd ${self}
        workflow_files="$(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \))"
        actionlint $workflow_files
        ghalint run
        pinact run
        zizmor .github/workflows
        touch $out
      '';
in
{
  packages = self.packages.${system}.mc-server;
  mbs = self.packages.${system}.mbs;
  mjs = self.packages.${system}.mjs;
  nix-lint = nixLintCheck;
  github-actions = githubActionsCheck;
  compose-mbs = composeCheck "mbs" ./../compose.mbs.yml;
  compose-mjs = composeCheck "mjs" ./../compose.mjs.yml;
}
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  home-manager-module = homeManagerCheck;
}
