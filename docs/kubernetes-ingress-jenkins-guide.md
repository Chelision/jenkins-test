# Jenkins 前端项目接入 Kubernetes Ingress 详细指南

## 1. 这份文档解决什么问题

你当前项目已经有两种部署能力：

```text
方式一：Jenkins 启动 vite preview
访问：http://服务器IP:5173

方式二：Jenkins 构建 dist，并发布到单机 Nginx
访问：http://www.mumup.asia
```

当前单机 Nginx 方案的链路是：

```text
用户访问域名
  -> DNS 解析到服务器公网 IP
  -> 服务器 Nginx
  -> /var/www/<域名>/current
  -> 前端 dist 静态资源
```

如果后续接入 Kubernetes Ingress，目标链路会变成：

```text
用户访问域名
  -> DNS 解析到 ingress-nginx 入口 IP
  -> Kubernetes ingress-nginx
  -> Kubernetes Ingress 规则
  -> Kubernetes Service
  -> 前端 nginx Pod
  -> dist 静态资源
```

简单说：

```text
单机 Nginx 方案：Nginx 配置在服务器 /etc/nginx/conf.d
Ingress 方案：域名转发规则写在 Kubernetes Ingress yaml
```

## 2. 先明确 Ingress 能做什么，不能做什么

### 2.1 Ingress 能做什么

Ingress 可以根据域名和路径把请求转发到不同 Service。

例如：

```text
www.mumup.asia   -> www-frontend Service
demo.mumup.asia  -> demo-frontend Service
admin.mumup.asia -> admin-frontend Service
```

对应 Kubernetes Ingress 大概是：

```yaml
rules:
  - host: www.mumup.asia
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: www-frontend
              port:
                number: 80
```

### 2.2 Ingress 不能直接做什么

Ingress 本身不会自动去腾讯云 DNS 创建解析。

也就是说，你创建了：

```yaml
host: demo.mumup.asia
```

并不代表腾讯云 DNS 会自动新增：

```text
demo.mumup.asia -> ingress-nginx 入口 IP
```

如果想自动创建 DNS，需要额外接入：

```text
ExternalDNS + 腾讯云 DNS Provider/Webhook
```

### 2.3 当前最推荐的 DNS 方案

你当前阶段最推荐：

```text
腾讯云 DNS 配一条泛解析
*.mumup.asia -> ingress-nginx 入口公网 IP
```

这样以后新增：

```text
test.mumup.asia
abc.mumup.asia
project-a.mumup.asia
```

不需要再去腾讯云单独加 DNS 记录，只需要新增 Kubernetes Ingress 规则。

注意：

```text
*.mumup.asia 不包含 mumup.asia 根域名
```

如果还要访问根域名：

```text
mumup.asia
```

需要单独添加：

```text
@ -> ingress-nginx 入口公网 IP
```

## 3. 当前项目迁移到 Ingress 后的目录建议

你当前项目已有：

```text
Jenkinsfile
package.json
nginx/vhost/*.conf
scripts/deploy-nginx-static.sh
```

如果接入 Kubernetes Ingress，建议新增：

```text
Dockerfile
nginx/default.conf
k8s/namespace.yaml
k8s/deployment.yaml
k8s/service.yaml
k8s/ingress.yaml
k8s/kustomization.yaml
```

目录结构示例：

```text
jenkins-test-pro/
  Dockerfile
  Jenkinsfile
  package.json
  nginx/
    default.conf
    vhost/
      www.mumup.asia.conf
      demo.mumup.asia.conf
      admin.mumup.asia.conf
  k8s/
    namespace.yaml
    deployment.yaml
    service.yaml
    ingress.yaml
    kustomization.yaml
```

说明：

```text
nginx/vhost/*.conf
```

继续服务于你当前的单机 Nginx 方案。

```text
nginx/default.conf
```

用于容器内部 Nginx 托管 dist。

```text
k8s/*.yaml
```

用于 Kubernetes 部署。

两套方案可以同时保留，Jenkins 通过参数选择部署到哪里。

## 4. Kubernetes 前置条件

接入 Ingress 之前，你需要准备这些东西。

### 4.1 Kubernetes 集群

可以是：

```text
腾讯云 TKE
自建 Kubernetes
本地测试集群，例如 minikube、kind
```

正式公网访问建议使用云上的 Kubernetes，例如腾讯云 TKE。

### 4.2 kubectl 可用

在 Jenkins 机器或 Jenkins 容器里执行：

