# Jenkins 前端项目域名访问与多项目部署指南

## 1. 当前目标

你现在的前端项目已经可以在 Jenkins 中启动，访问方式是：

```text
http://192.168.64.3:5173
```

你希望后续做到：

```text
http://www.mumup.asia
```

或者多个项目共用一个公网 IP：

```text
www.mumup.asia
admin.mumup.asia
demo.mumup.asia
jenkins.mumup.asia
api.mumup.asia
```

推荐最终架构：

```text
用户浏览器
  -> 域名 DNS
  -> 服务器公网 IP
  -> Nginx 80/443
  -> 不同项目的 dist 静态目录或不同后端端口
```

## 2. 先理解几个关键点

### 2.1 DNS 不能绑定端口

DNS 只能把域名解析到 IP，不能解析到带端口的地址。

不能这样配：

```text
www.mumup.asia -> http://192.168.64.3:5173
```

DNS 只能这样配：

```text
www.mumup.asia -> 服务器 IP
```

如果想访问 `http://www.mumup.asia` 时自动转到 `5173`，需要 Nginx 来做反向代理。

### 2.2 192.168.64.3 是内网 IP

`192.168.64.3` 是局域网或虚拟机内网 IP。

它通常只能被你的电脑或同一局域网访问，公网用户访问不到。

所以：

```text
www.mumup.asia -> 192.168.64.3
```

这个配置只适合本地测试，不适合公网访问。

公网访问必须使用服务器公网 IP。

### 2.3 不带端口访问依赖 80 或 443

浏览器访问：

```text
http://www.mumup.asia
```

默认访问的是：

```text
http://www.mumup.asia:80
```

浏览器访问：

```text
https://www.mumup.asia
```

默认访问的是：

```text
https://www.mumup.asia:443
```

所以如果不想带 `:5173`，就要让 Nginx 监听 `80` 或 `443`，再由 Nginx 转发到 `5173`。

## 3. 现在可以做的事情：内网测试域名访问

当前你还没有公网 IP 时，可以先在本机做 hosts 绑定测试。

### 3.1 本机配置 hosts

在你自己的电脑上编辑 hosts 文件。

macOS：

```bash
sudo vi /etc/hosts
```

Windows：

```text
C:\Windows\System32\drivers\etc\hosts
```

添加：

```text
192.168.64.3 www.mumup.asia
```

保存后，本机访问：

```text
http://www.mumup.asia:5173
```

这一步只是把域名指到虚拟机 IP，仍然需要带 `:5173`。

### 3.2 在虚拟机安装 Nginx

如果你希望本机访问时不带 `:5173`：

```text
http://www.mumup.asia
```

需要在 `192.168.64.3` 这台虚拟机上安装 Nginx。

CentOS Stream 9：

```bash
sudo dnf install -y nginx
sudo systemctl enable --now nginx
```

检查 Nginx 状态：

```bash
sudo systemctl status nginx
```

### 3.3 配置 Nginx 反向代理到 Vite preview

创建配置文件：

```bash
sudo vi /etc/nginx/conf.d/www.mumup.asia.conf
```

写入：

```nginx
server {
    listen 80;
    server_name www.mumup.asia;

    location / {
        proxy_pass http://127.0.0.1:5173;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

检查配置：

```bash
sudo nginx -t
```

重载 Nginx：

```bash
sudo systemctl reload nginx
```

现在本机访问：

```text
http://www.mumup.asia
```

请求链路会变成：

```text
www.mumup.asia
  -> hosts 指到 192.168.64.3
  -> Nginx 80
  -> 127.0.0.1:5173
  -> Jenkins 启动的 Vite preview
