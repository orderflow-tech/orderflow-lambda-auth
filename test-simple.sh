#!/bin/bash
# Script de teste simplificado para OrderFlow Lambda Auth

echo "🧪 Testando API OrderFlow Auth"
echo "================================"
echo ""

# Obter URL da API
cd terraform
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)
cd ..

echo "📍 API URL: $API_URL"
echo ""

# CPF válido para teste
CPF="11144477735"

# Teste 1: Autenticação
echo "1️⃣  Teste: Autenticação com CPF válido"
echo "---------------------------------------"
echo "Chamando: POST $API_URL"
echo "Payload: {\"cpf\":\"$CPF\"}"
echo ""

RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "{\"cpf\":\"$CPF\"}")

echo "✅ Resposta:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
echo ""

# Teste 2: CPF inválido
echo "2️⃣  Teste: CPF inválido (deve retornar erro)"
echo "----------------------------------------------"
RESPONSE2=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{"cpf":"12345678901"}')

echo "✅ Resposta:"
echo "$RESPONSE2" | jq '.' 2>/dev/null || echo "$RESPONSE2"
echo ""

# Teste 3: Sem CPF
echo "3️⃣  Teste: Sem CPF (deve retornar erro)"
echo "----------------------------------------"
RESPONSE3=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{}')

echo "✅ Resposta:"
echo "$RESPONSE3" | jq '.' 2>/dev/null || echo "$RESPONSE3"
echo ""

# Mostrar informações do Cognito
echo "================================"
echo "📊 Informações do Cognito"
echo "================================"
USER_POOL_ID=$(cd terraform && terraform output -raw user_pool_id)
echo "User Pool ID: $USER_POOL_ID"
echo ""
echo "Usuários cadastrados:"
aws cognito-idp list-users --user-pool-id "$USER_POOL_ID" --query 'Users[*].[Username,UserStatus]' --output table

echo ""
echo "✅ Testes concluídos!"
echo ""
echo "💡 Comandos úteis:"
echo "  - Ver logs: aws logs tail /aws/lambda/orderflow-auth-dev --follow"
echo "  - Ver outputs: cd terraform && terraform output"
