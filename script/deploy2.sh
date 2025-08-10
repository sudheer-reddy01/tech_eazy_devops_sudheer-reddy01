#!/bin/bash
set -e

# ------------ CONFIG ------------
TF_STATE="./terraform/terraform.tfstate"
KEY_PATH="./script/mykey.pem"
SSH_USER="ubuntu"
GITHUB_REPO="https://github.com/Trainings-TechEazy/test-repo-for-devops"
APP_JAR="target/hellomvc-0.0.1-SNAPSHOT.jar"
EXPECTED_MSG="Hello from Spring MVC!"

# ------------ FETCH VALUES FROM TERRAFORM ------------
echo "[INFO] Fetching values from Terraform state..."
if [ ! -f "$TF_STATE" ]; then
    echo "[ERROR] Terraform state file not found at $TF_STATE"
    exit 1
fi

EC2_IP=$(jq -r '.resources[] | select(.type=="aws_instance") | .instances[0].attributes.public_ip' "$TF_STATE")
S3_BUCKET=$(jq -r '.resources[] | select(.type=="aws_s3_bucket") | .instances[0].attributes.bucket' "$TF_STATE")

if [[ -z "$EC2_IP" || -z "$S3_BUCKET" || "$EC2_IP" == "null" || "$S3_BUCKET" == "null" ]]; then
    echo "[ERROR] Could not fetch EC2 IP or S3 bucket from Terraform state."
    exit 1
fi

echo "[INFO] EC2 IP: $EC2_IP"
echo "[INFO] S3 Bucket: $S3_BUCKET"

# ------------ SSH KEY FIX ------------
if [ ! -f "$KEY_PATH" ]; then
    echo "[ERROR] SSH key file not found at: $KEY_PATH"
    exit 1
fi
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

echo "[EC2] Running application..."
sudo pkill -f "java -jar" || true
nohup java -jar target/hellomvc-0.0.1-SNAPSHOT.jar > app.log 2>&1 &
EOF

# ------------ TEST APP ------------
echo "[INFO] Waiting for app to start..."
sleep 20

RESPONSE=$(curl -s "http://$EC2_IP/hello" || true)
if [[ "$RESPONSE" == "$EXPECTED_MSG" ]]; then
    echo "[SUCCESS] App is reachable and returned expected message!"
else
    echo "[ERROR] App test failed! Got: $RESPONSE"
    exit 1
fi

# ------------ UPLOAD LOGS TO S3 ------------
echo "[INFO] Uploading logs to S3..."
ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" \
    "aws s3 cp app.log s3://$S3_BUCKET/app.log --acl private"

echo "[INFO] Deployment complete."
