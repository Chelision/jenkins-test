# 前端项目通过 ingress-nginx 自动域名访问方案

## 目标

把当前前端项目从 Jenkins 机器上的 `vite preview :5173`，逐步升级成下面这种部署方式：

```text
用户访问域名
  -> DNS 解析到 ingress-nginx 入口 IP
  -> ingress-nginx 按域名转发
  -> Kubernetes Service
  -> 前端 nginx 容器
  -> dist 静态资源
```

最终效果：

```text
https://jenkins-test.example.com
https://dev-jenkins-test.example.com
https://test-jenkins-test.example.com
```

不同项目、不同环境可以用不同域名访问。

## 推荐路线

先做 **泛域名解析 + ingress-nginx**，跑通后再考虑 **ExternalDNS 自动创建 DNS 记录**。

原因：

- 泛域名解析实现最简单，只需要配置一次 DNS。
- Jenkins 只需要负责构建镜像并更新 Kubernetes 资源。
- 后续项目增多后，再引入 ExternalDNS 可以减少手动 DNS 管理。

## 阶段一：准备 Kubernetes ingress-nginx

### 1. 确认集群已有 ingress-nginx

在 Kubernetes 集群执行：

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

你需要看到类似服务：

```text
ingress-nginx-controller
```

如果还没有安装 ingress-nginx，可以使用 Helm：

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### 2. 获取 ingress-nginx 入口地址

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

如果是云服务器 LoadBalancer，会看到 `EXTERNAL-IP`。

如果是自建集群，可能需要自己把公网 Nginx、云负载均衡或服务器端口转发到 ingress-nginx。

记录入口 IP：

```text
INGRESS_IP=你的 ingress-nginx 入口 IP
```

## 阶段二：配置域名解析

假设你的根域名是：

```text
example.com
```

建议新增一个专门用于测试部署的二级域名：

```text
*.apps.example.com
```

DNS 记录：

```text
类型：A
主机记录：*.apps
记录值：ingress-nginx 入口 IP
```

配置后，下面这些域名都会解析到同一个 ingress-nginx：

```text
jenkins-test.apps.example.com
dev-jenkins-test.apps.example.com
test-jenkins-test.apps.example.com
```

然后由 Kubernetes Ingress 根据 `host` 决定转发到哪个前端服务。

本地临时测试也可以先改 hosts：

```text
192.168.64.3 jenkins-test.apps.example.com
```

## 阶段三：把前端构建成 nginx 镜像

当前 Jenkins 是执行：

```bash
npm run build
npm run preview
```

接入 Kubernetes 后，建议改成：

```text
npm run build
-> 生成 dist
-> 用 nginx 镜像托管 dist
-> 部署到 Kubernetes
```

### 1. 添加 Dockerfile

在项目根目录添加：

```dockerfile
FROM nginx:1.27-alpine

COPY dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### 2. 本地验证镜像

```bash
npm ci
npm run build
docker build -t jenkins-test-frontend:local .
docker run --rm -p 8080:80 jenkins-test-frontend:local
```

浏览器访问：

```text
http://127.0.0.1:8080
```

## 阶段四：创建 Kubernetes 部署文件

建议新增目录：

```text
k8s/
```

### 1. Deployment

`k8s/deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins-test-frontend
  namespace: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins-test-frontend
  template:
    metadata:
      labels:
        app: jenkins-test-frontend
    spec:
      containers:
        - name: frontend
          image: your-registry.example.com/jenkins-test-frontend:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 80
```

### 2. Service

`k8s/service.yaml`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: jenkins-test-frontend
  namespace: frontend
spec:
  type: ClusterIP
  selector:
    app: jenkins-test-frontend
  ports:
    - name: http
      port: 80
      targetPort: 80
```

### 3. Ingress

`k8s/ingress.yaml`：

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

### 4. 创建 namespace

```bash
kubectl create namespace frontend
```

## 阶段五：手动部署验证

先不要接 Jenkins，手动验证 Kubernetes 部署链路。

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

检查资源：

```bash
kubectl get pods -n frontend
kubectl get svc -n frontend
kubectl get ingress -n frontend
```

访问：

```text
http://jenkins-test.apps.example.com
```

如果打不开，按顺序检查：

```bash
nslookup jenkins-test.apps.example.com
kubectl describe ingress jenkins-test-frontend -n frontend
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
kubectl logs -n frontend deploy/jenkins-test-frontend
```

## 阶段六：改造 Jenkins 自动部署

Jenkins 后续不再启动：

```bash
npm run preview
```

