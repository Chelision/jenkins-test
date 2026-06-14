#!/usr/bin/env bash

# ============================================================================
# deploy-nginx-static.sh
# ============================================================================
#
# 作用：
#   把前端构建产物 dist 发布到 Nginx 的静态资源目录，并让 Nginx 加载最新版本。
#
# 典型执行入口：
#   Jenkinsfile 中的 “Deploy Static Files to Nginx” 阶段会执行类似下面的命令：
#
#     sudo SITE_NAME="${SITE_NAME}" \
#          PROJECT_KEY="${PROJECT_KEY}" \
#          RELEASE_ID="${PROJECT_KEY}-${BUILD_NUMBER}" \
#          ./scripts/deploy-nginx-static.sh
#
# 为什么需要 sudo：
#   这个脚本默认会写入两个系统目录：
#
#     1. /var/www
#        用来存放静态网站文件，例如：
#          /var/www/www.mumup.asia/releases/jenkins-test-pro-123
#          /var/www/www.mumup.asia/current
#
#     2. /etc/nginx/conf.d
#        用来存放 Nginx 站点配置，例如：
#          /etc/nginx/conf.d/www.mumup.asia.conf
#
#   普通 Jenkins 用户通常没有这些目录的写权限，所以 Jenkinsfile 里使用 sudo。
#
# 发布目录结构：
#   假设：
#     SITE_NAME=www.mumup.asia
#     PROJECT_KEY=jenkins-test-pro
#     BUILD_NUMBER=123
#
#   最终会生成类似结构：
#
#     /var/www/www.mumup.asia/
#       ├── releases/
#       │   └── jenkins-test-pro-123/
#       │       ├── index.html
#       │       └── assets/
#       └── current -> /var/www/www.mumup.asia/releases/jenkins-test-pro-123
#
#   Nginx 配置里通常会把站点 root 指向 current：
#
#     root /var/www/www.mumup.asia/current;
#
#   这样每次发布只需要切换 current 软链接，就能完成版本切换。
#
# 回滚思路：
#   因为每次构建都会放在 releases 下的独立目录，所以如果新版本有问题，
#   可以把 current 重新指回旧 release，然后 reload nginx。
#
# 注意：
#   这个脚本只负责“发布已经构建好的 dist”。
#   它不会执行 npm install，也不会执行 npm run build。
#   所以运行它之前，必须已经完成前端构建，并且项目根目录下存在 dist。
#
# ============================================================================

# 开启更严格的 Bash 执行模式：
#
#   -e：
#     任何命令返回非 0 状态码时，脚本立即退出。
#     这样可以避免前面步骤失败后，后面继续执行导致线上状态不可控。
#
#   -u：
#     使用未定义变量时报错并退出。
#     这样可以避免变量拼错后变成空字符串，误写入错误目录。
#
#   -o pipefail：
#     管道命令中任意一个子命令失败，整个管道都视为失败。
#     虽然当前脚本没有复杂管道，但这是发布脚本里常见的安全习惯。
set -euo pipefail

# ----------------------------------------------------------------------------
# 参数区：可以通过环境变量覆盖默认值
# ----------------------------------------------------------------------------
#
# 写法说明：
#
#   SITE_NAME="${SITE_NAME:-www.mumup.asia}"
#
# 含义是：
#   如果外部已经传入 SITE_NAME，就使用外部传入的值；
#   如果没有传入，就使用默认值 www.mumup.asia。
#
# Jenkinsfile 中就是通过下面这种方式传入变量的：
#
#   sudo SITE_NAME="${SITE_NAME}" PROJECT_KEY="${PROJECT_KEY}" ... ./scripts/...
#
# 这种写法会把变量只传给当前脚本，不会永久写入系统环境变量。

# 当前要发布的域名/站点名。
# 它会影响：
#   1. 要读取哪个 Nginx 配置文件：nginx/vhost/${SITE_NAME}.conf
#   2. 要发布到哪个目录：/var/www/${SITE_NAME}
# 示例：
#   SITE_NAME=www.mumup.asia
#   SITE_NAME=demo.mumup.asia
#   SITE_NAME=admin.mumup.asia
SITE_NAME="${SITE_NAME:-www.mumup.asia}"

# 前端构建产物目录。
# Vite、Vue、React 等前端项目通常会把构建结果输出到 dist。
# 这里默认读取项目根目录下的 dist：
#   <项目根目录>/dist
SOURCE_DIR="${SOURCE_DIR:-dist}"

# 静态网站部署根目录。
# 默认是 /var/www，最终站点文件会放到：
#   /var/www/${SITE_NAME}
# 如果本地测试时不想写系统目录，也可以临时覆盖：
#   DEPLOY_ROOT=/tmp/www ./scripts/deploy-nginx-static.sh
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www}"

