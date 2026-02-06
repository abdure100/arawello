#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."

echo "=== 1. Building image (linux/amd64) ==="
docker build --platform linux/amd64 -t openclaw-gateway:latest -f Dockerfile .

echo "=== 2. Tagging for ECR ==="
docker tag openclaw-gateway:latest 291529891373.dkr.ecr.us-east-1.amazonaws.com/openclaw-gateway:latest

echo "=== 3. Logging in to ECR ==="
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 291529891373.dkr.ecr.us-east-1.amazonaws.com

echo "=== 4. Pushing to ECR ==="
docker push 291529891373.dkr.ecr.us-east-1.amazonaws.com/openclaw-gateway:latest

echo "=== Done ==="