```bash
kubectl version --client
kubectl get nodes
```

能看到节点说明 Jenkins 有权限访问集群。

### 4.3 ingress-nginx 已安装

检查：

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

你需要看到类似：

```text
ingress-nginx-controller
```

如果还没安装，可以用 Helm：

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### 4.4 获取 ingress-nginx 入口 IP

执行：

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

如果是云集群，通常会看到：

```text
EXTERNAL-IP
```

记录这个 IP：

```text
INGRESS_IP=你的 ingress-nginx 入口公网 IP
```

### 4.5 DNS 泛解析

在腾讯云 DNS 配置：

```text
主机记录：*
记录类型：A
记录值：INGRESS_IP
TTL：600
```

如果需要根域名：

```text
主机记录：@
记录类型：A
记录值：INGRESS_IP
TTL：600
```

验证：

```bash
nslookup demo.mumup.asia
nslookup admin.mumup.asia
```

返回的 IP 应该是 `INGRESS_IP`。

## 5. 把前端 dist 做成 Nginx 镜像

Kubernetes 里不推荐运行：

```bash
npm run preview
```

更推荐：

```text
npm run build
-> 生成 dist
-> 用 nginx 容器托管 dist
```

### 5.1 新增 Dockerfile

项目根目录新增：

```dockerfile
FROM nginx:1.27-alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### 5.2 新增 nginx/default.conf

```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|svg|ico|webp|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
}
```

这份配置只在容器内部使用。

外部域名不在这里判断，而是交给 Kubernetes Ingress 判断。

## 6. Kubernetes YAML 示例

下面示例以当前项目为例：

```text
APP_NAME=jenkins-test-pro
NAMESPACE=frontend
SITE_NAME=demo.mumup.asia
```

### 6.1 namespace.yaml

`k8s/namespace.yaml`：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: frontend
```

### 6.2 deployment.yaml

`k8s/deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins-test-pro
  namespace: frontend
  labels:
    app: jenkins-test-pro
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins-test-pro
  template:
    metadata:
      labels:
        app: jenkins-test-pro
    spec:
      containers:
        - name: frontend
          image: your-registry.example.com/frontend/jenkins-test-pro:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 20
```

### 6.3 service.yaml

`k8s/service.yaml`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: jenkins-test-pro
  namespace: frontend
spec:
  type: ClusterIP
  selector:
    app: jenkins-test-pro
  ports:
    - name: http
      port: 80
      targetPort: 80
```

### 6.4 ingress.yaml

`k8s/ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-test-pro
  namespace: frontend
spec:
  ingressClassName: nginx
  rules:
    - host: demo.mumup.asia
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jenkins-test-pro
                port:
                  number: 80
```

访问链路：

```text
demo.mumup.asia
  -> ingress-nginx
  -> Ingress host=demo.mumup.asia
  -> Service jenkins-test-pro:80
  -> Pod containerPort 80
  -> nginx 容器里的 /usr/share/nginx/html
```

## 7. 多域名部署怎么做

你现在 Jenkinsfile 里有：

```text
SITE_NAME:
  www.mumup.asia
  demo.mumup.asia
  admin.mumup.asia
```

如果使用单机 Nginx，`SITE_NAME` 会决定发布到：

```text
/var/www/<SITE_NAME>/current
```

如果使用 Kubernetes Ingress，`SITE_NAME` 应该决定：

```text
Ingress rules[0].host
```

也就是说：

```text
选择 www.mumup.asia
-> Ingress host=www.mumup.asia

选择 demo.mumup.asia
-> Ingress host=demo.mumup.asia

选择 admin.mumup.asia
-> Ingress host=admin.mumup.asia
```

### 7.1 同一个项目发布到多个域名

你之前提到的需求是：

```text
A 项目先发布到 www.mumup.asia
A 项目再发布到 demo.mumup.asia
两个域名都还能访问，不能互相覆盖
```

在 Kubernetes 里可以有两种做法。

### 7.2 做法一：同一个 Deployment，多个 Ingress

如果两个域名展示完全一样的内容，可以让多个 Ingress host 指向同一个 Service。

```text
www.mumup.asia  -> jenkins-test-pro Service
demo.mumup.asia -> jenkins-test-pro Service
```

优点：

- 简单。
- 镜像只部署一份。
- 两个域名总是展示同一个版本。

缺点：

- 不能让 www 和 demo 保持不同版本。

### 7.3 做法二：每个域名一套 Deployment/Service/Ingress

如果你希望：

```text
www.mumup.asia 保持版本 A
demo.mumup.asia 更新到版本 B
```

推荐每个域名一套 Kubernetes 资源。

例如：

```text
www.mumup.asia:
  Deployment: jenkins-test-pro-www
  Service: jenkins-test-pro-www
  Ingress: jenkins-test-pro-www

