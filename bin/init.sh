#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -o posix
export LC_ALL=C.UTF-8

cd "$(dirname "$0")"

# shellcheck disable=SC1091
. ../.env

: "${MY_USER_NAME:?MY_USER_NAME must be set in .env}"
: "${PORT_SERVER:?PORT_SERVER must be set in .env}"
: "${PORT_SSH:?PORT_SSH must be set in .env}"
: "${DIR_REPO:?DIR_REPO must be set in .env}"
: "${DIR_SERVER:?DIR_SERVER must be set in .env}"
: "${DIR_BACKUP_CORE:?DIR_BACKUP_CORE must be set in .env}"
: "${DIR_BACKUP_WORLDS:?DIR_BACKUP_WORLDS must be set in .env}"

# https://qiita.com/siida36/items/be21d361cf80d664859c
sudo ufw default DENY
sudo ufw allow "${PORT_SERVER}/udp"
sudo ufw allow "${PORT_SSH}/tcp"
sudo ufw --force enable
sudo ufw reload

mkdir -p "${DIR_SERVER}"
mkdir -p "${DIR_BACKUP_CORE}"
mkdir -p "${DIR_BACKUP_WORLDS}"

# https://zenn.dev/hi_ka_ru/articles/d01bf1a91bade0
# https://takuya-1st.hatenablog.jp/entry/2019/08/09/004829
systemd_user_dir="${HOME}/.config/systemd/user"
mkdir -p "${systemd_user_dir}"

cat >"${systemd_user_dir}/mbs-backup-to-local.service" <<EOF
[Unit]
Description=Minecraft Bedrock Server Backup to Local

[Service]
Type=oneshot
WorkingDirectory=${DIR_REPO}
ExecStart=${DIR_REPO}/bin/backup-to-local.sh
EOF

cat >"${systemd_user_dir}/mbs-backup-to-cloud.service" <<EOF
[Unit]
Description=Minecraft Bedrock Server Backup to Cloud
After=mbs-backup-to-local.service
Wants=mbs-backup-to-local.service

[Service]
Type=oneshot
WorkingDirectory=${DIR_REPO}
ExecStart=${DIR_REPO}/bin/backup-to-cloud.sh
EOF

cat >"${systemd_user_dir}/mbs-backup-to-cloud.timer" <<'EOF'
[Unit]
Description=Minecraft Bedrock Server Backup to Cloud Timer

[Timer]
OnCalendar=Sat 5:00:00

[Install]
WantedBy=timers.target
EOF

cat >"${systemd_user_dir}/mbs-update.service" <<EOF
[Unit]
Description=Minecraft Bedrock Server Update

[Service]
Type=oneshot
WorkingDirectory=${DIR_REPO}
ExecStart=${DIR_REPO}/bin/update.sh
EOF

cat >"${systemd_user_dir}/mbs-update.timer" <<'EOF'
[Unit]
Description=Minecraft Bedrock Server Update Timer

[Timer]
OnCalendar=Sat 6:00:00

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now mbs-backup-to-cloud.timer
systemctl --user enable --now mbs-update.timer

# https://qiita.com/k0kubun/items/3c94473506e0e370a227
sudo loginctl enable-linger "${MY_USER_NAME}"
