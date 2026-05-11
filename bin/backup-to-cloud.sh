#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -o posix
export LC_ALL=C.UTF-8

cd "$(dirname "$0")"

# shellcheck disable=SC1091
. ../.env

aws s3 sync "${DIR_BACKUP}" "${S3_BACKUP_URI}" --profile="${AWS_PROFILE}"
