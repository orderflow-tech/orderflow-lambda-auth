# Guia de Testes - OrderFlow Lambda Auth

## 📋 Pré-requisitos

Após executar `terraform apply`, você terá os seguintes outputs importantes:
- `api_gateway_url`: URL base da sua API
- `user_pool_id`: ID do Cognito User Pool
- `user_pool_client_id`: ID do Client do Cognito

Execute para ver os outputs:
```bash
cd terraform
terraform output
```

## 🧪 Testes da API

### 1. Criar um usuário (Sign Up)

```bash
# Substitua <API_URL> pelo output api_gateway_url
curl -X POST <API_URL>/auth \
  -H "Content-Type: application/json" \
  -d '{
    "action": "signup",
    "cpf": "12345678901",
    "password": "Senha@123"
  }'
```

**Resposta esperada:**
```json
{
  "message": "Usuário criado com sucesso",
  "userId": "xxx-xxx-xxx"
}
```

### 2. Fazer Login (Sign In)

```bash
curl -X POST <API_URL>/auth \
  -H "Content-Type: application/json" \
  -d '{
    "action": "signin",
    "cpf": "12345678901",
    "password": "Senha@123"
  }'
```

**Resposta esperada:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "idToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": 3600
}
```

### 3. Refresh Token

```bash
curl -X POST <API_URL>/auth \
  -H "Content-Type: application/json" \
  -d '{
    "action": "refresh",
    "refreshToken": "<REFRESH_TOKEN_DO_LOGIN>"
  }'
```

## 🔍 Testes no Console AWS

### Verificar Cognito User Pool

```bash
# Listar usuários criados
aws cognito-idp list-users \
  --user-pool-id <USER_POOL_ID> \
  --region us-east-1
```

### Verificar Logs do Lambda

```bash
# Ver logs recentes
aws logs tail /aws/lambda/orderflow-auth-dev --follow
```

### Verificar API Gateway

```bash
# Testar endpoint
aws apigateway test-invoke-method \
  --rest-api-id <API_GATEWAY_ID> \
  --resource-id <RESOURCE_ID> \
  --http-method POST \
  --path-with-query-string /auth \
  --body '{"action":"signin","cpf":"12345678901","password":"Senha@123"}'
```

## 📝 Script de Teste Completo

Crie um arquivo `test-api.sh`:

```bash
#!/bin/bash

# Obter URL da API do Terraform
API_URL=$(cd terraform && terraform output -raw api_gateway_url)

echo "🧪 Testando API OrderFlow Auth"
echo "API URL: $API_URL"
echo ""

# Teste 1: SignUp
echo "1️⃣ Criando usuário..."
SIGNUP_RESPONSE=$(curl -s -X POST "$API_URL/auth" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "signup",
    "cpf": "12345678901",
    "password": "Senha@123"
  }')
echo "Resposta: $SIGNUP_RESPONSE"
echo ""

# Teste 2: SignIn
echo "2️⃣ Fazendo login..."
SIGNIN_RESPONSE=$(curl -s -X POST "$API_URL/auth" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "signin",
    "cpf": "12345678901",
    "password": "Senha@123"
  }')
echo "Resposta: $SIGNIN_RESPONSE"
echo ""

# Extrair tokens
ACCESS_TOKEN=$(echo $SIGNIN_RESPONSE | jq -r '.accessToken')
REFRESH_TOKEN=$(echo $SIGNIN_RESPONSE | jq -r '.refreshToken')

echo "✅ Access Token: ${ACCESS_TOKEN:0:50}..."
echo "✅ Refresh Token: ${REFRESH_TOKEN:0:50}..."
echo ""

# Teste 3: Refresh Token
echo "3️⃣ Renovando token..."
REFRESH_RESPONSE=$(curl -s -X POST "$API_URL/auth" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"refresh\",
    \"refreshToken\": \"$REFRESH_TOKEN\"
  }")
echo "Resposta: $REFRESH_RESPONSE"
echo ""

echo "✅ Testes concluídos!"
```

Execute:
```bash
chmod +x test-api.sh
./test-api.sh
```

## 🐛 Troubleshooting

### Erro 500 - Internal Server Error
- Verifique os logs do Lambda: `aws logs tail /aws/lambda/orderflow-auth-dev --follow`
- Verifique se o JWT_SECRET está configurado corretamente

### Erro 403 - Forbidden
- Verifique se as permissões IAM estão corretas
- Verifique se o Lambda tem permissão para acessar o Cognito

### Usuário já existe
- Delete o usuário via Console AWS ou CLI:
```bash
aws cognito-idp admin-delete-user \
  --user-pool-id <USER_POOL_ID> \
  --username "12345678901"
```

## 📊 Monitoramento

### CloudWatch Metrics
- Acesse: AWS Console → CloudWatch → Metrics
- Namespace: `AWS/Lambda` e `AWS/ApiGateway`

### CloudWatch Logs
```bash
# Lambda logs
aws logs tail /aws/lambda/orderflow-auth-dev --follow

# API Gateway logs
aws logs tail /aws/apigateway/orderflow-dev --follow
```

## 🧹 Limpeza

Para destruir toda a infraestrutura:
```bash
cd terraform
terraform destroy -auto-approve
```

**Atenção:** Isso vai deletar todos os recursos criados!
