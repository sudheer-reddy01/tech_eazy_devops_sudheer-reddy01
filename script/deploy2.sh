#!/bin/bash

# ------------ LOAD CONFIG ----------------
if [ ! -f .env ]; then
    echo "[ERROR] .env file not found. Please create one with required variables."
    exit 1
fi

source .env

# ------------ VALIDATE ----------------
if [[ -z "$KEY_PATH" || -z "$SSH_USER" || -z "$REPO_URL" || -z "$JAR_NAME" ]]; then
    echo "[ERROR] One or more required variables are missing in .env"
    exit 1
fi

set -e

echo "[INFO] Fetching values from Terraform state..."

EC2_IP=$(terraform output -raw ec2_public_ip)
BUCKET_NAME=$(terraform output -raw bucket_name)

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
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no remote_install.sh "$SSH_USER@$EC2_IP:/home/$SSH_USER/"

echo "[INFO] Running install script on EC2..."
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$EC2_IP" "chmod +x remote_install.sh && sudo ./remote_install.sh"

echo "[INFO] Waiting for app to start (10s)..."
sleep 10

echo "[INFO] Testing if app is reachable at: http://$EC2_IP/hello"
curl -s --connect-timeout 5 "http://$EC2_IP/hello" || echo "[WARNING] App may not be reachable yet."

# ---------------- Shutdown Prompt ----------------
read -p "Do you want to shut down the EC2 instance now? [yes/no]: " CONFIRM
if [[ "${CONFIRM,,}" == "yes" ]]; then
    echo "[ACTION] Triggering log upload to S3 before shutdown..."
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$EC2_IP" "sudo /usr/local/bin/upload_logs.sh"
    echo "[INFO] Logs uploaded. Now shutting down the instance..."
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$EC2_IP" "sudo shutdown -h now"
else
    echo "[INFO] Shutdown aborted. Instance is still running."
fi

echo "[DONE] Workflow complete."
