pipeline {
    // 使用任意可用 Jenkins 节点执行流水线。
    agent any

    options {
        // 在控制台日志里打印时间，方便排查每个阶段耗时。
        timestamps()

        // 禁止同一个任务并发构建，避免多个构建同时占用 5173 端口。
        disableConcurrentBuilds()
    }

    tools {
        // 这里的名字必须和 Jenkins -> Manage Jenkins -> Tools 里配置的 NodeJS 名称一致。
        nodejs 'Node22'
    }

    environment {
        // Vite preview 对外监听地址，0.0.0.0 表示允许从虚拟机外部访问。
        APP_HOST = '0.0.0.0'

        // 前端预览服务端口，浏览器访问 http://虚拟机IP:5173/。
        APP_PORT = '5173'

        // 让 Jenkins 不要在构建结束时杀掉后台启动的 preview 进程。
        JENKINS_NODE_COOKIE = 'dontKillMe'
    }

    stages {
        stage('Checkout') {
            steps {
                // 从 Jenkins 任务配置的 GitHub 仓库拉取代码。
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    set -e

                    echo "Workspace: $WORKSPACE"
                    echo "User: $(id)"
                    echo "Node path: $(command -v node)"
                    echo "NPM path: $(command -v npm)"

                    node -v
                    npm -v

                    # 使用 package-lock.json 精确安装依赖，适合 CI/CD 构建。
                    npm ci
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    set -e

                    # 当前仅在 Jenkins 机器上预览，使用本地资源路径构建。
                    npm run build
                '''
            }
        }

        // stage('Upload Assets to COS') {
        //     steps {
        //         // COS 密钥从 Jenkins 凭据读取，避免提交到 GitHub 仓库。
        //         withCredentials([
        //             string(credentialsId: 'cos-secret-id', variable: 'COS_SECRET_ID'),
        //             string(credentialsId: 'cos-secret-key', variable: 'COS_SECRET_KEY')
        //         ]) {
        //             sh '''
        //                 set -e
        //
        //                 # 上传 dist/assets 到腾讯云 COS。
        //                 npm run upload:cos
        //             '''
        //         }
        //     }
        // }

        stage('Start Frontend Preview') {
            steps {
                sh '''
                    set -e

                    # 如果 5173 端口已有旧的 preview 进程，先停止旧进程再启动新版本。
                    if command -v lsof >/dev/null 2>&1; then
                        OLD_PID=$(lsof -ti tcp:${APP_PORT} || true)
                        if [ -n "$OLD_PID" ]; then
                            kill $OLD_PID || true
                            sleep 2
                        fi
                    fi

                    # 后台启动 Vite preview，并把日志写到 frontend.log。
                    nohup npm run preview -- --host ${APP_HOST} --port ${APP_PORT} > frontend.log 2>&1 &
                    sleep 5

                    # 简单健康检查，确认本机能访问前端页面。
                    curl -f http://127.0.0.1:${APP_PORT}/
                '''
            }
        }
    }

    post {
        success {
            echo "Frontend service is running on http://<JENKINS_NODE_IP>:${APP_PORT}/"
        }

        always {
            // 保存构建产物和前端启动日志，方便在 Jenkins 页面下载或排查。
            archiveArtifacts artifacts: 'frontend.log,dist/**', allowEmptyArchive: true
        }
    }
}
