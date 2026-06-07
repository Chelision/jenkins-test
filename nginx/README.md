# Nginx 配置目录

这个目录用于把前端项目自己的 Nginx 配置跟代码一起管理。

推荐约定：

```text
nginx/vhost/www.mumup.asia.conf
nginx/vhost/admin.mumup.asia.conf
nginx/vhost/demo.mumup.asia.conf
```

每个正式生效的配置文件使用 `.conf` 结尾。示例配置使用 `.conf.example` 结尾，部署脚本不会自动发布示例文件。

Jenkins 发布静态文件时，可以把当前项目的配置复制到服务器：

```text
nginx/vhost/<SITE_NAME>.conf -> /etc/nginx/conf.d/<SITE_NAME>.conf
dist/ -> /var/www/<SITE_NAME>/dist/
```

例如：

```text
SITE_NAME=www.mumup.asia
nginx/vhost/www.mumup.asia.conf -> /etc/nginx/conf.d/www.mumup.asia.conf
dist/ -> /var/www/www.mumup.asia/dist/
```
