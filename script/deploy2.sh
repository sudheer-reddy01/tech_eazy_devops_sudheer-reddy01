#!/bin/bash
set -e

# ------------ CONFIG ------------
TF_DIR="../terraform"  # Path to Terraform folder
KEY_PATH="./mykey.pem"
SSH_USER="ubuntu"
GITHUB_REPO="https://github.com/Trainings-TechEazy/test-repo-for-devops"
APP_JAR="target/hellomvc-0.0.1-SNAPSHOT.jar"
EXPECTED_MSG="Hello from Spring MVC!"
APP_ENDPOINT="/hello"   # The app endpoint to check

# ------------ FETCH VALUES FROM TERRAFORM ------------
echo "[INFO] Fetching values from Terraform outputs..."
pushd "$TF_DIR" >/dev/null
EC2_IP=$(terraform output -raw ec2_public_ip)
S3_BUCKET=$(terraform output -raw bucket_name)
popd >/dev/null

if [[ -z "$EC2_IP" || -z "$S3_BUCKET" ]]; then
    echo "[ERROR] Could not fetch EC2 IP or S3 bucket from Terraform outputs."
    exit 1
fi

echo "[INFO] EC2 IP: $EC2_IP"
echo "[INFO] S3 Bucket: $S3_BUCKET"

# ------------ SSH KEY FIX ------------
chmod 400 "$KEY_PATH"

# ------------ INSTALL & DEPLOY APP ON EC2 ------------
echo "[INFO] Deploying application to EC2..."

ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" bash << EOF
set -e
echo "[EC2] Updating packages..."
sudo apt-get update -y

echo "[EC2] Installing Java 21, Maven, Git, AWS CLI..."
sudo apt-get install -y openjdk-21-jdk maven git awscli curl

echo "[EC2] Cloning repository..."
rm -rf test-repo-for-devops
git clone $GITHUB_REPO
cd test-repo-for-devops

echo "[EC2] Building application..."
mvn clean package -DskipTests

echo "[EC2] Running application on port 80..."
sudo pkill -f "java -jar" || true
nohup sudo java -jar $APP_JAR --server.port=80 > /tmp/app.log 2>&1 &
EOF

# ------------ WAIT UNTIL APP IS RUNNING ------------
echo "[INFO] Waiting for app to be ready..."
MAX_RETRIES=15
for i in $(seq 1 $MAX_RETRIES); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$EC2_IP$APP_ENDPOINT" || true)
    if [[ "$STATUS" == "200" ]]; then
        echo "[INFO] App is up and responding on port 80."
        break
    fi
    echo "[INFO] Waiting for app to start... ($i/$MAX_RETRIES)"
    sleep 5
done

if [[ "$STATUS" != "200" ]]; then
    echo "[ERROR] App did not start in expected time."
    exit 1
fi

# ------------ UPLOAD LOGS TO S3 ------------
echo "[INFO] Uploading logs to S3..."
ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" \
    "aws s3 cp /tmp/app.log s3://$S3_BUCKET/app-\$(date +%F-%H%M%S).log --acl private"

echo "[INFO] Deployment complete."