demo.mumup.asia:
  Deployment: jenkins-test-pro-demo
  Service: jenkins-test-pro-demo
  Ingress: jenkins-test-pro-demo

admin.mumup.asia:
  Deployment: jenkins-test-pro-admin
  Service: jenkins-test-pro-admin
  Ingress: jenkins-test-pro-admin
```

这样每个域名可以独立发布、独立回滚、互不覆盖。

这和你当前单机 Nginx 的：

```text
/var/www/www.mumup.asia/current
/var/www/demo.mumup.asia/current
/var/www/admin.mumup.asia/current
```

是同一种思想，只是换成 Kubernetes 资源隔离。

## 8. 推荐给当前项目的 Ingress 资源命名方式

为了让 `SITE_NAME` 能安全变成 Kubernetes 资源名，需要把点号替换掉。

例如：

```text
www.mumup.asia   -> jenkins-test-pro-www
demo.mumup.asia  -> jenkins-test-pro-demo
admin.mumup.asia -> jenkins-test-pro-admin
```

建议映射：

```text
SITE_NAME=www.mumup.asia
K8S_APP_NAME=jenkins-test-pro-www

SITE_NAME=demo.mumup.asia
K8S_APP_NAME=jenkins-test-pro-demo

SITE_NAME=admin.mumup.asia
K8S_APP_NAME=jenkins-test-pro-admin
```

Jenkins 里可以用 shell 判断：

```bash
case "$SITE_NAME" in
  www.mumup.asia)
    K8S_APP_NAME="jenkins-test-pro-www"
    ;;
  demo.mumup.asia)
    K8S_APP_NAME="jenkins-test-pro-demo"
    ;;
  admin.mumup.asia)
    K8S_APP_NAME="jenkins-test-pro-admin"
    ;;
  *)
    echo "ERROR: unsupported SITE_NAME: $SITE_NAME"
    exit 1
    ;;
esac
```

## 9. Jenkinsfile 后续怎么改

你当前 Jenkinsfile 已有：

```text
ENABLE_NGINX_DEPLOY
SITE_NAME
```

建议新增一个部署目标参数：

```groovy
choice(
    name: 'DEPLOY_TARGET',
    choices: [
        'preview',
        'single-nginx',
        'kubernetes-ingress'
    ],
    description: '选择部署方式'
)
```

含义：

```text
preview:
  继续 npm run preview，访问 IP:5173

single-nginx:
  当前方案，发布 dist 到 /var/www/<SITE_NAME>/current

kubernetes-ingress:
  构建镜像，发布 Deployment/Service/Ingress
```

### 9.1 Jenkins 需要的环境变量

建议增加：

```groovy
environment {
    PROJECT_KEY = 'jenkins-test-pro'
    K8S_NAMESPACE = 'frontend'
    IMAGE_REGISTRY = 'your-registry.example.com/frontend'
}
```

### 9.2 Jenkins 需要的凭据

至少需要：

```text
镜像仓库账号密码
Kubernetes kubeconfig
```

Jenkins Credentials 建议：

```text
docker-registry-credential
kubeconfig-frontend
```

如果使用腾讯云 TCR，镜像仓库凭据就是腾讯云镜像仓库的用户名和密码。

如果 Jenkins 运行在 Kubernetes 集群内，也可以用 ServiceAccount，不一定需要 kubeconfig 文件。

### 9.3 Jenkins 部署 Kubernetes 的大致阶段

```groovy
stage('Build') {
    steps {
        sh '''
            set -e
            npm ci
            npm run build
        '''
    }
}

stage('Build Image') {
    when {
        expression { return params.DEPLOY_TARGET == 'kubernetes-ingress' }
    }
    steps {
        sh '''
            set -e
            IMAGE="${IMAGE_REGISTRY}/${PROJECT_KEY}:${PROJECT_KEY}-${BUILD_NUMBER}"
            docker build -t "$IMAGE" .
        '''
    }
}

stage('Push Image') {
    when {
        expression { return params.DEPLOY_TARGET == 'kubernetes-ingress' }
    }
    steps {
        sh '''
            set -e
            IMAGE="${IMAGE_REGISTRY}/${PROJECT_KEY}:${PROJECT_KEY}-${BUILD_NUMBER}"
            docker push "$IMAGE"
        '''
    }
}

