# OrderFlow Lambda Auth

Este repositório contém a função AWS Lambda responsável pela autenticação de clientes do sistema OrderFlow via CPF, integrada com AWS Cognito e API Gateway.

## Visão Geral

A função Lambda implementa um sistema de autenticação sem senha, onde os clientes se identificam apenas com o CPF. O fluxo utiliza JWT (JSON Web Tokens) para manter a sessão do usuário.

### Componentes Principais

- **AWS Lambda**: Função serverless que processa as requisições de autenticação
- **AWS Cognito**: Gerenciamento de usuários e autenticação
- **API Gateway**: Ponto de entrada para as requisições externas
- **AWS Secrets Manager**: Armazenamento seguro da chave JWT

## Arquitetura

```
Cliente → API Gateway → Lambda Function → Cognito
                            ↓
                       JWT Token
```

### Fluxo de Autenticação

1. Cliente envia CPF para o endpoint `/auth` do API Gateway
2. API Gateway invoca a função Lambda
3. Lambda valida o formato do CPF
4. Lambda verifica se o usuário existe no Cognito
5. Se não existir, cria um novo usuário
6. Lambda gera um token JWT
7. Token é retornado ao cliente para uso em requisições subsequentes

## Estrutura do Projeto

```
orderflow-lambda-auth/
├── src/
│   └── index.ts              # Código principal da função Lambda
├── terraform/
│   ├── main.tf               # Recursos da infraestrutura
│   ├── variables.tf          # Variáveis do Terraform
│   └── outputs.tf            # Outputs da infraestrutura
├── .github/
│   └── workflows/
│       └── deploy.yml        # Pipeline CI/CD
├── package.json              # Dependências do projeto
├── tsconfig.json             # Configuração TypeScript
└── README.md                 # Este arquivo
```

## Pré-requisitos

- Node.js 20.x ou superior
- AWS CLI configurado
- Terraform 1.7.0 ou superior
- Conta AWS com permissões adequadas

## Configuração Local

### 1. Instalar Dependências

```bash
npm install
```

### 2. Compilar o Código

```bash
npm run build
```

### 3. Criar o Pacote de Deploy

```bash
npm run package
```

Isso criará um arquivo `lambda.zip` pronto para deploy.

## Deploy com Terraform

### 1. Configurar Variáveis

Crie um arquivo `terraform/terraform.tfvars`:

```hcl
aws_region       = "us-east-1"
environment      = "dev"
project_name     = "orderflow"
lambda_zip_path  = "../lambda.zip"
jwt_secret       = "your-secure-jwt-secret-key-min-32-chars"
log_retention_days = 7
```

### 2. Inicializar Terraform

```bash
cd terraform
terraform init
```

### 3. Planejar o Deploy

```bash
terraform plan
```

### 4. Aplicar a Infraestrutura

```bash
terraform apply
```

### 5. Obter a URL do API Gateway

```bash
terraform output api_gateway_url
```

## CI/CD com GitHub Actions

O projeto inclui um pipeline completo de CI/CD que é acionado automaticamente:

### Triggers

- **Push** para `main` ou `develop`: Deploy automático
- **Pull Request** para `main` ou `develop`: Lint, test e plan

### Secrets Necessários

Configure os seguintes secrets no GitHub:

- `AWS_ACCESS_KEY_ID`: Chave de acesso AWS
- `AWS_SECRET_ACCESS_KEY`: Chave secreta AWS
- `JWT_SECRET`: Chave secreta para geração de JWT (mínimo 32 caracteres)

### Jobs do Pipeline

1. **lint-and-test**: Executa linter e testes
2. **build**: Compila e cria o pacote Lambda
3. **terraform-plan**: Executa terraform plan (apenas em PRs)
4. **deploy**: Aplica a infraestrutura (apenas em push para main/develop)
5. **security-scan**: Executa scan de segurança com Trivy

## Uso da API

### Endpoint de Autenticação

**POST** `/auth`

#### Request

```json
{
  "cpf": "12345678901"
}
```

#### Response (Sucesso)

```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "userId": "12345678901",
  "message": "Autenticação realizada com sucesso"
}
```

#### Response (Erro)

```json
{
  "success": false,
  "message": "CPF inválido"
}
```

### Exemplo com cURL

```bash
curl -X POST https://your-api-gateway-url/dev/auth \
  -H "Content-Type: application/json" \
  -d '{"cpf":"12345678901"}'
```

### Exemplo com JavaScript

```javascript
const response = await fetch('https://your-api-gateway-url/dev/auth', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ cpf: '12345678901' }),
});

const data = await response.json();
console.log(data.token);
```

## Segurança

### Boas Práticas Implementadas

- ✅ Validação rigorosa de CPF
- ✅ JWT com expiração de 24 horas
- ✅ Secrets armazenados no AWS Secrets Manager
- ✅ IAM roles com princípio do menor privilégio
- ✅ Logs centralizados no CloudWatch
- ✅ CORS configurado
- ✅ Scan de vulnerabilidades no CI/CD
- ✅ Proteção de branches main/master

### Recomendações Adicionais

- Implementar rate limiting no API Gateway
- Adicionar WAF para proteção contra ataques
- Implementar rotação automática do JWT secret
- Configurar alertas no CloudWatch para falhas

## Monitoramento

### CloudWatch Logs

Os logs são armazenados em:
- Lambda: `/aws/lambda/orderflow-auth-{environment}`
- API Gateway: `/aws/apigateway/orderflow-{environment}`

### Métricas Importantes

- Invocações da Lambda
- Erros e throttling
- Latência do API Gateway
- Taxa de autenticações bem-sucedidas

## Desenvolvimento

### Executar Linter

```bash
npm run lint
```

### Executar Testes

```bash
npm test
```

### Formatar Código

```bash
npm run format
```

## Troubleshooting

### Erro: "CPF inválido"

Verifique se o CPF possui 11 dígitos e passa na validação de dígitos verificadores.

### Erro: "Falha ao criar usuário"

Verifique as permissões IAM da função Lambda para acessar o Cognito.

### Erro: "Internal server error"

Consulte os logs no CloudWatch para detalhes do erro.

## Contribuindo

1. Crie uma branch a partir de `develop`
2. Faça suas alterações
3. Execute os testes e linter
4. Abra um Pull Request para `develop`
5. Aguarde a revisão e aprovação

## Licença

MIT

## Suporte

Para questões e suporte, abra uma issue no repositório.
