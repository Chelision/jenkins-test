#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
PACKAGE_FILE="${COS_PACKAGE_FILE:-${ROOT_DIR}/package.json}"

if [ ! -f "$PACKAGE_FILE" ]; then
  echo "ERROR: package.json not found: $PACKAGE_FILE"
  exit 1
fi

pkg_cos() {
  node -e '
const fs = require("fs")
const file = process.argv[1]
const key = process.argv[2]
const cos = JSON.parse(fs.readFileSync(file, "utf8")).cos || {}
const keys = {
  Mode: ["Mode", "mode"],
  SecretID: ["SecretID", "SecretId", "secretID", "secretId", "secret_id"],
  SecretKey: ["SecretKey", "secretKey", "secret_key"],
  SessionToken: ["SessionToken", "sessionToken", "session_token"],
  BucketName: ["BucketName", "bucketName", "bucket"],
  BucketEndpoint: ["BucketEndpoint", "bucketEndpoint", "endpoint"],
  BucketAlias: ["BucketAlias", "bucketAlias", "alias"],
  AssetPrefix: ["AssetPrefix", "assetPrefix", "prefix"],
  SourceDir: ["SourceDir", "sourceDir", "source"]
}
for (const name of keys[key] || [key]) {
  if (cos[name] !== undefined && cos[name] !== null) {
    process.stdout.write(String(cos[name]))
    process.exit(0)
  }
}
' "$PACKAGE_FILE" "$1"
}

COS_MODE="${COS_MODE:-$(pkg_cos Mode)}"
COS_SECRET_ID="${COS_SECRET_ID:-$(pkg_cos SecretID)}"
COS_SECRET_KEY="${COS_SECRET_KEY:-$(pkg_cos SecretKey)}"
COS_SESSION_TOKEN="${COS_SESSION_TOKEN:-$(pkg_cos SessionToken)}"
COS_BUCKET_NAME="${COS_BUCKET_NAME:-$(pkg_cos BucketName)}"
COS_BUCKET_ENDPOINT="${COS_BUCKET_ENDPOINT:-$(pkg_cos BucketEndpoint)}"
COS_BUCKET_ALIAS="${COS_BUCKET_ALIAS:-$(pkg_cos BucketAlias)}"
COS_ASSET_PREFIX="${COS_ASSET_PREFIX:-$(pkg_cos AssetPrefix)}"
COS_SOURCE_DIR="${COS_SOURCE_DIR:-$(pkg_cos SourceDir)}"

COS_MODE="${COS_MODE:-SecretKey}"
COS_BUCKET_ALIAS="${COS_BUCKET_ALIAS:-$COS_BUCKET_NAME}"
COS_ASSET_PREFIX="${COS_ASSET_PREFIX:-assets}"
COS_SOURCE_DIR="${COS_SOURCE_DIR:-dist/assets}"

if [ "$COS_MODE" != "SecretKey" ]; then
  echo "ERROR: unsupported COS mode: $COS_MODE"
  echo "Only SecretKey mode is supported by this upload script."
  exit 1
fi

if [ -z "$COS_SECRET_ID" ]; then
  echo "ERROR: cos.SecretID is required in $PACKAGE_FILE"
  exit 1
fi

if [ -z "$COS_SECRET_KEY" ]; then
  echo "ERROR: cos.SecretKey is required in $PACKAGE_FILE"
  exit 1
fi

if [ -z "$COS_BUCKET_NAME" ]; then
  echo "ERROR: cos.BucketName is required in $PACKAGE_FILE"
  exit 1
fi

if [ -z "$COS_BUCKET_ENDPOINT" ]; then
  echo "ERROR: cos.BucketEndpoint is required in $PACKAGE_FILE"
  exit 1
fi

if ! command -v coscli >/dev/null 2>&1; then
  echo "ERROR: coscli command not found."
  echo "Install COSCLI before uploading."
  exit 1
fi

case "$COS_SOURCE_DIR" in
  /*) SOURCE_PATH="$COS_SOURCE_DIR" ;;
  *) SOURCE_PATH="${ROOT_DIR}/${COS_SOURCE_DIR}" ;;
esac

SOURCE_PATH="${SOURCE_PATH%/}"
COS_ASSET_PREFIX="${COS_ASSET_PREFIX#/}"
COS_ASSET_PREFIX="${COS_ASSET_PREFIX%/}"

if [ ! -d "$SOURCE_PATH" ]; then
  echo "ERROR: source directory not found: $SOURCE_PATH"
  echo "Run npm run build:cos before uploading."
  exit 1
fi

if [ -z "$(find "$SOURCE_PATH" -type f -print -quit)" ]; then
  echo "ERROR: source directory is empty: $SOURCE_PATH"
  exit 1
fi

if [ -n "$COS_ASSET_PREFIX" ]; then
  COS_TARGET="cos://${COS_BUCKET_NAME}/${COS_ASSET_PREFIX}/"
else
  COS_TARGET="cos://${COS_BUCKET_NAME}/"
fi

echo "Uploading assets to COS"
echo "Source: ${SOURCE_PATH}/"
echo "Target: ${COS_TARGET}"
echo "Endpoint: ${COS_BUCKET_ENDPOINT}"

if [ "${COS_DRY_RUN:-false}" = "true" ]; then
  echo "Dry run enabled, skip coscli sync."
  exit 0
fi

set +e
if [ -n "$COS_SESSION_TOKEN" ]; then
  coscli sync "${SOURCE_PATH}/" "$COS_TARGET" -r --init-skip \
    -i "$COS_SECRET_ID" \
    -k "$COS_SECRET_KEY" \
    --token "$COS_SESSION_TOKEN" \
    -e "$COS_BUCKET_ENDPOINT"
  status=$?
else
  coscli sync "${SOURCE_PATH}/" "$COS_TARGET" -r --init-skip \
    -i "$COS_SECRET_ID" \
    -k "$COS_SECRET_KEY" \
    -e "$COS_BUCKET_ENDPOINT"
  status=$?
fi
set -e

if [ "$status" -ne 0 ]; then
  echo ""
  echo "COS upload failed. If COS returned 403 on HEAD Bucket, check that:"
  echo "- package.json cos.SecretID and cos.SecretKey belong to the account that can access this bucket."
  echo "- The bucket name is ${COS_BUCKET_NAME} and endpoint is ${COS_BUCKET_ENDPOINT}."
  echo "- The key has COS upload permissions, including HeadBucket, GetBucket, HeadObject,"
  echo "  InitiateMultipartUpload, UploadPart, CompleteMultipartUpload, ListMultipartUploads, and ListParts."
  exit "$status"
fi