```

### 3.4 当前阶段验证命令

在虚拟机上执行：

```bash
curl -I http://127.0.0.1:5173
```

如果这里不通，说明 Jenkins 启动的前端服务没有正常运行。

再执行：

```bash
curl -I http://127.0.0.1
```

如果 `5173` 通，但 `80` 不通，说明 Nginx 配置或 Nginx 服务有问题。

检查 80 端口：

```bash
sudo ss -lntp | grep ':80'
```

检查 5173 端口：

```bash
sudo ss -lntp | grep ':5173'
```

查看 Nginx 日志：

```bash
sudo tail -n 100 /var/log/nginx/error.log
sudo tail -n 100 /var/log/nginx/access.log
```

如果你执行：

```bash
sudo firewall-cmd --add-service=http --permanent
```

看到：

```text
FirewallD is not running
```

说明 firewalld 没运行，不一定是问题。当前重点看 Nginx 是否监听 80，以及云服务器安全组是否放行 80。

## 4. 申请公网 IP 后需要做的事情

有公网 IP 后，才可以让外部用户访问你的域名。

假设你的公网 IP 是：

```text
1.2.3.4
```

实际操作时替换成你自己的公网 IP。

### 4.1 配置 DNS 解析

在域名 DNS 控制台添加：

```text
主机记录：www
记录类型：A
记录值：1.2.3.4
TTL：600
```

如果你希望未来多个项目自动使用二级域名，建议再加泛解析：

```text
主机记录：*
记录类型：A
记录值：1.2.3.4
TTL：600
```

这样下面这些域名都会解析到同一台服务器：

```text
www.mumup.asia
admin.mumup.asia
demo.mumup.asia
jenkins.mumup.asia
api.mumup.asia
```

### 4.2 验证 DNS 是否生效

在本机执行：

```bash
nslookup www.mumup.asia
```

或者：

```bash
dig www.mumup.asia
```

你需要看到解析结果是你的公网 IP。

如果 DNS 还没生效，等几分钟到几十分钟。

### 4.3 云服务器安全组放行端口

在云服务器控制台放行入方向：

```text
TCP 80
TCP 443
```

如果你还需要直接访问 Jenkins：

```text
TCP 8080
```

如果你临时还想访问 Vite preview：

```text
TCP 5173
```

正式部署不建议长期暴露 `5173`，建议只暴露 `80` 和 `443`。

### 4.4 服务器系统防火墙

如果 firewalld 正在运行：

```bash
sudo firewall-cmd --state
```

返回：

```text
running
```

则放行 HTTP 和 HTTPS：

```bash
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload
```

如果返回：

```text
not running
```

或者提示：

```text
FirewallD is not running
```

说明系统 firewalld 没启用，主要检查云服务器安全组和 Nginx 即可。

## 5. 一个域名多个项目共用的推荐方案

### 5.1 域名规划

建议这样规划：

```text
www.mumup.asia        主站
admin.mumup.asia      后台管理前端
demo.mumup.asia       测试项目
jenkins.mumup.asia    Jenkins
api.mumup.asia        后端 API
```

DNS 可以每个子域名单独配 A 记录，也可以使用泛解析。

单独配置：

```text
www      A    公网 IP
admin    A    公网 IP
demo     A    公网 IP
jenkins  A    公网 IP
api      A    公网 IP
```

泛解析：

```text
*        A    公网 IP
```

### 5.2 Nginx 按二级域名转发到不同端口

如果你继续使用多个运行中的服务，可以这样：

```nginx
server {
    listen 80;
    server_name www.mumup.asia;

    location / {
        proxy_pass http://127.0.0.1:5173;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name admin.mumup.asia;

    location / {
        proxy_pass http://127.0.0.1:5174;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name jenkins.mumup.asia;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

这种方式能跑通，但前端项目不建议长期使用 `vite preview` 作为正式服务。

### 5.3 更推荐：Nginx 直接托管前端 dist

前端正式部署推荐：

```text
Jenkins 拉代码
  -> npm ci
  -> npm run build
  -> 生成 dist
  -> 拷贝 dist 到 /var/www/项目名/dist
  -> Nginx 直接托管静态文件
```

目录规划：

```text
/var/www/www.mumup.asia/dist
/var/www/admin.mumup.asia/dist
/var/www/demo.mumup.asia/dist
```

Nginx 配置：

```nginx
server {
    listen 80;
    server_name www.mumup.asia;

    root /var/www/www.mumup.asia/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    listen 80;
    server_name admin.mumup.asia;

    root /var/www/admin.mumup.asia/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

这种方式的优点：

- 不需要长期运行 `npm run preview`。
- 前端静态资源由 Nginx 直接返回，性能更好。
- Jenkins 构建结束后服务仍然稳定。
- 多个项目更容易管理。
- 服务器只需要暴露 80 和 443。

## 6. 当前 Jenkinsfile 后续建议改造

你现在的 Jenkinsfile 核心流程是：

```text
npm ci
npm run build
npm run preview -- --host 0.0.0.0 --port 5173
```

短期可以继续这样用。

正式部署建议改成：

```text
npm ci
npm run build
sudo rm -rf /var/www/www.mumup.asia/dist
sudo mkdir -p /var/www/www.mumup.asia/dist
sudo cp -r dist/* /var/www/www.mumup.asia/dist/
sudo nginx -t
sudo systemctl reload nginx
```

对应 Jenkinsfile 阶段可以改成：

```groovy
stage('Deploy Static Files') {
    steps {
        sh '''
            set -e

            DEPLOY_DIR=/var/www/www.mumup.asia/dist

            sudo rm -rf "$DEPLOY_DIR"
            sudo mkdir -p "$DEPLOY_DIR"
            sudo cp -r dist/* "$DEPLOY_DIR"/

            sudo nginx -t
            sudo systemctl reload nginx
        '''
    }
}
```

注意：Jenkins 用户默认可能没有 sudo 权限。

你需要在服务器上给 Jenkins 配置有限 sudo 权限，只允许它执行必要命令。示例：

```bash
sudo visudo
```

添加：

```text
jenkins ALL=(ALL) NOPASSWD: /usr/bin/rm, /usr/bin/mkdir, /usr/bin/cp, /usr/sbin/nginx, /bin/systemctl
```

更稳妥的方式是写一个部署脚本，只授权 Jenkins 执行这个脚本：

```text
jenkins ALL=(ALL) NOPASSWD: /usr/local/bin/deploy-www-mumup.sh
```

## 7. 建议新增的部署脚本

可以在服务器上创建：

```bash
sudo vi /usr/local/bin/deploy-www-mumup.sh
```

内容：

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$1"
DEPLOY_DIR="/var/www/www.mumup.asia/dist"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "ERROR: source dir not found: $SOURCE_DIR"
  exit 1
fi

rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp -r "$SOURCE_DIR"/. "$DEPLOY_DIR"/

nginx -t
systemctl reload nginx
```

授权：

```bash
sudo chmod +x /usr/local/bin/deploy-www-mumup.sh
```

Jenkinsfile 中调用：

```groovy
stage('Deploy Static Files') {
    steps {
        sh '''
            set -e
            sudo /usr/local/bin/deploy-www-mumup.sh "$WORKSPACE/dist"
        '''
    }
}
```

## 8. HTTPS 后续配置

公网 IP 和域名解析都完成后，建议给域名配置 HTTPS。

CentOS 安装 certbot：

```bash
sudo dnf install -y certbot python3-certbot-nginx
```

申请证书：

```bash
sudo certbot --nginx -d www.mumup.asia
```

如果还有其他子域名：

```bash
sudo certbot --nginx -d www.mumup.asia -d admin.mumup.asia -d demo.mumup.asia
```

检查自动续期：

```bash
sudo certbot renew --dry-run
```

证书成功后，访问方式变成：

```text
https://www.mumup.asia
```

## 9. 推荐执行顺序

### 当前阶段：还没有公网 IP

1. 确认 Jenkins 构建能启动项目。
2. 确认虚拟机访问 `http://127.0.0.1:5173` 成功。
3. 本机 hosts 添加 `192.168.64.3 www.mumup.asia`。
4. 虚拟机安装 Nginx。
5. Nginx 配置 `www.mumup.asia -> 127.0.0.1:5173`。
6. 本机访问 `http://www.mumup.asia` 验证。

### 公网 IP 到位后

1. DNS 添加 `www` A 记录到公网 IP。
2. DNS 添加 `*` 泛解析到公网 IP。
3. 云服务器安全组放行 `80` 和 `443`。
4. Nginx 配置 `www.mumup.asia`。
5. 浏览器访问 `http://www.mumup.asia`。
6. 配置 HTTPS。
7. 浏览器访问 `https://www.mumup.asia`。

### 正式稳定部署

1. Jenkins 不再长期运行 `npm run preview`。
2. Jenkins 构建后拷贝 `dist` 到 `/var/www/域名/dist`。
3. Nginx 直接托管静态资源。
4. 每个项目一个二级域名。
5. 每个项目一个 Nginx server 配置。
6. Jenkins 每个项目只负责构建和发布静态文件。

## 10. 常见问题排查

### 10.1 域名打不开

先确认 DNS：

```bash
nslookup www.mumup.asia
```

如果不是你的服务器 IP，说明 DNS 没配好或还没生效。

### 10.2 IP 能访问，域名不能访问

检查 Nginx 的 `server_name`：

```bash
sudo nginx -T | grep -n "server_name"
```

确认有：

```text
server_name www.mumup.asia;
```

### 10.3 80 端口访问不了

检查 Nginx：

```bash
sudo systemctl status nginx
sudo nginx -t
sudo ss -lntp | grep ':80'
```

检查云服务器安全组是否放行 `TCP 80`。

### 10.4 访问域名返回 502

如果使用反向代理到 `5173`，502 通常说明后端服务没起来。

检查：

```bash
curl -I http://127.0.0.1:5173
sudo ss -lntp | grep ':5173'
```

如果 `5173` 没监听，回 Jenkins 重新构建或查看 `frontend.log`。

### 10.5 前端页面刷新后 404

如果是 Vue Router history 模式，需要 Nginx 配置：

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

### 10.6 Jenkins 没权限拷贝到 /var/www

检查 Jenkins 用户：

```bash
id jenkins
```

给部署目录授权：

```bash
sudo mkdir -p /var/www/www.mumup.asia/dist
sudo chown -R jenkins:jenkins /var/www/www.mumup.asia
```

或者使用 sudo 部署脚本。

## 11. 最终推荐状态

最推荐你后续做到这个状态：

```text
DNS:
  *.mumup.asia -> 公网 IP

Nginx:
  www.mumup.asia     -> /var/www/www.mumup.asia/dist
  admin.mumup.asia   -> /var/www/admin.mumup.asia/dist
  demo.mumup.asia    -> /var/www/demo.mumup.asia/dist
  jenkins.mumup.asia -> http://127.0.0.1:8080

Jenkins:
  每个项目拉 GitHub 代码
  npm ci
  npm run build
  发布 dist 到对应 /var/www 目录
  reload nginx

公网只开放:
  80
  443

不再对外开放:
  5173
```

这样一个公网 IP 就可以承载多个项目，后续增加项目只需要：

1. 新增一个二级域名。
2. 新增一个 Nginx server 配置。
3. 新增一个 Jenkins 项目或 Jenkinsfile 部署目录。
4. 构建并发布。
