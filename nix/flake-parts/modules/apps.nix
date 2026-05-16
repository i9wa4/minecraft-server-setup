{ lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      mc-server = lib.getExe config.packages.mc-server;
      mbs = lib.getExe config.packages.mbs;
      mjs = lib.getExe config.packages.mjs;
      shellList = values: lib.concatMapStringsSep " " lib.escapeShellArg values;
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
      mkSystemdInstallApp =
        profile: servers:
        let
          app = pkgs.writeShellApplication {
            name = "${profile}-install";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nix
              pkgs.systemd
            ];
            text = ''
              usage() {
                cat <<USAGE
              Usage: nix run '.#${profile}-install'

              Build the ${profile} Home Manager unit set, keep it with a
              repo-owned GC root, link only the Minecraft user systemd units,
              and enable/start the service and timers.

              Environment:
                MINECRAFT_SETUP_REPO  Repository checkout. Defaults to the
                                      current directory, then ~/mc/server-setup.
              USAGE
              }

              case "''${1:-}" in
                -h | --help | help)
                  usage
                  exit 0
                  ;;
                "")
                  ;;
                *)
                  usage >&2
                  exit 2
                  ;;
              esac

              profile=${lib.escapeShellArg profile}
              servers=(${shellList servers})
              repo_root="''${MINECRAFT_SETUP_REPO:-$PWD}"
              if [ ! -f "''${repo_root}/flake.nix" ]; then
                repo_root="''${HOME}/mc/server-setup"
              fi
              if [ ! -f "''${repo_root}/flake.nix" ]; then
                echo "cannot find server-setup flake; set MINECRAFT_SETUP_REPO" >&2
                exit 1
              fi

              state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
              state_dir="''${state_home}/mc-server-setup"
              root="''${state_dir}/''${profile}-home-manager-generation"
              unit_dir="''${HOME}/.config/systemd/user"

              mkdir -p "''${state_dir}" "''${unit_dir}"

              generation="$(
                nix build --no-link --print-out-paths \
                  "path:''${repo_root}#homeConfigurations.''${profile}.activationPackage"
              )"
              nix-store --add-root "''${root}" --indirect --realise "''${generation}" >/dev/null

              unit_src="''${root}/home-files/.config/systemd/user"
              if [ ! -d "''${unit_src}" ]; then
                echo "missing generated systemd user unit directory: ''${unit_src}" >&2
                exit 1
              fi

              link_unit() {
                local unit source target current
                unit="$1"
                source="''${unit_src}/''${unit}"
                target="''${unit_dir}/''${unit}"

                if [ ! -e "''${source}" ]; then
                  echo "missing generated unit: ''${source}" >&2
                  exit 1
                fi

                if [ -e "''${target}" ] || [ -L "''${target}" ]; then
                  if [ ! -L "''${target}" ]; then
                    echo "refusing to replace non-symlink unit: ''${target}" >&2
                    exit 1
                  fi

                  current="$(readlink "''${target}")"
                  case "''${current}" in
                    "''${source}" | "''${unit_src}/"* | /nix/store/*-home-manager-files/.config/systemd/user/"''${unit}" | /nix/store/*-"''${unit}"/"''${unit}")
                      ;;
                    *)
                      echo "refusing to replace existing unit symlink: ''${target} -> ''${current}" >&2
                      exit 1
                      ;;
                  esac
                fi

                ln -sfn "''${source}" "''${target}"
              }

              units=()
              enable_units=()
              for server in "''${servers[@]}"; do
                for unit in \
                  "''${server}.service" \
                  "''${server}-update.service" \
                  "''${server}-backup-local.service" \
                  "''${server}-update.timer" \
                  "''${server}-backup-local.timer"; do
                  link_unit "''${unit}"
                  units+=("''${unit}")
                done

                enable_units+=(
                  "''${server}.service"
                  "''${server}-update.timer"
                  "''${server}-backup-local.timer"
                )
              done

              systemctl --user daemon-reload
              systemctl --user reset-failed "''${units[@]}" 2>/dev/null || true
              for unit in "''${enable_units[@]}"; do
                rm -f "''${unit_dir}/default.target.wants/''${unit}"
                rm -f "''${unit_dir}/timers.target.wants/''${unit}"
              done
              systemctl --user enable --force "''${enable_units[@]}"
              systemctl --user start "''${enable_units[@]}"

              echo "installed Minecraft systemd units for profile: ''${profile}"
              echo "GC root: ''${root}"
              for server in "''${servers[@]}"; do
                systemctl --user --no-pager list-timers "''${server}-*"
              done
            '';
          };
        in
        {
          type = "app";
          program = "${app}/bin/${profile}-install";
          meta.description = "Install ${profile} Minecraft user systemd units";
        };
      mkSystemdUninstallApp =
        profile: servers:
        let
          app = pkgs.writeShellApplication {
            name = "${profile}-uninstall";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.systemd
            ];
            text = ''
              usage() {
                cat <<USAGE
              Usage: nix run '.#${profile}-uninstall'

              Disable and remove the Minecraft user systemd units for ${profile}.
              Stopping the server service runs its ExecStop command.
              USAGE
              }

              case "''${1:-}" in
                -h | --help | help)
                  usage
                  exit 0
                  ;;
                "")
                  ;;
                *)
                  usage >&2
                  exit 2
                  ;;
              esac

              profile=${lib.escapeShellArg profile}
              servers=(${shellList servers})
              state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
              root="''${state_home}/mc-server-setup/''${profile}-home-manager-generation"
              unit_dir="''${HOME}/.config/systemd/user"

              disable_units=()
              remove_units=()
              for server in "''${servers[@]}"; do
                disable_units+=(
                  "''${server}.service"
                  "''${server}-update.timer"
                  "''${server}-backup-local.timer"
                )
                remove_units+=(
                  "''${server}.service"
                  "''${server}-update.service"
                  "''${server}-backup-local.service"
                  "''${server}-update.timer"
                  "''${server}-backup-local.timer"
                )
              done

              systemctl --user disable --now "''${disable_units[@]}" 2>/dev/null || true

              for unit in "''${remove_units[@]}"; do
                rm -f "''${unit_dir}/''${unit}"
                rm -f "''${unit_dir}/default.target.wants/''${unit}"
                rm -f "''${unit_dir}/timers.target.wants/''${unit}"
              done

              rm -f "''${root}"
              systemctl --user daemon-reload
              systemctl --user reset-failed "''${remove_units[@]}" 2>/dev/null || true

              echo "removed Minecraft systemd units for profile: ''${profile}"
            '';
          };
        in
        {
          type = "app";
          program = "${app}/bin/${profile}-uninstall";
          meta.description = "Uninstall ${profile} Minecraft user systemd units";
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
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        mbs-install = mkSystemdInstallApp "mbs" [ "mbs" ];
        mbs-uninstall = mkSystemdUninstallApp "mbs" [ "mbs" ];
        mjs-install = mkSystemdInstallApp "mjs" [ "mjs" ];
        mjs-uninstall = mkSystemdUninstallApp "mjs" [ "mjs" ];
        mc-install = mkSystemdInstallApp "mc" [
          "mbs"
          "mjs"
        ];
        mc-uninstall = mkSystemdUninstallApp "mc" [
          "mbs"
          "mjs"
        ];
      };
    };
}
