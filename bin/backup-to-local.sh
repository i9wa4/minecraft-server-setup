#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -o posix
export LC_ALL=C.UTF-8

cd "$(dirname "$0")"

# shellcheck disable=SC1091
. ../.env

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
echo TIMESTAMP="${TIMESTAMP}"

echo "back up core data"
zip "${DIR_BACKUP_CORE}"/core."${TIMESTAMP}".zip \
  "${DIR_SERVER}"/allowlist.json \
  "${DIR_SERVER}"/permissions.json \
  "${DIR_SERVER}"/server.properties \
  "${DIR_SERVER}"/valid_known_packs.json \
  "${DIR_REPO}"/.env

echo "remove old core backups"
cd "${DIR_BACKUP_CORE}"
# shellcheck disable=SC2012
ls -t | tail -n +9 | xargs -r rm

# NOTE: use kaiede/minecraft-bedrock-backup instead
# echo "back up worlds"
# cd "${DIR_REPO}"
# docker compose stop
# zip -r "${DIR_BACKUP_WORLDS}"/mbs-worlds-"${TIMESTAMP}".zip \
#   "${DIR_SERVER}"/worlds
# docker compose up -d --wait

# echo "remove old worlds backups"
# cd "${DIR_BACKUP_WORLDS}"
# ls -t | tail -n +29 | xargs -r rm