stage('Deploy to Kubernetes') {
    when {
        expression { return params.DEPLOY_TARGET == 'kubernetes-ingress' }
    }
    steps {
        sh '''
            set -e

            case "$SITE_NAME" in
              www.mumup.asia)
                K8S_APP_NAME="${PROJECT_KEY}-www"
                ;;
              demo.mumup.asia)
                K8S_APP_NAME="${PROJECT_KEY}-demo"
                ;;
              admin.mumup.asia)
                K8S_APP_NAME="${PROJECT_KEY}-admin"
                ;;
              *)
                echo "ERROR: unsupported SITE_NAME: $SITE_NAME"
                exit 1
                ;;
            esac

            IMAGE="${IMAGE_REGISTRY}/${PROJECT_KEY}:${PROJECT_KEY}-${BUILD_NUMBER}"

            kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

            envsubst < k8s/deployment.yaml | kubectl apply -f -
            envsubst < k8s/service.yaml | kubectl apply -f -
            envsubst < k8s/ingress.yaml | kubectl apply -f -

            kubectl rollout status deployment/"$K8S_APP_NAME" -n "$K8S_NAMESPACE"
        '''
    }
}
```

## 10. Kubernetes YAML 模板化写法

为了让 `SITE_NAME` 可以在 Jenkins 里选择，建议把 k8s yaml 写成模板。

### 10.1 deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${K8S_APP_NAME}
  namespace: ${K8S_NAMESPACE}
  labels:
    app: ${K8S_APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${K8S_APP_NAME}
  template:
    metadata:
      labels:
        app: ${K8S_APP_NAME}
    spec:
      containers:
        - name: frontend
          image: ${IMAGE}
          imagePullPolicy: Always
          ports:
            - containerPort: 80
```

### 10.2 service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ${K8S_APP_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: ${K8S_APP_NAME}
  ports:
    - name: http
      port: 80
      targetPort: 80
```

### 10.3 ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${K8S_APP_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  ingressClassName: nginx
  rules:
    - host: ${SITE_NAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${K8S_APP_NAME}
                port:
                  number: 80
```

## 11. HTTPS 怎么处理

Ingress 场景下推荐使用 cert-manager。

基本链路：

```text
cert-manager
  -> 自动申请证书
  -> 写入 Kubernetes Secret
  -> Ingress 使用这个 Secret
```

如果你已经有泛域名证书：

```text
*.mumup.asia
```

也可以手动创建 Kubernetes TLS Secret：

```bash
kubectl create secret tls mumup-asia-wildcard-tls \
  --cert=fullchain.pem \
  --key=privkey.pem \
  -n frontend
```

Ingress 加上：

```yaml
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - demo.mumup.asia
      secretName: mumup-asia-wildcard-tls
  rules:
    - host: demo.mumup.asia
```

如果用泛域名证书，同一个 Secret 可以给多个二级域名复用。

## 12. ExternalDNS 是否现在就要做

不建议你第一阶段就做 ExternalDNS。

原因：

```text
1. 你配置 *.mumup.asia 泛解析后，已经不需要每个二级域名单独加 DNS。
2. ExternalDNS 接腾讯云需要额外 Provider/Webhook。
3. ExternalDNS 需要腾讯云 DNS API 权限，安全和权限配置更复杂。
```

推荐顺序：

```text
阶段一：单机 Nginx + 泛解析
阶段二：Kubernetes ingress-nginx + 泛解析
阶段三：ExternalDNS 自动管理腾讯云 DNS
```

也就是说，Ingress 可以先上，ExternalDNS 可以以后再上。

## 13. 从当前项目迁移的推荐路线

### 阶段一：保留当前方案

继续使用：

```text
Jenkins -> dist -> /var/www/<SITE_NAME>/current
```

同时在腾讯云 DNS 配：

```text
*.mumup.asia -> 服务器公网 IP
```

这个阶段最少变动，适合你现在继续跑项目。

### 阶段二：准备 Kubernetes 基础设施

完成：

```text
Kubernetes 集群
ingress-nginx
镜像仓库
Jenkins kubectl 权限
Jenkins docker build/push 权限
```

### 阶段三：项目新增容器化文件

新增：

```text
Dockerfile
nginx/default.conf
k8s/deployment.yaml
k8s/service.yaml
k8s/ingress.yaml
```