而是执行：

```text
npm ci
npm run build
docker build
docker push
kubectl apply
kubectl set image
```

### Jenkins 需要准备的凭据

建议在 Jenkins Credentials 中配置：

```text
镜像仓库账号密码
kubeconfig
```

### Jenkinsfile 思路

```groovy
pipeline {
    agent any

    parameters {
        string(name: 'IMAGE_TAG', defaultValue: 'latest', description: '镜像标签')
        string(name: 'APP_DOMAIN', defaultValue: 'jenkins-test.apps.example.com', description: '访问域名')
    }

    environment {
        IMAGE_NAME = 'your-registry.example.com/jenkins-test-frontend'
        K8S_NAMESPACE = 'frontend'
        DEPLOYMENT_NAME = 'jenkins-test-frontend'
    }

    stages {
        stage('Install Dependencies') {
            steps {
                sh 'npm ci'
            }
        }

        stage('Build Frontend') {
            steps {
                sh 'npm run build'
            }
        }

        stage('Build Docker Image') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
            }
        }

        stage('Push Docker Image') {
            steps {
                sh 'docker push ${IMAGE_NAME}:${IMAGE_TAG}'
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl apply -f k8s/ingress.yaml
                    kubectl set image deployment/${DEPLOYMENT_NAME} frontend=${IMAGE_NAME}:${IMAGE_TAG} -n ${K8S_NAMESPACE}
                    kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }
    }
}
```

实际落地时，`IMAGE_TAG` 建议使用 Git commit：

```bash
git rev-parse --short HEAD
```

这样每次部署都能追踪到具体代码版本。

## 阶段七：多个项目和多个环境的域名规则

建议统一域名规则：

```text
项目名.环境.apps.example.com
```

例如：

```text
jenkins-test.dev.apps.example.com
jenkins-test.test.apps.example.com
jenkins-test.prod.apps.example.com
admin.dev.apps.example.com
portal.dev.apps.example.com
```

也可以简单一点：

```text
dev-jenkins-test.apps.example.com
test-jenkins-test.apps.example.com
prod-jenkins-test.apps.example.com
```

每个项目对应一组 Kubernetes 资源：

```text
Deployment
Service
Ingress
```

每个域名对应一条 Ingress rule。

## 阶段八：升级为 ExternalDNS 自动解析

当项目越来越多，不想手动维护 DNS，可以引入 ExternalDNS。

ExternalDNS 的作用：

```text
监听 Kubernetes Ingress
-> 读取 host
-> 自动在 DNS 服务商创建 A/CNAME 记录
```

适用场景：

- 你有很多项目。
- 每个项目都需要自动生成域名。
- 你使用 Cloudflare、DNSPod、阿里云 DNS 等支持 API 的 DNS 服务商。

接入后，Jenkins 只需要创建 Ingress：

```yaml
rules:
  - host: jenkins-test.apps.example.com
```

ExternalDNS 会自动创建 DNS 记录。

注意：如果已经使用泛域名解析，短期内可以不接 ExternalDNS。

## 阶段九：HTTPS 证书

如果需要 HTTPS，推荐接入 cert-manager。

最终结构：

```text
cert-manager
  -> 自动申请证书
  -> 写入 Kubernetes Secret
  -> Ingress 使用 TLS
```

Ingress 示例：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-test-frontend
  namespace: frontend
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - jenkins-test.apps.example.com
      secretName: jenkins-test-frontend-tls
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

## 建议实施顺序

1. 准备 Kubernetes 集群和 ingress-nginx。
2. 配置 `*.apps.example.com` 泛域名到 ingress-nginx 入口 IP。
3. 给前端项目添加 Dockerfile。
4. 手动构建前端镜像并推送到镜像仓库。
5. 创建 Deployment、Service、Ingress。
6. 手动 `kubectl apply` 验证域名能访问。
7. 改造 Jenkinsfile，让 Jenkins 构建镜像并部署 Kubernetes。
8. 多项目复用同一套模板，只换项目名、镜像名、域名。
9. 项目增多后再接入 ExternalDNS。
10. 需要 HTTPS 时接入 cert-manager。

## 当前项目改造建议

当前项目现在可以先保留 Jenkins 的 `vite preview` 流程用于临时预览。

正式接入 ingress-nginx 时，建议新增一套 Kubernetes 部署流程，不再使用：

```bash
npm run preview
```

改为：

```bash
npm run build
docker build
docker push
kubectl apply
```

这样部署出来的前端服务更稳定，也更适合多个项目、多个域名统一管理。
