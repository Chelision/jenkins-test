# `deploy-nginx-static.sh` 脚本流程说明

这份文档用于说明 `scripts/deploy-nginx-static.sh` 的整体部署流程，以及它和 Jenkins、Nginx 配置、`current` 软链接之间的关系。

## 1. 脚本的核心作用

这个脚本主要做两件事：

1. 把前端构建产物 `dist` 复制到服务器的 release 发布目录。
2. 把仓库里的 Nginx vhost 配置复制到服务器的 Nginx 配置目录，并重载 Nginx。

简化理解：

```text
项目 dist
  -> /var/www/<SITE_NAME>/releases/<RELEASE_ID>

nginx/vhost/<SITE_NAME>.conf
  -> /etc/nginx/conf.d/<SITE_NAME>.conf
```

然后脚本会把：

```text
/var/www/<SITE_NAME>/current
```

这个软链接切换到最新的 release 目录。

## 2. Jenkins 是怎么调用它的

`jenkinsfile` 中的部署阶段会执行：

```sh
sudo SITE_NAME="${SITE_NAME}" PROJECT_KEY="${PROJECT_KEY}" RELEASE_ID="${PROJECT_KEY}-${BUILD_NUMBER}" ./scripts/deploy-nginx-static.sh
```

这里传给脚本三个关键变量：

| 变量 | 来源 | 作用 |
| --- | --- | --- |
| `SITE_NAME` | Jenkins 构建参数 | 当前要部署的域名，例如 `admin.mumup.asia` |
| `PROJECT_KEY` | Jenkinsfile 的 `environment` | 项目标识，例如 `jenkins-test-pro` |
| `RELEASE_ID` | `PROJECT_KEY` + `BUILD_NUMBER` | 本次发布目录名，例如 `jenkins-test-pro-123` |

所以如果 Jenkins 里选择：

```text
SITE_NAME=admin.mumup.asia
BUILD_NUMBER=123
PROJECT_KEY=jenkins-test-pro
```

实际效果大概是：

```text
发布目录：
/var/www/admin.mumup.asia/releases/jenkins-test-pro-123

当前线上入口：
/var/www/admin.mumup.asia/current

Nginx 配置：
/etc/nginx/conf.d/admin.mumup.asia.conf
```

## 3. 主要变量说明

脚本开头会定义一组变量，如果外部没有传入，就使用默认值。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SITE_NAME` | `www.mumup.asia` | 当前站点域名 |
| `SOURCE_DIR` | `dist` | 本地构建产物目录 |
| `DEPLOY_ROOT` | `/var/www` | 服务器静态站点根目录 |
| `NGINX_CONF_DIR` | `/etc/nginx/conf.d` | Nginx 配置文件目录 |
| `PROJECT_KEY` | `JOB_NAME` 或 `unknown-project` | 项目标识 |
| `RELEASE_ID` | `BUILD_NUMBER` 或时间戳 | 本次发布版本 ID |

例如：

```sh
SITE_NAME="${SITE_NAME:-www.mumup.asia}"
```

意思是：

- 如果外部传了 `SITE_NAME`，就使用外部传入的值。
- 如果外部没有传，或者传的是空值，就使用 `www.mumup.asia`。

## 4. 路径是怎么拼出来的

假设：

```text
SITE_NAME=admin.mumup.asia
DEPLOY_ROOT=/var/www
RELEASE_ID=jenkins-test-pro-123
```

脚本会拼出这些路径：

| 变量 | 最终值示例 | 说明 |
| --- | --- | --- |
| `SOURCE_PATH` | `<项目根目录>/dist` | 要发布的前端构建产物 |
| `VHOST_SOURCE` | `<项目根目录>/nginx/vhost/admin.mumup.asia.conf` | 仓库里的 Nginx 配置源文件 |
| `SITE_ROOT` | `/var/www/admin.mumup.asia` | 当前域名的网站根目录 |
| `RELEASES_DIR` | `/var/www/admin.mumup.asia/releases` | 历史版本目录 |
| `RELEASE_DIR` | `/var/www/admin.mumup.asia/releases/jenkins-test-pro-123` | 本次发布目录 |
| `CURRENT_LINK` | `/var/www/admin.mumup.asia/current` | 当前线上版本入口 |
| `VHOST_TARGET` | `/etc/nginx/conf.d/admin.mumup.asia.conf` | Nginx 最终配置文件 |

## 5. 服务器目录结构

如果同时部署三个域名：

```text
www.mumup.asia
demo.mumup.asia
admin.mumup.asia
```

Nginx 配置目录一般是：

```text
/etc/nginx/
└── conf.d/
    ├── www.mumup.asia.conf
    ├── demo.mumup.asia.conf
    └── admin.mumup.asia.conf
