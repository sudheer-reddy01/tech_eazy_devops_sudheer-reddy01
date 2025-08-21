#!/bin/bash
set -e

# ---------- Stage selection ----------
STAGE="${1:-dev}"
CONFIG_FILE="configs/${STAGE}.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "[INFO] Deploying stage: $STAGE"
echo "[INFO] Loading config from $CONFIG_FILE"

# ---------- Load values from config.json ----------
TF_DIR=$(jq -r '.TF_DIR' "$CONFIG_FILE")
KEY_PATH=$(jq -r '.KEY_PATH' "$CONFIG_FILE")
SSH_USER=$(jq -r '.SSH_USER' "$CONFIG_FILE")
GITHUB_REPO=$(jq -r '.GITHUB_REPO' "$CONFIG_FILE")
APP_JAR=$(jq -r '.APP_JAR' "$CONFIG_FILE")
EXPECTED_MSG=$(jq -r '.EXPECTED_MSG' "$CONFIG_FILE")
APP_ENDPOINT=$(jq -r '.APP_ENDPOINT' "$CONFIG_FILE")

# ---------- Fetch Terraform Outputs ----------
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

# ---------- SSH Key Permission Fix ----------
chmod 400 "$KEY_PATH"

# ---------- Deploy to EC2 ----------
echo "[INFO] Deploying application to EC2..."

ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" bash << EOF
set -e
echo "[EC2] Updating packages..."
sudo apt-get update -y

echo "[EC2] Installing Java 21, Maven, Git, AWS CLI..."
sudo apt-get install -y openjdk-21-jdk maven git awscli curl

echo "[EC2] Cloning repository..."
rm -rf repo
git clone "$GITHUB_REPO" repo
cd repo

echo "[EC2] Building application..."
mvn clean package -DskipTests

echo "[EC2] Running application on port 80..."
sudo pkill -f "java -jar" || true
nohup sudo java -jar "$APP_JAR" --server.port=80 > /tmp/app.log 2>&1 &
EOF

# ---------- Wait for App Startup ----------
echo "[INFO] Waiting for app to be ready..."
MAX_RETRIES=15
for i in $(seq 1 $MAX_RETRIES); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$EC2_IP$APP_ENDPOINT" || true)
    if [[ "$STATUS" == "200" ]]; then
        echo "[INFO] App is up and responding."
        break
    fi
    echo "[INFO] Waiting... ($i/$MAX_RETRIES)"
    sleep 5
done

if [[ "$STATUS" != "200" ]]; then
    echo "[ERROR] App did not start in expected time."
    exit 1
fi

# ---------- Upload Logs to Stage-Specific S3 Path ----------
echo "[INFO] Uploading logs to S3..."
STAGE_LOG_PATH="logs/${STAGE}/app-$(date +%F-%H%M%S).log"

ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "$SSH_USER@$EC2_IP" \
    "aws s3 cp /tmp/app.log s3://$S3_BUCKET/$STAGE_LOG_PATH --acl private"

echo "[INFO] Logs uploaded to s3://$S3_BUCKET/$STAGE_LOG_PATH"
echo "[INFO] ✅ Deployment to '$STAGE' complete."