# Nginx 虚拟主机配置目录。
# 默认是 /etc/nginx/conf.d。
# 脚本会把仓库里的 nginx/vhost/${SITE_NAME}.conf 复制到这里。
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"

# 项目标识。
# 用来生成发布版本目录名，也方便从目录名看出是哪个项目发布的。
#
# 优先级：
#   1. 如果外部传入 PROJECT_KEY，就使用 PROJECT_KEY
#   2. 否则如果 Jenkins 有 JOB_NAME，就使用 JOB_NAME
#   3. 都没有时，使用 unknown-project
PROJECT_KEY="${PROJECT_KEY:-${JOB_NAME:-unknown-project}}"

# 发布版本 ID。
# 每次发布都应该对应一个唯一目录，避免覆盖旧版本。
#
# 优先级：
#   1. 如果外部传入 RELEASE_ID，就使用 RELEASE_ID
#   2. 否则如果 Jenkins 有 BUILD_NUMBER，就使用 BUILD_NUMBER
#   3. 都没有时，使用当前时间戳
#
# Jenkinsfile 当前传入的是：
#   RELEASE_ID="${PROJECT_KEY}-${BUILD_NUMBER}"
#
# 示例：
#   jenkins-test-pro-123
RELEASE_ID="${RELEASE_ID:-${BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}}"

# 计算项目根目录的绝对路径。
#
# dirname -- "$0"：
#   取得当前脚本所在目录，也就是 scripts。
#
# "$(dirname -- "$0")/.."：
#   从 scripts 回到项目根目录。
#
# CDPATH= cd -- ... && pwd：
#   进入项目根目录并打印绝对路径。
#   CDPATH= 是为了避免某些 shell 配置影响 cd 输出。
#
# 最终 PROJECT_ROOT 类似：
#   /var/lib/jenkins/workspace/jenkins-test-pro
PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# ----------------------------------------------------------------------------
# 路径区：根据参数拼出本次发布会用到的完整路径
# ----------------------------------------------------------------------------

# dist 的绝对路径。
# 也就是要发布的前端构建产物来源。
# 示例：
#   /var/lib/jenkins/workspace/jenkins-test-pro/dist
SOURCE_PATH="${PROJECT_ROOT}/${SOURCE_DIR}"

# 仓库中 Nginx 站点配置文件的来源路径。
# SITE_NAME 是什么，就读取哪个配置文件。
# 示例：
#   nginx/vhost/www.mumup.asia.conf
VHOST_SOURCE="${PROJECT_ROOT}/nginx/vhost/${SITE_NAME}.conf"

# 当前站点在服务器上的根目录。
# 示例：
#   /var/www/www.mumup.asia
SITE_ROOT="${DEPLOY_ROOT}/${SITE_NAME}"

# 所有历史发布版本存放目录。
# 每次发布都会在这个目录下创建一个新的 release 子目录。
# 示例：
#   /var/www/www.mumup.asia/releases
RELEASES_DIR="${SITE_ROOT}/releases"

# current 软链接路径。
# Nginx 配置通常指向这个 current，而不是直接指向某个 release。
# 这样发布新版时，只需要把 current 指向新目录即可。
# 示例：
#   /var/www/www.mumup.asia/current
CURRENT_LINK="${SITE_ROOT}/current"

# 对 RELEASE_ID 做安全处理，只保留适合文件名的字符。
#
# tr -c 'A-Za-z0-9._-' '-' 的意思是：
#   把所有不是字母、数字、点、下划线、短横线的字符替换成短横线。
#
# 这样可以避免 RELEASE_ID 中出现空格、斜杠等危险字符，
# 防止生成奇怪路径或误写入非预期目录。
SAFE_RELEASE_ID="$(printf '%s' "$RELEASE_ID" | tr -c 'A-Za-z0-9._-' '-')"

# 本次发布对应的目录。
# 示例：
#   /var/www/www.mumup.asia/releases/jenkins-test-pro-123
RELEASE_DIR="${RELEASES_DIR}/${SAFE_RELEASE_ID}"

# Nginx 配置文件最终要复制到的位置。
# 示例：
#   /etc/nginx/conf.d/www.mumup.asia.conf
VHOST_TARGET="${NGINX_CONF_DIR}/${SITE_NAME}.conf"

# ----------------------------------------------------------------------------
# 前置检查：缺少必要文件时立即失败
# ----------------------------------------------------------------------------

# 检查 dist 是否存在。
#
# 如果 dist 不存在，说明前端还没有构建成功，或者 SOURCE_DIR 配错了。
# 这种情况下不能继续发布，否则可能会发布一个空目录或旧内容。
if [ ! -d "$SOURCE_PATH" ]; then
  echo "ERROR: build output not found: $SOURCE_PATH"
  echo "Run npm run build before deploying."
  exit 1
fi

