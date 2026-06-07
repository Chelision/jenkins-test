# Nginx 配置目录

这个目录用于把前端项目自己的 Nginx 配置跟代码一起管理。

推荐约定：

```text
nginx/vhost/www.mumup.asia.conf
nginx/vhost/admin.mumup.asia.conf
nginx/vhost/demo.mumup.asia.conf
```

每个正式生效的配置文件使用 `.conf` 结尾。示例配置使用 `.conf.example` 结尾，部署脚本不会自动发布示例文件。

Jenkinsfile 里的 `SITE_NAME` 是下拉选择项。新增一个下拉选项时，也要新增同名配置：

```text
SITE_NAME=admin.mumup.asia
nginx/vhost/admin.mumup.asia.conf
```

Jenkins 发布静态文件时，可以把当前项目的配置复制到服务器：

```text
nginx/vhost/<SITE_NAME>.conf -> /etc/nginx/conf.d/<SITE_NAME>.conf
dist/ -> /var/www/<SITE_NAME>/releases/<BUILD_NUMBER>/
/var/www/<SITE_NAME>/current -> /var/www/<SITE_NAME>/releases/<BUILD_NUMBER>/
```

例如：

```text
SITE_NAME=www.mumup.asia
nginx/vhost/www.mumup.asia.conf -> /etc/nginx/conf.d/www.mumup.asia.conf
dist/ -> /var/www/www.mumup.asia/releases/12/
/var/www/www.mumup.asia/current -> /var/www/www.mumup.asia/releases/12/
```

每个域名都有自己的独立发布目录：

```text
/var/www/www.mumup.asia/current
/var/www/demo.mumup.asia/current
/var/www/admin.mumup.asia/current
```

所以同一个项目先发布到 `www.mumup.asia`，再发布到 `demo.mumup.asia`，两个域名会分别保留自己的 `current`，不会互相覆盖。

同一个域名再次发布时，只会切换这个域名自己的 `current`，其他域名不受影响。
