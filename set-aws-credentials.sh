#!/bin/bash
# Script para configurar credenciais AWS do LAB
# Substitua os valores abaixo pelas credenciais do seu AWS LAB
# Executar: source ./set-aws-credentials.sh

export AWS_ACCESS_KEY_ID=TROCAR_PELA_SUA
export AWS_SECRET_ACCESS_KEY=TROCAR_PELA_SUA
export AWS_SESSION_TOKEN=TROCAR_PELA_SUA
export AWS_REGION="us-east-1"

# Gere o secret em outro terminal: openssl rand -base64 32
export TF_VAR_jwt_secret="TROCAR_PELA_GERADA"

echo "✅ Credenciais AWS configuradas!"
echo "Região: $AWS_REGION"
echo "Access Key: ${AWS_ACCESS_KEY_ID:0:20}..."
