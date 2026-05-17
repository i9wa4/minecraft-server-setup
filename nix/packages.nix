{
  pkgs,
  ...
}:
let
  mcServerScript = ''
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
      host-setup    Install Ubuntu host packages using Docker's official apt repo
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
      backup-sync   Sync backup data to a remote rsync target when enabled
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

    host_setup() {
      require_env
      require_command sudo
      require_command apt-get
      require_command curl
      require_command dpkg
      require_command systemctl

      if [ ! -r /etc/os-release ]; then
        echo "missing /etc/os-release; host-setup currently supports Ubuntu only" >&2
        exit 1
      fi

      # shellcheck disable=SC1091
      . /etc/os-release
      if [ "''${ID:-}" != "ubuntu" ]; then
        echo "unsupported OS: ''${ID:-unknown}; host-setup follows Docker's official Ubuntu install docs" >&2
        exit 1
      fi

      local codename arch
      codename="''${UBUNTU_CODENAME:-''${VERSION_CODENAME:-}}"
      arch="$(dpkg --print-architecture)"
      if [ -z "''${codename}" ]; then
        echo "cannot determine Ubuntu codename from /etc/os-release" >&2
        exit 1
      fi

      local conflicts=()
      while IFS= read -r package_name; do
        conflicts+=("''${package_name}")
      done < <(
        dpkg --get-selections \
          docker.io \
          docker-compose \
          docker-compose-v2 \
          docker-doc \
          podman-docker \
          containerd \
          runc 2>/dev/null | awk '{print $1}'
      )

      if [ "''${#conflicts[@]}" -gt 0 ]; then
        sudo apt-get remove -y "''${conflicts[@]}"
      fi

      sudo apt-get update
      sudo apt-get install -y ca-certificates curl openssh-server ufw
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
        sudo tee /etc/apt/keyrings/docker.asc >/dev/null
      sudo chmod a+r /etc/apt/keyrings/docker.asc

      sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
    Types: deb
    URIs: https://download.docker.com/linux/ubuntu
    Suites: ''${codename}
    Components: stable
    Architectures: ''${arch}
    Signed-By: /etc/apt/keyrings/docker.asc
    EOF

      sudo apt-get update
      sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

      sudo systemctl enable --now ssh
      sudo systemctl enable --now docker
      sudo systemctl enable containerd.service

      if ! getent group docker >/dev/null 2>&1; then
        sudo groupadd docker
      fi
      sudo usermod -aG docker "''${MY_USER_NAME}"

      echo "host setup complete"
      echo "log out and log back in so docker group membership is re-evaluated"
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
      local files=()
      local candidate
      for candidate in \
        "''${DIR_SERVER}/allowlist.json" \
        "''${DIR_SERVER}/permissions.json" \
        "''${DIR_SERVER}/valid_known_packs.json" \
        "''${DIR_SERVER}/whitelist.json" \
        "''${DIR_SERVER}/ops.json" \
        "''${DIR_SERVER}/banned-ips.json" \
        "''${DIR_SERVER}/banned-players.json" \
        "''${DIR_SERVER}/usercache.json" \
        "''${DIR_SERVER}/eula.txt" \
        "''${DIR_SERVER}/server.properties" \
        "''${env_path}"; do
        if [ -e "''${candidate}" ]; then
          files+=("''${candidate}")
        fi
      done

      if [ "''${#files[@]}" -eq 0 ]; then
        echo "no core config files found to back up" >&2
        exit 1
      fi

      zip "''${DIR_BACKUP_CORE}/core.''${timestamp}.zip" "''${files[@]}"

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

    remote_sync_enabled() {
      case "''${BACKUP_REMOTE_SYNC_ENABLE:-false}" in
        true | TRUE | True | 1 | yes | YES | on | ON)
          return 0
          ;;
        false | FALSE | False | 0 | no | NO | off | OFF | "")
          return 1
          ;;
        *)
          echo "invalid BACKUP_REMOTE_SYNC_ENABLE: ''${BACKUP_REMOTE_SYNC_ENABLE}" >&2
          return 2
          ;;
      esac
    }

    require_remote_sync_target() {
      if [ -z "''${BACKUP_REMOTE_SYNC_TARGET:-}" ]; then
        echo "BACKUP_REMOTE_SYNC_TARGET must be set when BACKUP_REMOTE_SYNC_ENABLE=true" >&2
        return 1
      fi

      case "''${BACKUP_REMOTE_SYNC_TARGET}" in
        *:*)
          ;;
        *)
          echo "BACKUP_REMOTE_SYNC_TARGET must be an rsync remote target with an explicit path, such as user@host:/path" >&2
          return 1
          ;;
      esac

      case "''${BACKUP_REMOTE_SYNC_TARGET}" in
        *:)
          echo "BACKUP_REMOTE_SYNC_TARGET must include a destination path, not a bare host:" >&2
          return 1
          ;;
      esac
    }

    backup_sync() {
      require_env

      if remote_sync_enabled; then
        :
      else
        case "$?" in
          1)
            echo "remote backup sync disabled by BACKUP_REMOTE_SYNC_ENABLE=''${BACKUP_REMOTE_SYNC_ENABLE:-false}"
            return 0
            ;;
          *)
            exit 1
            ;;
        esac
      fi

      : "''${DIR_BACKUP:?DIR_BACKUP must be set in ''${env_file}}"
      require_remote_sync_target || exit 1
      BACKUP_REMOTE_SYNC_RSH="''${BACKUP_REMOTE_SYNC_RSH:-ssh}"

      if [ ! -d "''${DIR_BACKUP}" ]; then
        echo "missing backup directory: ''${DIR_BACKUP}" >&2
        exit 1
      fi

      require_command rsync
      rsync -a \
        --numeric-ids \
        --no-owner \
        --no-group \
        --partial \
        --partial-dir=.rsync-partial \
        --info=stats1 \
        --rsh="''${BACKUP_REMOTE_SYNC_RSH}" \
        "''${DIR_BACKUP}/" \
        "''${BACKUP_REMOTE_SYNC_TARGET}"
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
        if remote_sync_enabled; then
          if require_command rsync; then
            echo "ok: rsync"
          else
            failed=1
          fi

          if require_remote_sync_target; then
            echo "ok: BACKUP_REMOTE_SYNC_TARGET"
          else
            failed=1
          fi
        else
          case "$?" in
            1)
              echo "ok: remote backup sync disabled"
              ;;
            *)
              failed=1
              ;;
          esac
        fi
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
      host-setup)
        host_setup
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
      backup-sync)
        backup_sync
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

  mc-server = pkgs.writeShellApplication {
    name = "mc-server";
    runtimeInputs = [
      pkgs.awscli2
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.rsync
      pkgs.zip
    ];
    text = ''
      export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      ${mcServerScript}
    '';
  };

  mbs = pkgs.writeShellApplication {
    name = "mbs";
    runtimeInputs = [ mc-server ];
    text = ''
      export MINECRAFT_SERVER_ID=mbs
      export MINECRAFT_ENV_FILE="''${MINECRAFT_ENV_FILE:-.env.mbs}"
      export MINECRAFT_COMPOSE_FILE="''${MINECRAFT_COMPOSE_FILE:-compose.mbs.yml}"
      exec mc-server "$@"
    '';
  };

  mjs = pkgs.writeShellApplication {
    name = "mjs";
    runtimeInputs = [ mc-server ];
    text = ''
      export MINECRAFT_SERVER_ID=mjs
      export MINECRAFT_ENV_FILE="''${MINECRAFT_ENV_FILE:-.env.mjs}"
      export MINECRAFT_COMPOSE_FILE="''${MINECRAFT_COMPOSE_FILE:-compose.mjs.yml}"
      export PORT_SERVER_PROTO="''${PORT_SERVER_PROTO:-tcp}"
      exec mc-server "$@"
    '';
  };
in
{
  default = mc-server;
  inherit mc-server mbs mjs;
}
