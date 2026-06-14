#!/usr/bin/env sh

# ============================================================================
# upload-to-cos.sh
# ============================================================================
#
# 作用：
#   把前端构建产物里的静态资源上传到腾讯云 COS。
#
# 当前默认上传内容：
#   dist/assets  ->  cos://<BucketName>/assets/
#
# 常见使用场景：
#   1. 前端执行 COS 专用构建，例如 npm run build:cos
#   2. 构建产物生成到 dist
#   3. 本脚本把 dist/assets 同步到 COS
#   4. 页面中的静态资源可以通过 CDN/COS 访问
#
# 典型执行入口：
#   package.json 里通常会配置类似命令：
#
#     npm run upload:cos
#
#   Jenkinsfile 中也可以通过下面这种方式执行：
#
#     npm run upload:cos
#
# 配置来源：
#   这个脚本支持两种配置来源：
#
#   1. 环境变量
#      例如：
#        COS_SECRET_ID=xxx COS_SECRET_KEY=yyy ./scripts/upload-to-cos.sh
#
#   2. package.json 的 cos 字段
#      例如：
#        {
#          "cos": {
#            "Mode": "SecretKey",
#            "BucketName": "ap-ives-1304933815",
#            "BucketEndpoint": "cos.ap-guangzhou.myqcloud.com",
#            "AssetPrefix": "assets",
#            "SourceDir": "dist/assets"
#          }
#        }
#
# 配置优先级：
#   环境变量优先级更高。
#   如果环境变量没有传入，脚本才会去 package.json 的 cos 字段里读取。
#
# 密钥注意事项：
#   SecretID / SecretKey 属于敏感信息，不建议提交到 Git 仓库。
#   更推荐在 Jenkins 凭据里保存密钥，然后通过环境变量传给脚本。
#
# 依赖：
#   服务器或 Jenkins 节点上需要提前安装 coscli 命令。
#   本脚本最终通过 coscli sync 执行上传。
#
# ============================================================================

# 开启较严格的 POSIX sh 执行模式：
#
#   -e：
#     任何命令返回非 0 状态码时，脚本立即退出。
#
#   -u：
#     使用未定义变量时报错并退出。
#
# 注意：
#   这里使用的是 /usr/bin/env sh，不是 bash。
#   所以没有使用 bash 才支持的 pipefail。
set -eu

# ----------------------------------------------------------------------------
# 基础路径
# ----------------------------------------------------------------------------

# 当前脚本所在目录。
# 如果脚本路径是：
#   scripts/upload-to-cos.sh
#
# 那么 SCRIPT_DIR 就是项目根目录下的 scripts 目录。
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# 项目根目录。
# 通过脚本目录 scripts 再向上一级得到。
ROOT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

# package.json 路径。
#
# 默认读取项目根目录下的 package.json。
# 也可以通过 COS_PACKAGE_FILE 覆盖，用于特殊测试或多 package 场景。
#
# 示例：
#   COS_PACKAGE_FILE=/tmp/package.json ./scripts/upload-to-cos.sh
PACKAGE_FILE="${COS_PACKAGE_FILE:-${ROOT_DIR}/package.json}"

# package.json 必须存在。
# 因为脚本会从 package.json 的 cos 字段读取默认配置。
if [ ! -f "$PACKAGE_FILE" ]; then
  echo "ERROR: package.json not found: $PACKAGE_FILE"
  exit 1
fi

# ----------------------------------------------------------------------------
# 从 package.json 读取 cos 配置
# ----------------------------------------------------------------------------