```

静态文件目录一般是：

```text
/var/www/
├── www.mumup.asia/
│   ├── releases/
│   │   ├── jenkins-test-pro-101/
│   │   └── jenkins-test-pro-102/
│   └── current -> /var/www/www.mumup.asia/releases/jenkins-test-pro-102
├── demo.mumup.asia/
│   ├── releases/
│   │   ├── jenkins-test-pro-201/
│   │   └── jenkins-test-pro-202/
│   └── current -> /var/www/demo.mumup.asia/releases/jenkins-test-pro-202
└── admin.mumup.asia/
    ├── releases/
    │   ├── jenkins-test-pro-301/
    │   └── jenkins-test-pro-302/
    └── current -> /var/www/admin.mumup.asia/releases/jenkins-test-pro-302
```

重点：

- Nginx 配置文件是按域名区分的。
- release 目录是按每次构建版本区分的。
- `current` 是当前线上版本入口。
- 每次发布只切换对应域名自己的 `current`，不会影响其他域名。

## 6. `current` 软链接是什么

`current` 是服务器文件系统里的软链接，可以理解成快捷方式。

Nginx 配置中通常写：

```nginx
root /var/www/admin.mumup.asia/current;
```

但 `current` 本身并不是一个真实版本目录，它指向某一个 release：

```text
/var/www/admin.mumup.asia/current
  -> /var/www/admin.mumup.asia/releases/jenkins-test-pro-123
