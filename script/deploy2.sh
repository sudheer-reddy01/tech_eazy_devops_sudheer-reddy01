#!/bin/bash

# ------------ LOAD CONFIG ----------------
if [ ! -f .env ]; then
    echo "[ERROR] .env file not found. Please create one with required variables."
    exit 1
fi

source .env

echo "[DEBUG] Showing first line of key file:"
head -n 1 "$KEY_PATH_ENV" | cat -A


# ------------ VALIDATE ENV VARIABLES ----------------
if [[ -z "$KEY_PATH_ENV" || -z "$SSH_USER" || -z "$REPO_URL" || -z "$JAR_NAME" ]]; then
    echo "[ERROR] One or more required variables are missing."
    echo "KEY_PATH_ENV='$KEY_PATH_ENV'"
    echo "SSH_USER='$SSH_USER'"
    echo "REPO_URL='$REPO_URL'"
    echo "JAR_NAME='$JAR_NAME'"
    exit 1
fi

# ------------ VALIDATE SSH KEY ----------------
if [ ! -f "$KEY_PATH_ENV" ]; then
    echo "[ERROR] SSH key not found at: $KEY_PATH_ENV"
    exit 1
fi

# Convert CRLF to LF if needed
if grep -q $'\r' "$KEY_PATH_ENV"; then
    echo "[INFO] Converting Windows line endings in SSH key..."
    sed -i 's/\r$//' "$KEY_PATH_ENV"
fi

# Fix permissions if too open
chmod 400 "$KEY_PATH_ENV"

# Check if it's a valid PEM RSA key
if ! head -n 1 "$KEY_PATH_ENV" | grep -q "BEGIN RSA PRIVATE KEY"; then
    echo "[ERROR] SSH key is not in valid RSA PEM format."
    exit 1
fi

echo "[INFO] SSH key validation passed."

set -e

echo "[INFO] Fetching values from Terraform state..."
EC2_IP=$(terraform -chdir=../terraform output -raw ec2_public_ip)
BUCKET_NAME=$(terraform -chdir=../terraform output -raw bucket_name)

echo "[INFO] EC2 IP: $EC2_IP"
echo "[INFO] S3 Bucket: $BUCKET_NAME"

# ----- CREATE REMOTE INSTALL SCRIPT -----
cat <<EOF > remote_install.sh
#!/bin/bash
set -e

echo "[REMOTE] Updating system and installing Java 21 & Maven..."
sudo apt-get update -y
sudo apt-get install -y openjdk-21-jdk maven awscli

echo "[REMOTE] Java version:"
java -version
echo "[REMOTE] Maven version:"
mvn -version

echo "[REMOTE] Cloning and building the app..."
git clone $REPO_URL appdir
cd appdir
mvn clean package

echo "[REMOTE] Running the application..."
nohup java -jar target/$JAR_NAME > /tmp/app.log 2>&1 &

echo "[REMOTE] App deployed successfully."

# Set up upload_logs.sh script for manual log upload
echo "[REMOTE] Creating upload_logs.sh script..."
cat <<SHUTDOWN | sudo tee /usr/local/bin/upload_logs.sh > /dev/null
#!/bin/bash
echo "[UPLOAD] Uploading logs to S3 bucket: $BUCKET_NAME ..."
aws s3 cp /var/log/cloud-init.log s3://$BUCKET_NAME/logs/\$(hostname)-cloud-init.log
aws s3 cp /tmp/app.log s3://$BUCKET_NAME/logs/\$(hostname)-app.log
echo "[UPLOAD] Logs uploaded to S3 successfully."
SHUTDOWN

sudo chmod +x /usr/local/bin/upload_logs.sh
EOF

chmod +x remote_install.sh

echo "[INFO] Copying install script to EC2..."
scp -i "$KEY_PATH_ENV" -o StrictHostKeyChecking=no remote_install.sh "$SSH_USER@$EC2_IP:/home/$SSH_USER/"

echo "[INFO] Running install script on EC2..."
ssh -i "$KEY_PATH_ENV" -o StrictHostKeyChecking=no "$SSH_USER@$EC2_IP" "chmod +x remote_install.sh && sudo ./remote_install.sh"

echo "[INFO] Waiting for app to start (10s)..."
sleep 10

echo "[INFO] Testing if app is reachable at: http://$EC2_IP/hello"
curl -s --connect-timeout 5 "http://$EC2_IP/hello" || echo "[WARNING] App may not be reachable yet."

# ----- UPLOAD LOGS DIRECTLY (NO SHUTDOWN) -----
echo "[ACTION] Uploading logs to S3..."
ssh -i "$KEY_PATH_ENV" -o StrictHostKeyChecking=no "$SSH_USER@$EC2_IP" "sudo /usr/local/bin/upload_logs.sh"
echo "[INFO] Logs uploaded successfully. EC2 instance remains running."

echo "[DONE] Workflow complete."