# pkg_cos 用来读取 package.json 中 cos 字段的某个配置项。
#
# 为什么这里用 node：
#   JSON 解析不适合用纯 shell 处理，容易遇到转义、空格、换行等问题。
#   当前项目本身是前端项目，Jenkins 构建阶段已经具备 node 环境，
#   所以直接用 node 读取 package.json 更可靠。
#
# 使用方式：
#   pkg_cos BucketName
#   pkg_cos BucketEndpoint
#   pkg_cos SourceDir
#
# 兼容别名：
#   为了兼容不同命名习惯，同一个字段支持多种写法。
#   例如 SecretID 同时支持：
#     SecretID
#     SecretId
#     secretID
#     secretId
#     secret_id
pkg_cos() {
  node -e '
const fs = require("fs")
const file = process.argv[1]
const key = process.argv[2]

// 读取 package.json，然后取里面的 cos 字段。
// 如果 package.json 中没有 cos 字段，就使用空对象，避免脚本直接崩溃。
const cos = JSON.parse(fs.readFileSync(file, "utf8")).cos || {}

// 每个标准配置项允许多个别名。
// 这样 package.json 里使用驼峰、小写、下划线等命名时都能兼容。
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

// 按别名顺序查找配置值。
// 找到第一个非 undefined 且非 null 的值后输出，然后正常退出。
// 如果没有找到，node 不输出任何内容，shell 侧会拿到空字符串。
for (const name of keys[key] || [key]) {
  if (cos[name] !== undefined && cos[name] !== null) {
    process.stdout.write(String(cos[name]))
    process.exit(0)
  }
}
' "$PACKAGE_FILE" "$1"
}

# ----------------------------------------------------------------------------
# 读取配置：环境变量优先，package.json 兜底
# ----------------------------------------------------------------------------

# COS_MODE：
#   上传认证模式。
#   当前脚本只支持 SecretKey 模式。
#   后面会强制校验，如果不是 SecretKey 就退出。
COS_MODE="${COS_MODE:-$(pkg_cos Mode)}"

# COS_SECRET_ID：
#   腾讯云 API 密钥 ID。
#   推荐通过 Jenkins 凭据注入环境变量，不建议写进 package.json。
COS_SECRET_ID="${COS_SECRET_ID:-$(pkg_cos SecretID)}"

# COS_SECRET_KEY：
#   腾讯云 API 密钥 Key。
#   推荐通过 Jenkins 凭据注入环境变量，不建议写进 package.json。
COS_SECRET_KEY="${COS_SECRET_KEY:-$(pkg_cos SecretKey)}"

# COS_SESSION_TOKEN：
#   临时密钥的 token。
#   如果使用腾讯云 STS 临时密钥，就需要传这个值。
#   如果使用长期 SecretID / SecretKey，则通常为空。
COS_SESSION_TOKEN="${COS_SESSION_TOKEN:-$(pkg_cos SessionToken)}"

# COS_BUCKET_NAME：
#   COS 存储桶名称。
#   这里需要填写完整 bucket 名称，通常包含 appid。
#   示例：
#     ap-ives-1304933815
COS_BUCKET_NAME="${COS_BUCKET_NAME:-$(pkg_cos BucketName)}"

# COS_BUCKET_ENDPOINT：
#   COS 存储桶 endpoint。
#   endpoint 需要和 bucket 所在地域一致。
#   示例：
#     cos.ap-guangzhou.myqcloud.com
COS_BUCKET_ENDPOINT="${COS_BUCKET_ENDPOINT:-$(pkg_cos BucketEndpoint)}"

# COS_BUCKET_ALIAS：
#   存储桶别名。
#   当前脚本没有直接把它传给 coscli sync，只是保留配置读取能力。
#   如果没有配置，后面默认等于 COS_BUCKET_NAME。
COS_BUCKET_ALIAS="${COS_BUCKET_ALIAS:-$(pkg_cos BucketAlias)}"

# COS_ASSET_PREFIX：
#   上传到 COS 里的目标路径前缀。
#
# 示例：
#   COS_ASSET_PREFIX=assets
#   则上传目标是：
#     cos://<BucketName>/assets/
#
# 如果设置为空字符串，则上传到 bucket 根目录：
#   cos://<BucketName>/
COS_ASSET_PREFIX="${COS_ASSET_PREFIX:-$(pkg_cos AssetPrefix)}"

# COS_SOURCE_DIR：
#   本地要上传的源目录。
#
# 默认是 dist/assets，表示只上传前端构建后的静态资源目录。
# 如果想上传整个 dist，可以设置：
#   COS_SOURCE_DIR=dist
COS_SOURCE_DIR="${COS_SOURCE_DIR:-$(pkg_cos SourceDir)}"

# ----------------------------------------------------------------------------
# 默认值
# ----------------------------------------------------------------------------

# 如果外部和 package.json 都没有配置 Mode，默认使用 SecretKey 模式。
COS_MODE="${COS_MODE:-SecretKey}"

