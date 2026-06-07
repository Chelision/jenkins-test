pipeline {
    // 使用任意可用 Jenkins 节点执行流水线。
    agent any

    options {
        // 在控制台日志里打印时间，方便排查每个阶段耗时。
        timestamps()

        // 禁止同一个任务并发构建，避免多个构建同时占用 5173 端口。
        disableConcurrentBuilds()
    }

    parameters {
        // 构建时通过下拉框选择要部署的 Git 分支。
        // 需要 Jenkins 安装 Git Parameter 插件，否则 gitParameter 参数无法识别。
        // Jenkins 任务配置里的 Pipeline -> SCM -> Branch Specifier 需要写成 */${BRANCH_NAME}。
        gitParameter(
            name: 'BRANCH_NAME',
            type: 'PT_BRANCH',
            branchFilter: 'origin/(.*)',
            defaultValue: 'main',
            selectedValue: 'DEFAULT',
            sortMode: 'ASCENDING_SMART',
            description: '请选择要部署的 Git 分支'
        )

        // 是否发布到服务器 Nginx 静态目录。
        // 默认关闭，先保留当前 vite preview 的访问方式；服务器 Nginx 和 sudo 权限配置好后再勾选。
        booleanParam(
            name: 'ENABLE_NGINX_DEPLOY',
            defaultValue: false,
            description: '是否把 dist 和 nginx/vhost/<域名>.conf 发布到服务器 Nginx'
        )

        // 当前项目要绑定的域名，同时对应 nginx/vhost/<SITE_NAME>.conf。
        // 新增可选项时，需要同步新增 nginx/vhost/<域名>.conf。
        choice(
            name: 'SITE_NAME',
            choices: [
                'www.mumup.asia',
                'demo.mumup.asia',
                'admin.mumup.asia'
            ],
            description: '要发布的域名，例如 www.mumup.asia、admin.mumup.asia'
        )

        // 构建时通过下拉框选择要部署的 Git Tag。
        // jenkins中也需要改为对应的tag部署而不是branch
        // 需要 Jenkins 安装 Git Parameter 插件。
        // Jenkins 任务配置里的 Pipeline -> SCM -> Branch Specifier 建议写成 refs/tags/${TAG_NAME}。
        // gitParameter(
        //     name: 'TAG_NAME',
        //     type: 'PT_TAG',
        //     tagFilter: '*',
        //     defaultValue: '',
        //     selectedValue: 'TOP',
        //     sortMode: 'DESCENDING_SMART',
        //     description: '请选择要部署的 Git Tag'
        // )
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

        // 当前仓库对应的项目标识，用于生成可追踪的发布版本目录。
        PROJECT_KEY = 'jenkins-test-pro'
    }

    stages {
        stage('Checkout') {
            steps {
                // 打印本次构建选择的分支，方便在 Jenkins 控制台日志里确认部署来源。
                echo "Deploy branch: ${params.BRANCH_NAME}"
                // 输出tagname
                // echo "Deploy tag: ${params.TAG_NAME}"

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

        stage('Deploy Static Files to Nginx') {
            when {
                expression { return params.ENABLE_NGINX_DEPLOY }
            }
            steps {
                sh '''
                    set -e

                    # 发布 dist 到 /var/www/<SITE_NAME>/releases/<BUILD_NUMBER>，并切换 current。
                    sudo SITE_NAME="${SITE_NAME}" PROJECT_KEY="${PROJECT_KEY}" RELEASE_ID="${PROJECT_KEY}-${BUILD_NUMBER}" ./scripts/deploy-nginx-static.sh
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
            when {
                expression { return !params.ENABLE_NGINX_DEPLOY }
            }
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
