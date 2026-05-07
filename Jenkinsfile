pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        APP_HOST = '0.0.0.0'
        APP_PORT = '5173'
        JENKINS_NODE_COOKIE = 'dontKillMe'
        EXTRA_NODE_PATH = '/opt/homebrew/bin:/usr/local/bin'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install') {
            steps {
                sh '''
                    set -e
                    export PATH="${EXTRA_NODE_PATH}:$PATH"

                    if ! command -v node >/dev/null 2>&1; then
                        echo "ERROR: node command not found. Install Node.js on this Jenkins agent or configure the Jenkins NodeJS tool."
                        echo "Current PATH: $PATH"
                        exit 127
                    fi

                    if ! command -v npm >/dev/null 2>&1; then
                        echo "ERROR: npm command not found. Install npm on this Jenkins agent or configure the Jenkins NodeJS tool."
                        echo "Current PATH: $PATH"
                        exit 127
                    fi

                    node -v
                    npm -v
                    npm ci
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    set -e
                    export PATH="${EXTRA_NODE_PATH}:$PATH"
                    npm run build
                '''
            }
        }

        stage('Start Frontend') {
            steps {
                sh '''
                    set -e
                    export PATH="${EXTRA_NODE_PATH}:$PATH"

                    if command -v lsof >/dev/null 2>&1; then
                        OLD_PID=$(lsof -ti tcp:${APP_PORT} || true)
                        if [ -n "$OLD_PID" ]; then
                            kill $OLD_PID || true
                            sleep 2
                        fi
                    fi

                    nohup npm run preview -- --host ${APP_HOST} --port ${APP_PORT} > frontend.log 2>&1 &
                    sleep 5

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
            archiveArtifacts artifacts: 'frontend.log,dist/**', allowEmptyArchive: true
        }
    }
}