# 如果没有单独配置 BucketAlias，默认使用 BucketName。
COS_BUCKET_ALIAS="${COS_BUCKET_ALIAS:-$COS_BUCKET_NAME}"

# 如果没有配置 COS 目标前缀，默认上传到 assets 目录下。
COS_ASSET_PREFIX="${COS_ASSET_PREFIX:-assets}"

# 如果没有配置本地源目录，默认上传 dist/assets。
COS_SOURCE_DIR="${COS_SOURCE_DIR:-dist/assets}"

# ----------------------------------------------------------------------------
# 配置校验
# ----------------------------------------------------------------------------

# 当前脚本只实现了 SecretKey 模式。
# 如果后续要支持其他模式，需要在这里扩展对应认证逻辑。
if [ "$COS_MODE" != "SecretKey" ]; then
  echo "ERROR: unsupported COS mode: $COS_MODE"
  echo "Only SecretKey mode is supported by this upload script."
  exit 1
fi

# SecretID 不能为空。
# 缺少它时，coscli 无法完成认证。
if [ -z "$COS_SECRET_ID" ]; then
  echo "ERROR: cos.SecretID is required in $PACKAGE_FILE"
  exit 1
fi

# SecretKey 不能为空。
# 缺少它时，coscli 无法完成认证。
if [ -z "$COS_SECRET_KEY" ]; then
  echo "ERROR: cos.SecretKey is required in $PACKAGE_FILE"
  exit 1
fi

# BucketName 不能为空。
# 它决定上传到哪个 COS 存储桶。
if [ -z "$COS_BUCKET_NAME" ]; then
  echo "ERROR: cos.BucketName is required in $PACKAGE_FILE"
  exit 1
fi

# BucketEndpoint 不能为空。
# 它决定请求哪个地域的 COS 服务。
if [ -z "$COS_BUCKET_ENDPOINT" ]; then
  echo "ERROR: cos.BucketEndpoint is required in $PACKAGE_FILE"
  exit 1
fi

# 检查 coscli 是否已安装。
#
# command -v coscli：
#   用来判断当前 PATH 中是否能找到 coscli 命令。
#
# 如果 Jenkins 节点没有安装 coscli，这里会直接失败。
if ! command -v coscli >/dev/null 2>&1; then
  echo "ERROR: coscli command not found."
  echo "Install COSCLI before uploading."
  exit 1
fi

# ----------------------------------------------------------------------------
# 计算本地源目录
# ----------------------------------------------------------------------------

