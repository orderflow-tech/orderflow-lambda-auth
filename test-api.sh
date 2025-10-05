#!/bin/bash
# Script de teste automatizado para OrderFlow Lambda Auth

echo "🧪 Testando API OrderFlow Auth"
echo "================================"
echo ""

# Obter URL da API do Terraform
cd terraform
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)

if [ -z "$API_URL" ]; then
  echo "❌ Erro: Não foi possível obter a URL da API"
  echo "Execute: cd terraform && terraform output"
  exit 1
fi

cd ..

echo "📍 API URL: $API_URL"
echo ""

# Usar CPF válido para teste (CPF fictício mas válido)
CPF="11144477735"

echo "📋 CPF de teste: $CPF"
echo ""

# Teste 1: Autenticar (cria usuário se não existir)
echo "1️⃣  Teste: Criar usuário (SignUp)"
echo "-----------------------------------"
SIGNUP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/auth" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"signup\",
    \"cpf\": \"$CPF\",
    \"password\": \"Senha@123\"
  }")

HTTP_CODE=$(echo "$SIGNUP_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$SIGNUP_RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
  echo "✅ SignUp bem-sucedido!"
else
  echo "❌ SignUp falhou!"
fi
echo ""

# Aguardar um pouco
sleep 2

# Teste 2: SignIn
echo "2️⃣  Teste: Fazer login (SignIn)"
echo "--------------------------------"
SIGNIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/auth" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"signin\",
    \"cpf\": \"$CPF\",
    \"password\": \"Senha@123\"
  }")

HTTP_CODE=$(echo "$SIGNIN_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$SIGNIN_RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✅ SignIn bem-sucedido!"
  
  # Extrair tokens (requer jq)
  if command -v jq &> /dev/null; then
    ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.accessToken // empty')
    REFRESH_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.refreshToken // empty')
    
    if [ -n "$ACCESS_TOKEN" ]; then
      echo "🔑 Access Token: ${ACCESS_TOKEN:0:50}..."
    fi
    if [ -n "$REFRESH_TOKEN" ]; then
      echo "🔄 Refresh Token: ${REFRESH_TOKEN:0:50}..."
    fi
  fi
else
  echo "❌ SignIn falhou!"
  REFRESH_TOKEN=""
fi
echo ""

# Teste 3: Refresh Token (se disponível)
if [ -n "$REFRESH_TOKEN" ]; then
  sleep 2
  
  echo "3️⃣  Teste: Renovar token (Refresh)"
  echo "-----------------------------------"
  REFRESH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/auth" \
    -H "Content-Type: application/json" \
    -d "{
      \"action\": \"refresh\",
      \"refreshToken\": \"$REFRESH_TOKEN\"
    }")
  
  HTTP_CODE=$(echo "$REFRESH_RESPONSE" | tail -n1)
  RESPONSE_BODY=$(echo "$REFRESH_RESPONSE" | head -n-1)
  
  echo "HTTP Status: $HTTP_CODE"
  echo "Response: $RESPONSE_BODY"
  
  if [ "$HTTP_CODE" -eq 200 ]; then
    echo "✅ Refresh bem-sucedido!"
  else
    echo "❌ Refresh falhou!"
  fi
  echo ""
fi

# Teste 4: SignIn com credenciais erradas
echo "4️⃣  Teste: Login com senha incorreta (deve falhar)"
echo "---------------------------------------------------"
WRONG_SIGNIN=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/auth" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"signin\",
    \"cpf\": \"$CPF\",
    \"password\": \"SenhaErrada@123\"
  }")

HTTP_CODE=$(echo "$WRONG_SIGNIN" | tail -n1)
RESPONSE_BODY=$(echo "$WRONG_SIGNIN" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"

if [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ]; then
  echo "✅ Erro esperado recebido corretamente!"
else
  echo "⚠️  Código de status inesperado (esperado 401 ou 403)"
fi
echo ""

echo "================================"
echo "✅ Testes concluídos!"
echo ""
echo "💡 Dicas:"
echo "  - Ver logs: aws logs tail /aws/lambda/orderflow-auth-dev --follow"
echo "  - Ver usuários: aws cognito-idp list-users --user-pool-id \$(cd terraform && terraform output -raw user_pool_id)"
echo "  - Ver outputs: cd terraform && terraform output"