先手动验证：

```bash
npm ci
npm run build
docker build -t jenkins-test-pro:local .
docker run --rm -p 8080:80 jenkins-test-pro:local
```

访问：

```text
http://127.0.0.1:8080
```

### 阶段四：Jenkins 增加 kubernetes-ingress 部署分支

保留现有：

```text
preview
single-nginx
```

新增：

```text
kubernetes-ingress
```

这样你可以逐步切换，不会一下子把当前部署方式替换掉。

### 阶段五：把 DNS 指向 ingress-nginx

等 Kubernetes 部署验证成功后，把：

```text
*.mumup.asia
```

从原来的服务器公网 IP 改到：

```text
ingress-nginx 入口公网 IP
```

如果你希望单机 Nginx 和 Ingress 并行一段时间，可以临时用不同子域名：

```text
www.mumup.asia       -> 单机 Nginx
k8s-www.mumup.asia   -> ingress-nginx
k8s-demo.mumup.asia  -> ingress-nginx
```

验证没问题后，再把正式域名切过去。

## 14. 常见排查命令

### 14.1 DNS 是否解析正确

```bash
nslookup demo.mumup.asia
```

结果应该是 ingress-nginx 入口 IP。

### 14.2 Ingress 是否创建

```bash
kubectl get ingress -n frontend
kubectl describe ingress jenkins-test-pro-demo -n frontend
```

### 14.3 Service 是否存在

```bash
kubectl get svc -n frontend
kubectl describe svc jenkins-test-pro-demo -n frontend
```

### 14.4 Pod 是否正常

```bash
kubectl get pods -n frontend
kubectl describe pod <pod-name> -n frontend
kubectl logs <pod-name> -n frontend
```

### 14.5 Deployment 是否完成发布

```bash
kubectl rollout status deployment/jenkins-test-pro-demo -n frontend
```

### 14.6 ingress-nginx 日志

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
```

### 14.7 绕过 DNS 测试 Host 转发

如果 DNS 还没生效，可以用：

```bash
curl -H "Host: demo.mumup.asia" http://INGRESS_IP/
```

如果这个能访问，说明 Ingress 转发是通的，问题在 DNS。

## 15. 常见问题

### 15.1 域名解析对了，但页面打不开

检查：

```bash
kubectl get ingress -n frontend
kubectl get svc -n frontend
kubectl get pods -n frontend
```

通常是 Service selector 和 Deployment label 对不上。

### 15.2 Ingress 没有 ADDRESS

执行：

```bash
kubectl get ingressclass
kubectl get svc -n ingress-nginx
```

确认：

```text
ingressClassName: nginx
```

和集群里的 IngressClass 名称一致。

### 15.3 页面刷新 404

容器内 Nginx 必须有：

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

这对 Vue Router history 模式很重要。

### 15.4 每次发布后页面还是旧的

检查镜像 tag 是否变化。

不要长期使用：

```text
latest
```

推荐：

```text
jenkins-test-pro-${BUILD_NUMBER}
```

同时 Deployment 里的 image 要更新到新 tag。

### 15.5 Jenkins 不能执行 kubectl

检查 Jenkins 机器：

```bash
kubectl get nodes
kubectl get namespace frontend
```

如果本机可以，Jenkins 不可以，通常是 Jenkins 用户没有 kubeconfig。

## 16. 当前项目的最终建议

你现在最适合的路线是：

```text
第一步：
继续使用当前单机 Nginx 方案，配好 *.mumup.asia 泛解析。

第二步：
准备 Kubernetes 集群和 ingress-nginx。

第三步：
新增 Dockerfile、nginx/default.conf、k8s/*.yaml。

第四步：
Jenkinsfile 新增 DEPLOY_TARGET，下拉选择 preview、single-nginx、kubernetes-ingress。

第五步：
先用 k8s-demo.mumup.asia 测试 Ingress，不直接动正式 www.mumup.asia。

第六步：
测试稳定后，把正式域名切到 ingress-nginx。
```

这样迁移风险最低，当前能跑的部署方式不会被打断。

## 17. 参考资料

- Kubernetes Ingress 官方文档：https://kubernetes.io/docs/concepts/services-networking/ingress/
- ExternalDNS 官方文档：https://kubernetes-sigs.github.io/external-dns/
- ExternalDNS GitHub：https://github.com/kubernetes-sigs/external-dns
- ingress-nginx Helm Chart：https://github.com/kubernetes/ingress-nginx