```

脚本里负责切换软链接的是：

```sh
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
```

这句的意思是：

```text
把 /var/www/<SITE_NAME>/current 指向本次新发布的 release 目录
```

例如发布前：

```text
current -> /var/www/admin.mumup.asia/releases/jenkins-test-pro-122
```

发布后：

```text
current -> /var/www/admin.mumup.asia/releases/jenkins-test-pro-123
```

这样 Nginx 配置不需要每次改，只要 `current` 指向新版本，用户访问到的就是新版本。

## 7. Nginx 配置和软链接的关系

Nginx 配置负责告诉 Nginx：

```text
访问哪个域名，就去哪个目录找静态文件
```

例如 `admin.mumup.asia.conf`：

```nginx
server {
    listen 80;
    server_name admin.mumup.asia;

    root /var/www/admin.mumup.asia/current;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

这里的关系是：

```text
浏览器访问 admin.mumup.asia
  -> Nginx 匹配 server_name admin.mumup.asia
  -> Nginx 使用 root /var/www/admin.mumup.asia/current
  -> current 指向某个 releases/xxx
  -> 返回这个 release 里的 index.html、assets 等文件
```

所以：

- `server_name` 来自 `.conf` 文件。
- `.conf` 文件按域名准备。
- `current` 由部署脚本创建或切换。
- Nginx 只需要固定指向 `current`。

## 8. 脚本完整执行流程

### 8.1 检查 `dist` 是否存在

脚本先检查：

```text
<项目根目录>/dist
```

如果不存在，说明前端还没有构建成功，脚本直接失败。

对应逻辑：

```sh
if [ ! -d "$SOURCE_PATH" ]; then
  echo "ERROR: build output not found: $SOURCE_PATH"
  exit 1
fi
```

### 8.2 检查 Nginx vhost 配置是否存在

脚本会根据 `SITE_NAME` 查找对应配置：

```text
nginx/vhost/<SITE_NAME>.conf
```

例如：

```text
nginx/vhost/admin.mumup.asia.conf
```

如果文件不存在，脚本直接失败。

### 8.3 创建 releases 目录

脚本会确保这个目录存在：

```text
/var/www/<SITE_NAME>/releases
```

如果不存在就创建。

### 8.4 检查本次 release 是否已存在

脚本会检查：

```text
/var/www/<SITE_NAME>/releases/<RELEASE_ID>
```

如果已经存在，脚本会失败，避免覆盖旧版本。

这是为了保留历史 release，方便回滚。

### 8.5 创建本次 release 目录

例如：

```text
/var/www/admin.mumup.asia/releases/jenkins-test-pro-123
```

### 8.6 复制 `dist` 内容

脚本执行：

```sh
cp -R "$SOURCE_PATH"/. "$RELEASE_DIR"/
```

注意这里复制的是 `dist` 里面的内容，不是把 `dist` 目录本身复制进去。

结果是：

```text
/var/www/admin.mumup.asia/releases/jenkins-test-pro-123/index.html
/var/www/admin.mumup.asia/releases/jenkins-test-pro-123/assets/...
```

不是：

```text
/var/www/admin.mumup.asia/releases/jenkins-test-pro-123/dist/index.html
```

### 8.7 切换 `current`

脚本执行：

```sh
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
```

这一步会让：

```text
/var/www/<SITE_NAME>/current
```

指向最新 release。

这一步完成后，Nginx 访问 `current` 时，实际上访问的是最新版本目录。

### 8.8 复制 Nginx 配置

脚本执行：

```sh
cp "$VHOST_SOURCE" "$VHOST_TARGET"
```

例如：

```text
nginx/vhost/admin.mumup.asia.conf
  -> /etc/nginx/conf.d/admin.mumup.asia.conf
```

如果服务器上已经存在同名配置文件，会被覆盖。

### 8.9 检查 Nginx 配置

脚本执行：

```sh
nginx -t
```

如果配置语法错误，脚本会失败，后面的 reload 不会执行。

### 8.10 重载 Nginx

脚本执行：

```sh
systemctl reload nginx
```

这会让新的 Nginx 配置生效。

`reload` 通常比 `restart` 平滑，不会粗暴中断服务。

## 9. 一个完整例子

假设 Jenkins 中选择：

```text
SITE_NAME=demo.mumup.asia
PROJECT_KEY=jenkins-test-pro
BUILD_NUMBER=88
```

Jenkins 调用脚本时传入：

```text
RELEASE_ID=jenkins-test-pro-88
```

脚本会做：

```text
1. 检查 dist 是否存在
2. 检查 nginx/vhost/demo.mumup.asia.conf 是否存在
3. 创建 /var/www/demo.mumup.asia/releases
4. 创建 /var/www/demo.mumup.asia/releases/jenkins-test-pro-88
5. 复制 dist 内容到 /var/www/demo.mumup.asia/releases/jenkins-test-pro-88
6. 切换 /var/www/demo.mumup.asia/current 指向这个新目录
7. 复制 nginx/vhost/demo.mumup.asia.conf 到 /etc/nginx/conf.d/demo.mumup.asia.conf
8. 执行 nginx -t
9. 执行 systemctl reload nginx
```

最终访问链路：

```text
用户访问 http://demo.mumup.asia
  -> Nginx 匹配 server_name demo.mumup.asia
  -> Nginx 读取 /var/www/demo.mumup.asia/current
  -> current 指向 /var/www/demo.mumup.asia/releases/jenkins-test-pro-88
  -> 返回新版本前端页面
```

## 10. 常用排查命令

查看 Nginx 配置是否存在：

```sh
ls -l /etc/nginx/conf.d/
```

查看某个域名配置内容：

```sh
cat /etc/nginx/conf.d/admin.mumup.asia.conf
```

查看当前线上版本指向哪里：

```sh
ls -l /var/www/admin.mumup.asia/current
```

查看所有 release：

```sh
ls -l /var/www/admin.mumup.asia/releases
```

检查 Nginx 配置：

```sh
sudo nginx -t
```

重载 Nginx：

```sh
sudo systemctl reload nginx
```

## 11. 总结

这个脚本的部署模型可以概括为：

```text
一个域名一个 Nginx conf
一个域名一个 /var/www/<域名> 目录
一次 Jenkins 构建生成一个 releases/<版本号>
Nginx 永远访问 current
部署脚本负责把 current 切到最新 release
```

所以你可以记住这句话：

```text
Nginx 配置管域名入口，release 目录管历史版本，current 软链接管当前线上版本。
```
