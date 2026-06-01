# Nginx 与 Ingress 介绍

## 1. Nginx 是什么

Nginx 是一个高性能 Web 服务器，也常用作反向代理服务器。

在前端项目里，Nginx 最常见的用途是：

- 托管静态资源，例如 `dist/index.html`、`dist/assets/*.js`、`dist/assets/*.css`。
- 把用户请求转发到后端服务。
- 按域名区分不同项目。
- 配置 HTTPS 证书。
- 做缓存、压缩、访问日志等。

例如一个普通前端项目构建后会生成：

```text
dist/
  index.html
  assets/
    index.js
    index.css
```

Nginx 可以直接把这个目录作为网站对外提供访问：

```nginx
server {
    listen 80;
    server_name example.com;

    root /var/www/example/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

访问：

```text
http://example.com
```

就会看到前端页面。

## 2. 反向代理是什么

反向代理可以理解为：

```text
用户
  -> Nginx
  -> 真正的应用服务
```

用户只访问 Nginx，Nginx 再把请求转发给后面的服务。

例如你的前端服务运行在：

```text
http://127.0.0.1:5173
```

可以用 Nginx 代理成：

```text
http://frontend.example.com
```

配置示例：

```nginx
server {
    listen 80;
    server_name frontend.example.com;

    location / {
        proxy_pass http://127.0.0.1:5173;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## 3. Ingress 是什么

Ingress 是 Kubernetes 里的一个资源对象，用来描述“外部流量如何进入集群”。

它本身不是 Nginx，也不是负载均衡器。

Ingress 更像一份规则：

```text
访问 jenkins-test.apps.example.com
  -> 转发到 jenkins-test-frontend Service
```

Ingress 示例：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-test-frontend
  namespace: frontend
spec:
  ingressClassName: nginx
  rules:
    - host: jenkins-test.apps.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jenkins-test-frontend
                port:
                  number: 80
```

这段配置的意思是：

```text
当请求的域名是 jenkins-test.apps.example.com
并且路径以 / 开头
就转发到 frontend 命名空间里的 jenkins-test-frontend Service 的 80 端口
```

## 4. ingress-nginx 是什么

Ingress 只是一份规则，必须有一个控制器来真正执行这些规则。

`ingress-nginx` 就是最常见的 Ingress Controller 之一。

它的作用是：

```text
监听 Kubernetes 里的 Ingress 资源
  -> 自动生成 Nginx 配置
  -> 用 Nginx 转发外部请求到集群内 Service
```

所以三者关系是：

```text
Ingress：Kubernetes 里的转发规则
ingress-nginx：读取 Ingress 规则并执行转发的控制器
Nginx：真正处理 HTTP 请求的服务器
```

## 5. 普通 Nginx 和 ingress-nginx 的区别

### 普通 Nginx

普通 Nginx 通常运行在一台服务器上。

你需要手动写配置：

```nginx
server {
    listen 80;
    server_name project-a.example.com;

    location / {
        proxy_pass http://127.0.0.1:5173;
    }
}
```

适合：

- 单机部署。
- 少量项目。
- 不使用 Kubernetes 的场景。
- 直接托管前端静态资源。

### ingress-nginx

ingress-nginx 运行在 Kubernetes 集群里。

你不直接写 Nginx 配置，而是写 Kubernetes Ingress：

```yaml
rules:
  - host: project-a.example.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: project-a
              port:
                number: 80
```

适合：

- Kubernetes 部署。
- 多项目、多环境。
- 自动化部署。
- Jenkins、GitLab CI、Argo CD 等持续部署场景。

## 6. Service 是什么

Ingress 不会直接转发到 Pod，而是转发到 Service。

常见链路：

```text
用户
  -> 域名
  -> ingress-nginx
  -> Ingress 规则
  -> Service
  -> Pod
```

前端项目部署到 Kubernetes 后，一般会有：

```text
Deployment：管理前端 Pod
Service：给前端 Pod 提供稳定访问入口
Ingress：把域名流量转发到 Service
```

## 7. 前端项目在 Kubernetes 中的推荐部署方式

前端项目不要在 Kubernetes 里运行：

```bash
npm run preview
```

更推荐：

```text
npm run build
  -> 生成 dist
  -> 打包 nginx 镜像
  -> Kubernetes 运行 nginx 容器
  -> ingress-nginx 通过域名访问
```

Dockerfile 示例：

```dockerfile
FROM nginx:1.27-alpine

COPY dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

这样做的好处：

- 不依赖 Node 进程长期运行。
- 镜像小，启动快。
- Nginx 更适合托管静态资源。
- 方便多副本部署。
- 更适合生产环境。

## 8. 域名如何进入 ingress-nginx

要让域名访问到 Kubernetes 服务，需要两层配置。

第一层是 DNS：

```text
jenkins-test.apps.example.com -> ingress-nginx 入口 IP
```

第二层是 Ingress：

```text
jenkins-test.apps.example.com -> jenkins-test-frontend Service
```

完整链路：

```text
浏览器访问 jenkins-test.apps.example.com
  -> DNS 找到 ingress-nginx IP
  -> 请求到达 ingress-nginx
  -> ingress-nginx 查找 host 匹配的 Ingress
  -> 转发到对应 Service
  -> Service 转发到 Pod
  -> Pod 里的 Nginx 返回前端页面
```

## 9. 多项目如何区分

多个项目可以用不同域名区分：

```text
project-a.apps.example.com
project-b.apps.example.com
project-c.apps.example.com
```

每个项目一套资源：

```text
project-a Deployment
project-a Service
project-a Ingress

project-b Deployment
project-b Service
project-b Ingress
```

Ingress 示例：

```yaml
rules:
  - host: project-a.apps.example.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: project-a
              port:
                number: 80
```

## 10. 多环境如何区分

可以用不同子域名：

```text
dev-jenkins-test.apps.example.com
test-jenkins-test.apps.example.com
prod-jenkins-test.apps.example.com
```

也可以用环境作为二级路径：

```text
jenkins-test.dev.apps.example.com
jenkins-test.test.apps.example.com
jenkins-test.prod.apps.example.com
```

推荐使用域名区分环境，不推荐用路径区分：

```text
/dev
/test
/prod
```

原因是前端项目经常涉及路由、静态资源路径、登录回调地址，用域名隔离更清晰。

## 11. HTTPS 怎么做

在 Kubernetes 里，HTTPS 通常配合 `cert-manager`。

流程：

```text
cert-manager
  -> 自动申请证书
  -> 写入 Kubernetes Secret
  -> Ingress 使用这个 Secret 开启 HTTPS
```

Ingress TLS 示例：

```yaml
spec:
  tls:
    - hosts:
        - jenkins-test.apps.example.com
      secretName: jenkins-test-frontend-tls
```

## 12. DNS 是否可以自动创建

可以。

如果你不想每次手动去 DNS 控制台加记录，可以使用 ExternalDNS。

ExternalDNS 会：

```text
监听 Ingress
  -> 读取 host
  -> 调用 DNS 服务商 API
  -> 自动创建 DNS 记录
```

例如你创建了 Ingress：

```text
host: project-a.apps.example.com
```

ExternalDNS 会自动创建：

```text
project-a.apps.example.com -> ingress-nginx IP
```

如果你已经配置了泛域名：

```text
*.apps.example.com -> ingress-nginx IP
```

那短期内可以不用 ExternalDNS。

## 13. 推荐落地顺序

1. 先用普通 Nginx 理解域名转发。
2. 准备 Kubernetes 集群。
3. 安装 ingress-nginx。
4. 配置泛域名解析到 ingress-nginx。
5. 前端项目构建成 nginx 镜像。
6. 创建 Deployment、Service、Ingress。
7. 验证域名访问前端页面。
8. 接入 Jenkins 自动构建镜像并部署。
9. 项目变多后再接 ExternalDNS。
10. 需要 HTTPS 后接 cert-manager。

## 14. 一句话总结

```text
Nginx 是 Web 服务器。
Ingress 是 Kubernetes 里的域名转发规则。
ingress-nginx 是用 Nginx 执行这些 Ingress 规则的控制器。
```
