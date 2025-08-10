#!/bin/bash

# ------------ LOAD CONFIG ----------------
if [ ! -f .env ]; then
    echo "[ERROR] .env file not found. Please create one with required variables."
    exit 1
fi

source .env

# ------------ CREATE SSH KEY FILE IF MISSING ----------------
if [ ! -f "$KEY_PATH_ENV" ]; then
    if [ -n "$PEM_KEY" ]; then
        echo "[INFO] SSH key file not found. Creating from PEM_KEY environment variable..."
        mkdir -p "$(dirname "$KEY_PATH_ENV")"
        echo "$PEM_KEY" > "$KEY_PATH_ENV"
        sed -i 's/\r$//' "$KEY_PATH_ENV"  # Remove CRLF if present
    else
        echo "[ERROR] SSH key file not found at: $KEY_PATH_ENV"
        echo "[ERROR] And PEM_KEY environment variable is empty."
        exit 1
    fi
fi

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
# Fix permissions
chmod 400 "$KEY_PATH_ENV"

# Debug first line
echo "[DEBUG] Showing first line of key file:"
head -n 1 "$KEY_PATH_ENV" | cat -A

# Check format
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
sudo apt-get install -y openjdk-21-jdk ma
