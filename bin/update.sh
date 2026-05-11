#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -o posix
export LC_ALL=C.UTF-8

cd "$(dirname "$0")"

# shellcheck disable=SC1091
. ../.env

echo "update the server"
cd "${DIR_REPO}"
docker compose down
docker compose pull
docker compose up -d --wait