# COS_SOURCE_DIR 支持绝对路径和相对路径。
#
# 如果以 / 开头：
#   认为它已经是绝对路径，直接使用。
#
# 如果不是以 / 开头：
#   认为它是相对于项目根目录的路径。
#
# 示例：
#   COS_SOURCE_DIR=dist/assets
#   SOURCE_PATH=<项目根目录>/dist/assets
#
#   COS_SOURCE_DIR=/tmp/assets
#   SOURCE_PATH=/tmp/assets
case "$COS_SOURCE_DIR" in
  /*) SOURCE_PATH="$COS_SOURCE_DIR" ;;
  *) SOURCE_PATH="${ROOT_DIR}/${COS_SOURCE_DIR}" ;;
esac

# 去掉本地源目录末尾的 /。
# 这样后面拼接 "${SOURCE_PATH}/" 时路径格式更统一。
SOURCE_PATH="${SOURCE_PATH%/}"

# 去掉 COS 目标前缀开头和结尾的 /。
#
# 例如：
#   /assets/  ->  assets
#   assets/   ->  assets
#   /assets   ->  assets
#
# 这样后面拼接 cos://bucket/prefix/ 时不会出现重复斜杠。
COS_ASSET_PREFIX="${COS_ASSET_PREFIX#/}"
COS_ASSET_PREFIX="${COS_ASSET_PREFIX%/}"

# 检查本地源目录是否存在。
#
# 如果 dist/assets 不存在，通常说明：
#   1. 还没有执行构建
#   2. 构建命令失败了
#   3. COS_SOURCE_DIR 配错了
if [ ! -d "$SOURCE_PATH" ]; then
  echo "ERROR: source directory not found: $SOURCE_PATH"
  echo "Run npm run build:cos before uploading."
  exit 1
fi

# 检查源目录里是否至少有一个文件。
#
# find "$SOURCE_PATH" -type f -print -quit：
#   找到第一个普通文件后立即输出并退出。
#
# 如果输出为空，说明目录存在但里面没有可上传文件。
if [ -z "$(find "$SOURCE_PATH" -type f -print -quit)" ]; then
  echo "ERROR: source directory is empty: $SOURCE_PATH"
  exit 1
fi

# ----------------------------------------------------------------------------
# 计算 COS 上传目标
# ----------------------------------------------------------------------------

# 根据 COS_ASSET_PREFIX 决定上传到 bucket 根目录还是某个子目录。
#
# COS_ASSET_PREFIX 非空：
#   cos://<BucketName>/<AssetPrefix>/
#
# COS_ASSET_PREFIX 为空：
#   cos://<BucketName>/
if [ -n "$COS_ASSET_PREFIX" ]; then
  COS_TARGET="cos://${COS_BUCKET_NAME}/${COS_ASSET_PREFIX}/"
else
  COS_TARGET="cos://${COS_BUCKET_NAME}/"
fi

# 打印上传信息。
# 这些日志会出现在 Jenkins 控制台里，方便确认：
#   - 本地上传源目录
#   - COS 目标路径
#   - COS endpoint
#
# 注意：
#   这里不会打印 SecretID / SecretKey，避免密钥泄漏到日志。
echo "Uploading assets to COS"
echo "Source: ${SOURCE_PATH}/"
echo "Target: ${COS_TARGET}"
echo "Endpoint: ${COS_BUCKET_ENDPOINT}"

# COS_DRY_RUN 是试运行开关。
#
# 如果设置：
#   COS_DRY_RUN=true
#
# 脚本只打印源路径和目标路径，不真正执行 coscli sync。
# 这适合调试配置是否正确。
if [ "${COS_DRY_RUN:-false}" = "true" ]; then
  echo "Dry run enabled, skip coscli sync."
  exit 0
fi

# ----------------------------------------------------------------------------
# 执行上传
# ----------------------------------------------------------------------------

# 临时关闭 set -e。
#
# 原因：
#   coscli sync 失败时，我们不想让脚本立即退出；
#   而是希望先拿到失败状态码 status，
#   然后输出更友好的排查提示。
set +e

# 如果配置了 COS_SESSION_TOKEN，说明使用的是临时密钥。
# 此时 coscli sync 需要额外传入 --token。
if [ -n "$COS_SESSION_TOKEN" ]; then
  coscli sync "${SOURCE_PATH}/" "$COS_TARGET" -r --init-skip \
    -i "$COS_SECRET_ID" \
    -k "$COS_SECRET_KEY" \
    --token "$COS_SESSION_TOKEN" \
    -e "$COS_BUCKET_ENDPOINT"
  status=$?
else
  # 没有 COS_SESSION_TOKEN 时，按普通 SecretID / SecretKey 方式上传。
  coscli sync "${SOURCE_PATH}/" "$COS_TARGET" -r --init-skip \
    -i "$COS_SECRET_ID" \
    -k "$COS_SECRET_KEY" \
    -e "$COS_BUCKET_ENDPOINT"
  status=$?
fi

# 重新开启 set -e，恢复脚本的严格失败行为。
set -e

# 如果 coscli sync 返回非 0，说明上传失败。
#
# 这里补充常见 403 / 权限问题排查方向：
#   1. 密钥是不是属于正确账号
#   2. bucket 名称和 endpoint 是否匹配
#   3. 密钥是否拥有上传所需权限
if [ "$status" -ne 0 ]; then
  echo ""
  echo "COS upload failed. If COS returned 403 on HEAD Bucket, check that:"
  echo "- package.json cos.SecretID and cos.SecretKey belong to the account that can access this bucket."
  echo "- The bucket name is ${COS_BUCKET_NAME} and endpoint is ${COS_BUCKET_ENDPOINT}."
  echo "- The key has COS upload permissions, including HeadBucket, GetBucket, HeadObject,"
  echo "  InitiateMultipartUpload, UploadPart, CompleteMultipartUpload, ListMultipartUploads, and ListParts."
  exit "$status"
fi
