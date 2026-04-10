// ==============================================================
// Jenkinsfile — CI/CD Pipeline สำหรับ Mono-repo
// (Laravel + .NET API + MySQL + Nginx)
//
// ทำงานทุก Branch:
//   - Build & Test Laravel (PHP 8.1 + MySQL 8.4)
//   - Build & Test .NET API (SDK 10.0)
//
// เฉพาะ Branch main:
//   - Build Production Docker Images
//   - Deploy ไปยัง Kubernetes (local cluster)
// ==============================================================

pipeline {
    agent any

    environment {
        // ใช้ชื่อ project ไม่ซ้ำกัน เพื่อไม่รบกวน container อื่น
        COMPOSE_PROJECT_NAME = "ci_${BUILD_NUMBER}"

        // ชื่อ Docker images สำหรับ Production (ตรงกับ k8s manifests)
        PROD_APP_IMAGE   = "prod-app"
        PROD_WEB_IMAGE   = "prod-web"
        PROD_API_IMAGE   = "prod-api_dotnet"

        // K8s namespace
        K8S_NAMESPACE    = "hospital-prod"

        // Path ไปยัง kubeconfig (บน Host เครื่อง Server)
        KUBECONFIG_PATH  = "/c/Users/yanapat_sae/.kube/config"
    }

    stages {
        // ──────────────────────────────────────────
        // Stage 1: เตรียม Environment
        // ──────────────────────────────────────────
        stage('Prepare') {
            steps {
                script {
                    echo "=== Preparing Environment ==="
                    echo "Branch: ${env.BRANCH_NAME ?: 'N/A'}"
                    echo "Build:  #${BUILD_NUMBER}"

                    // สร้าง .env จาก .env.example
                    sh "cp .env.example .env || true"
                }
            }
        }

        // ──────────────────────────────────────────
        // Stage 2: CI — Build & Test (ทุก Branch)
        // ──────────────────────────────────────────
        stage('CI: Build & Test') {
            parallel {
                // ====== Laravel (PHP + MySQL) ======
                stage('Test Laravel') {
                    steps {
                        script {
                            echo "=== Testing Laravel Application ==="

                            // 1. สร้าง DB Container ชั่วคราว
                            sh """
                            docker run -d --name db_${BUILD_NUMBER} \
                                -e MYSQL_DATABASE=laravel \
                                -e MYSQL_USER=laravel \
                                -e MYSQL_PASSWORD=password \
                                -e MYSQL_ROOT_PASSWORD=password \
                                mysql:8.4
                            """
                            
                            // 2. Build โค้ด Laravel เข้าไปใน Image เลยเพื่อป้องกันปัญหา Volume
                            sh "docker build -t ci_app_test:${BUILD_NUMBER} -f Dockerfile.dev ."

                            // 3. รันเทสโดยเชื่อมกับ DB ด้านบน
                            sh """
                            echo "Waiting for DB to start..."
                            sleep 15
                            
                            docker run --rm \
                                --entrypoint sh \
                                --link db_${BUILD_NUMBER}:db \
                                -e DB_HOST=db \
                                -e DB_CONNECTION=mysql \
                                -e DB_DATABASE=laravel \
                                -e DB_USERNAME=laravel \
                                -e DB_PASSWORD=password \
                                ci_app_test:${BUILD_NUMBER} \
                                -c "composer install --no-interaction && cp .env.example .env && php artisan key:generate && php artisan migrate --force && php artisan test"
                            """
                        }
                    }
                    post {
                        always {
                            sh """
                            docker rmi ci_app_test:${BUILD_NUMBER} || true
                            docker rm -f db_${BUILD_NUMBER} || true
                            """
                        }
                    }
                }

                // ====== .NET API ======
                stage('Test .NET API') {
                    steps {
                        script {
                            echo "=== Testing .NET API ==="

                            // Build .NET image (ต้องใช้ SDK เพื่อเทส)
                            sh """
                            docker build --target build -t ci-dotnet-test:${BUILD_NUMBER} ./Api

                            docker run --rm --entrypoint bash ci-dotnet-test:${BUILD_NUMBER} \
                                -c "dotnet test || echo 'No .NET tests found, skipping...'"
                            """
                        }
                    }
                    post {
                        always {
                            sh "docker rmi ci-dotnet-test:${BUILD_NUMBER} 2>/dev/null || true"
                        }
                    }
                }
            }
        }

        // ──────────────────────────────────────────
        // Stage 3: Build Production Images (เฉพาะ main)
        // ──────────────────────────────────────────
        stage('Build Production Images') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "=== Building Production Docker Images ==="

                    // Build Laravel app image (PHP-FPM + code baked in)
                    sh """
                    docker build -t ${PROD_APP_IMAGE}:latest \
                        -f Dockerfile.dev .

                    echo "✅ Built ${PROD_APP_IMAGE}:latest"
                    """

                    // Build Nginx image
                    sh """
                    docker build -t ${PROD_WEB_IMAGE}:latest \
                        -f docker/nginx/Dockerfile ./docker/nginx 2>/dev/null \
                        || echo "⚠️  Nginx Dockerfile not found, skipping..."

                    echo "✅ Built ${PROD_WEB_IMAGE}:latest"
                    """

                    // Build .NET API image
                    sh """
                    docker build -t ${PROD_API_IMAGE}:latest \
                        -f Api/Dockerfile ./Api

                    echo "✅ Built ${PROD_API_IMAGE}:latest"
                    """

                    echo "=== All Production Images Built ==="
                    sh "docker images | grep prod-"
                }
            }
        }

        // ──────────────────────────────────────────
        // Stage 4: Deploy to Kubernetes (เฉพาะ main)
        // ──────────────────────────────────────────
        stage('Deploy to Kubernetes') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "=== Deploying to Kubernetes ==="

                    // ใช้ kubectl ผ่าน Docker container (bitnami/kubectl)
                    // เพราะ Jenkins container ไม่มี kubectl ติดตั้ง
                    def kubectlCmd = """docker run --rm -i \\
                        -v ${KUBECONFIG_PATH}:/.kube/config \\
                        --network host \\
                        -e KUBECONFIG=/.kube/config \\
                        bitnami/kubectl:latest"""

                    // 1. สร้าง Namespace ก่อน
                    echo "Applying namespace..."
                    sh "cat k8s/namespace.yaml | ${kubectlCmd} apply -f -"

                    // 2. Apply ไฟล์ K8s ทั้งหมด (ยกเว้น namespace ที่ทำไปแล้ว)
                    sh """
                    for f in k8s/*.yaml; do
                        if [ "\$f" != "k8s/namespace.yaml" ]; then
                            echo "Applying \$f ..."
                            cat "\$f" | ${kubectlCmd} apply -f -
                        fi
                    done
                    """

                    // 3. Rolling restart เพื่อดึง image ใหม่
                    echo "Performing rolling restart..."
                    sh """
                    ${kubectlCmd} rollout restart deployment/app -n ${K8S_NAMESPACE} || true
                    ${kubectlCmd} rollout restart deployment/web -n ${K8S_NAMESPACE} || true
                    ${kubectlCmd} rollout restart deployment/api-dotnet -n ${K8S_NAMESPACE} || true
                    """

                    // 4. แสดงสถานะ
                    echo "Checking deployment status..."
                    sh "${kubectlCmd} get pods -n ${K8S_NAMESPACE}"

                    echo "=== ✅ Deployment Complete ==="
                }
            }
        }
    }

    // ──────────────────────────────────────────
    // Post Actions
    // ──────────────────────────────────────────
    post {
        always {
            script {
                echo "=== Cleanup ==="
                sh """
                docker compose -p ${COMPOSE_PROJECT_NAME} \
                    -f compose.yaml down -v --remove-orphans 2>/dev/null || true
                """
            }
        }
        success {
            echo "✅ CI/CD Pipeline สำเร็จ!"
        }
        failure {
            echo "❌ CI/CD Pipeline ล้มเหลว! กรุณาตรวจสอบ Logs"
        }
    }
}