# 检查对应域名的 Nginx 配置是否存在。
#
# 例如 SITE_NAME=www.mumup.asia 时，必须存在：
#   nginx/vhost/www.mumup.asia.conf
#
# 如果 Jenkins 参数里新增了一个 SITE_NAME 选项，
# 也需要同步新增对应的 Nginx 配置文件。
if [ ! -f "$VHOST_SOURCE" ]; then
  echo "ERROR: nginx vhost config not found: $VHOST_SOURCE"
  exit 1
fi

# 打印本次发布的关键路径。
# 这些日志会出现在 Jenkins 控制台里，方便排查：
#   - 发布的是哪个站点
#   - 从哪个 dist 发布
#   - 发布到哪个 release 目录
#   - current 会指向哪里
#   - Nginx 配置会写到哪里
echo "Deploy site: $SITE_NAME"
echo "Project key: $PROJECT_KEY"
echo "Source dist: $SOURCE_PATH"
echo "Release dir: $RELEASE_DIR"
echo "Current link: $CURRENT_LINK"
echo "Nginx config: $VHOST_TARGET"

# ----------------------------------------------------------------------------
# 创建发布目录并复制静态文件
# ----------------------------------------------------------------------------

# 确保 releases 目录存在。
# -p 表示：
#   1. 父目录不存在时一起创建
#   2. 目录已经存在时不报错
mkdir -p "$RELEASES_DIR"

# 防止覆盖已有 release。
#
# 正常情况下，每个 Jenkins BUILD_NUMBER 只对应一个唯一 release。
# 如果 RELEASE_DIR 已经存在，说明：
#   1. 当前构建号已经发布过
#   2. 或者 RELEASE_ID 重复
#   3. 或者有人手动创建过同名目录
#
# 为了避免覆盖线上可回滚版本，这里直接失败。
if [ -e "$RELEASE_DIR" ]; then
  echo "ERROR: release already exists: $RELEASE_DIR"
  exit 1
fi

# 创建本次发布目录。
mkdir -p "$RELEASE_DIR"

# 把 dist 目录里的所有内容复制到本次 release 目录。
#
# "$SOURCE_PATH"/. 的写法很重要：
#   它表示复制 dist 里面的内容，而不是把 dist 目录本身复制进去。
#
# 复制后的结果是：
#   /var/www/www.mumup.asia/releases/xxx/index.html
#   /var/www/www.mumup.asia/releases/xxx/assets/...
#
# 而不是：
#   /var/www/www.mumup.asia/releases/xxx/dist/index.html
cp -R "$SOURCE_PATH"/. "$RELEASE_DIR"/

# ----------------------------------------------------------------------------
# 切换 current 软链接
# ----------------------------------------------------------------------------

# 把 current 指向本次新发布的 release 目录。
#
# ln 参数说明：
#   -s：创建符号链接，也就是软链接
#   -f：如果 current 已存在，强制替换
#   -n：如果 current 本身是指向目录的软链接，不进入该目录，而是替换链接本身
#
# 这一步完成后，Nginx 如果配置 root 指向 current，
# 用户访问到的就是最新发布版本。
#
# 这种方式的优点：
#   1. 新旧版本目录都保留，方便回滚
#   2. 切换动作非常快
#   3. 不需要直接覆盖正在被 Nginx 读取的文件
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

# ----------------------------------------------------------------------------
# 更新 Nginx 配置并重载服务
# ----------------------------------------------------------------------------

# 把仓库里的 Nginx 配置复制到系统 Nginx 配置目录。
#
# 来源：
#   nginx/vhost/${SITE_NAME}.conf
#
# 目标：
#   /etc/nginx/conf.d/${SITE_NAME}.conf
#
# 注意：
#   如果目标文件已存在，这里会直接覆盖。
#   所以仓库里的 nginx/vhost 配置应该被视为当前站点配置的来源。
cp "$VHOST_SOURCE" "$VHOST_TARGET"

# 检查 Nginx 配置是否合法。
#
# nginx -t 会检查所有 Nginx 配置文件语法。
# 如果配置有问题，命令会失败；由于脚本开启了 set -e，
# 后面的 systemctl reload nginx 就不会执行。
#
# 这样可以避免把错误配置加载到线上 Nginx。
nginx -t

# 重新加载 Nginx。
#
# reload 和 restart 不同：
#   reload：平滑重新加载配置，通常不会中断已有连接
#   restart：重启服务，影响更大
#
# 发布静态文件后 reload 的目的：
#   1. 让新的 /etc/nginx/conf.d/${SITE_NAME}.conf 生效
#   2. 如果配置中指向 current，Nginx 会开始使用新的 current 目标
systemctl reload nginx

# 发布成功提示。
# 这行日志会显示在 Jenkins 控制台，表示脚本已经执行完成。
echo "Deploy complete: http://${SITE_NAME}"
