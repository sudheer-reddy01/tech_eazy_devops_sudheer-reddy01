#!/bin/bash
set -e

# ------------ CONFIG ------------
TF_DIR="../terraform"  # Adjusted since workflow runs from script/
KEY_PATH="./mykey.pem"
SSH_USER="ubuntu"
GITHUB_REPO="https://github.com/Trainings-TechEazy/test-repo-for-devops"
APP_JAR="target/hellomvc-0.0.1-SNAPSHOT.jar"
EXPECTED_MSG="Hello from Spring MVC!"

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

ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" bash << 'EOF'
set -e
echo "[EC2] Updating packages..."
sudo apt-get update -y

echo "[EC2] Installing Java 21, Maven, Git, AWS CLI..."
sudo apt-get install -y openjdk-21-jdk maven git awscli curl

echo "[EC2] Cloning repository..."
rm -rf test-repo-for-devops
git clone https://github.com/Trainings-TechEazy/test-repo-for-devops
cd test-repo-for-devops

echo "[EC2] Building application..."
mvn clean package -DskipTests

echo "[EC2] Running application on port 80..."
sudo pkill -f "java -jar" || true
nohup sudo java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=80 > app.log 2>&1 &
EOF

# ------------ TEST APP WITH RETRIES ------------
echo "[INFO] Waiting for app to start..."
for i in {1..10}; do
    RESPONSE=$(curl -s "http://$EC2_IP/hello" || true)
    if [[ "$RESPONSE" == "$EXPECTED_MSG" ]]; then
        echo "[SUCCESS] App is reachable and returned expected message!"
        break
    fi
    echo "[INFO] Attempt $i/10 failed. Retrying in 10s..."
    sleep 10
done

if [[ "$RESPONSE" != "$EXPECTED_MSG" ]]; then
    echo "[ERROR] App test failed! Got: $RESPONSE"
    exit 1
fi

# ------------ UPLOAD LOGS TO S3 ------------
echo "[INFO] Uploading logs to S3..."
ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" \
    "aws s3 cp app.log s3://$S3_BUCKET/app-\$(date +%F-%H%M%S).log --acl private"

echo "[INFO] Deployment complete."
