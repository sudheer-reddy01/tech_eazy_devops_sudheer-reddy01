#!/bin/bash

STAGE=$1
CONFIG_FILE="${STAGE}_config.sh"

if [[ -z "$STAGE" || ! -f "$CONFIG_FILE" ]]; then
  echo "❌ Please provide a valid stage (e.g., dev or prod). Missing config file: $CONFIG_FILE"
  exit 1
fi

echo "🌱 Loading environment variables..."
export $(grep -v '^#' .env | xargs)

source "$CONFIG_FILE"

echo "🚀 Launching EC2 instance for $STAGE..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"

echo "⏳ Waiting for instance to be in 'running' state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "✅ Instance is running at $PUBLIC_IP"
echo "⏱ Waiting 90 seconds for setup..."
sleep 90

echo "⚙️ Setting up application on EC2..."

ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << EOF
  sudo apt update -y
  sudo apt install -y git openjdk-17-jdk maven

  git clone "$GIT_REPO"
  cd test-repo-for-devops

  mvn clean package

  sudo nohup java -jar target/*.jar --server.port=$APP_PORT > app.log 2>&1 &
  sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port $APP_PORT
EOF

echo "🔍 Testing app at http://$PUBLIC_IP/hello"
for i in {1..10}; do
  if curl -s --max-time 5 "http://$PUBLIC_IP/hello" | grep -q "Hello"; then
    echo "✅ App is up and running!"
    echo "🌐 Your app is live! Access it at: http://$PUBLIC_IP/hello"
    break
  else
    echo "❌ Attempt $i/10 failed. Retrying in 10 seconds..."
    sleep 10
  fi

  if [ "$i" -eq 10 ]; then
    echo "❌ App failed to respond after $i attempts."
    exit 1
  fi
done

