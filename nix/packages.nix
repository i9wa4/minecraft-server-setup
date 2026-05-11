{
  pkgs,
  ...
}:
let
  minecraftServerScript = ''
    server_id="''${MINECRAFT_SERVER_ID:-minecraft}"
    repo_root="''${MINECRAFT_REPO_ROOT:-$PWD}"
    env_file="''${MINECRAFT_ENV_FILE:-.env.''${server_id}}"
    compose_file="''${MINECRAFT_COMPOSE_FILE:-compose.''${server_id}.yml}"

    cd "''${repo_root}"

    usage() {
      cat <<USAGE
    Usage: ''${server_id} <command>

    Commands:
      doctor        Check required host commands and env values
      host-init     Initialize host firewall and user lingering
      init          Create server directories
      up            Start the Minecraft server
      down          Stop and remove compose services
      stop          Stop compose services
      restart       Restart compose services
      update        Pull images and recreate services
      ps            Show compose service status
      logs          Follow compose logs
      timers        Show Minecraft systemd user timers
      backup-local  Back up core server files locally
      backup-cloud  Sync backups to S3
    USAGE
    }

    resolve_path() {
      local path="$1"
      case "''${path}" in
        /*) printf '%s\n' "''${path}" ;;
        *) printf '%s/%s\n' "''${repo_root}" "''${path}" ;;
      esac
    }

    env_path="$(resolve_path "''${env_file}")"
    compose_path="$(resolve_path "''${compose_file}")"

    require_command() {
      local command_name="$1"
      if ! command -v "''${command_name}" >/dev/null 2>&1; then
        echo "missing command: ''${command_name}" >&2
        return 1
      fi
    }

    require_env() {
      if [ ! -f "''${env_path}" ]; then
        echo "missing env file: ''${env_path}" >&2
        return 1
      fi

      set -o allexport
      # shellcheck disable=SC1090
      . "''${env_path}"
      set +o allexport

      : "''${MY_USER_NAME:?MY_USER_NAME must be set in ''${env_file}}"
      : "''${PORT_SERVER:?PORT_SERVER must be set in ''${env_file}}"
      : "''${PORT_SSH:?PORT_SSH must be set in ''${env_file}}"
      : "''${DIR_REPO:?DIR_REPO must be set in ''${env_file}}"
      : "''${DIR_SERVER:?DIR_SERVER must be set in ''${env_file}}"
      : "''${SERVER_NAME:?SERVER_NAME must be set in ''${env_file}}"
    }

    require_compose_file() {
      if [ ! -f "''${compose_path}" ]; then
        echo "missing compose file: ''${compose_path}" >&2
        return 1
      fi
    }

    compose() {
      require_env
      require_compose_file
      require_command docker
      ENV_FILE="''${env_path}" docker compose \
        --env-file "''${env_path}" \
        -f "''${compose_path}" \
        -p "''${SERVER_NAME}" \
        "$@"
    }

    init_dirs() {
      require_env
      mkdir -p "''${DIR_SERVER}"
      if [ -n "''${DIR_BACKUP_CORE:-}" ]; then
        mkdir -p "''${DIR_BACKUP_CORE}"
      fi
      if [ -n "''${DIR_BACKUP_WORLDS:-}" ]; then
        mkdir -p "''${DIR_BACKUP_WORLDS}"
      fi
    }

    host_init() {
      require_env
      require_command sudo
      require_command ufw

      sudo ufw default DENY
      case "''${PORT_SERVER_PROTO:-udp}" in
        udp)
          sudo ufw allow "''${PORT_SERVER}/udp"
          ;;
        tcp)
          sudo ufw allow "''${PORT_SERVER}/tcp"
          ;;
        both)
          sudo ufw allow "''${PORT_SERVER}/udp"
          sudo ufw allow "''${PORT_SERVER}/tcp"
          ;;
        *)
          echo "invalid PORT_SERVER_PROTO: ''${PORT_SERVER_PROTO}" >&2
          exit 1
          ;;
      esac
      sudo ufw allow "''${PORT_SSH}/tcp"
      sudo ufw --force enable
      sudo ufw reload
      sudo loginctl enable-linger "''${MY_USER_NAME}"
    }

    backup_local() {
      require_env
      : "''${DIR_BACKUP_CORE:?DIR_BACKUP_CORE must be set in ''${env_file}}"

      local timestamp
      timestamp=$(date '+%Y%m%d-%H%M%S')
      echo "TIMESTAMP=''${timestamp}"

      mkdir -p "''${DIR_BACKUP_CORE}"
      zip "''${DIR_BACKUP_CORE}/core.''${timestamp}.zip" \
        "''${DIR_SERVER}/allowlist.json" \
        "''${DIR_SERVER}/permissions.json" \
        "''${DIR_SERVER}/server.properties" \
        "''${DIR_SERVER}/valid_known_packs.json" \
        "''${env_path}"

      cd "''${DIR_BACKUP_CORE}"
      # shellcheck disable=SC2012
      ls -t | tail -n +9 | xargs -r rm
    }

    backup_cloud() {
      require_env
      : "''${DIR_BACKUP:?DIR_BACKUP must be set in ''${env_file}}"
      : "''${AWS_PROFILE:?AWS_PROFILE must be set in ''${env_file}}"
      : "''${S3_BACKUP_URI:?S3_BACKUP_URI must be set in ''${env_file}}"
      require_command aws

      aws s3 sync "''${DIR_BACKUP}" "''${S3_BACKUP_URI}" --profile="''${AWS_PROFILE}"
    }

    doctor() {
      local failed=0
      for command_name in bash docker systemctl sudo ufw zip; do
        if require_command "''${command_name}"; then
          echo "ok: ''${command_name}"
        else
          failed=1
        fi
      done

      if require_env; then
        echo "ok: ''${env_path}"
      else
        failed=1
      fi

      if require_compose_file; then
        echo "ok: ''${compose_path}"
      else
        failed=1
      fi

      if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
        echo "docker command exists, but the daemon is not reachable" >&2
        failed=1
      fi

      return "''${failed}"
    }

    command_name="''${1:-help}"
    if [ "$#" -gt 0 ]; then
      shift
    fi

    case "''${command_name}" in
      help | -h | --help)
        usage
        ;;
      doctor)
        doctor
        ;;
      host-init)
        host_init
        ;;
      init)
        init_dirs
        ;;
      up)
        init_dirs
        compose up -d --wait "$@"
        ;;
      down)
        compose down "$@"
        ;;
      stop)
        compose stop "$@"
        ;;
      restart)
        compose restart "$@"
        ;;
      update)
        init_dirs
        compose down
        compose pull
        compose up -d --wait "$@"
        ;;
      ps | status)
        compose ps "$@"
        ;;
      logs)
        compose logs --tail=100 -f "$@"
        ;;
      timers)
        require_command systemctl
        systemctl --user list-timers "''${server_id}-*"
        ;;
      backup-local)
        backup_local
        ;;
      backup-cloud)
        backup_cloud
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  '';

  minecraft-server = pkgs.writeShellApplication {
    name = "minecraft-server";
    runtimeInputs = [
      pkgs.awscli2
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.zip
    ];
    text = ''
      export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      ${minecraftServerScript}
    '';
  };

  mbs = pkgs.writeShellApplication {
    name = "mbs";
    runtimeInputs = [ minecraft-server ];
    text = ''
      export MINECRAFT_SERVER_ID=mbs
      export MINECRAFT_ENV_FILE="''${MINECRAFT_ENV_FILE:-.env.mbs}"
      export MINECRAFT_COMPOSE_FILE="''${MINECRAFT_COMPOSE_FILE:-compose.yml}"
      exec minecraft-server "$@"
    '';
  };

  mjs = pkgs.writeShellApplication {
    name = "mjs";
    runtimeInputs = [ minecraft-server ];
    text = ''
      export MINECRAFT_SERVER_ID=mjs
      export MINECRAFT_ENV_FILE="''${MINECRAFT_ENV_FILE:-.env.mjs}"
      export MINECRAFT_COMPOSE_FILE="''${MINECRAFT_COMPOSE_FILE:-compose.mjs.yml}"
      export PORT_SERVER_PROTO="''${PORT_SERVER_PROTO:-tcp}"
      exec minecraft-server "$@"
    '';
  };
in
{
  default = minecraft-server;
  inherit minecraft-server mbs mjs;
}
