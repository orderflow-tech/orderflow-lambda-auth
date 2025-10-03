terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket         = "orderflow-terraform-state"
    key            = "lambda-auth/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "OrderFlow"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "Lambda-Auth"
    }
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "orderflow" {
  name = "${var.project_name}-user-pool-${var.environment}"

  # Configuração de atributos personalizados
  schema {
    name                = "cpf"
    attribute_data_type = "String"
    mutable             = false
    required            = false

    string_attribute_constraints {
      min_length = 11
      max_length = 11
    }
  }

  # Políticas de senha (não será usada diretamente, mas é necessária)
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Configuração de auto-verificação
  auto_verified_attributes = []

  # Configuração de recuperação de conta
  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  # Configuração de exclusão de usuário
  deletion_protection = var.environment == "production" ? "ACTIVE" : "INACTIVE"

  tags = {
    Name = "${var.project_name}-user-pool-${var.environment}"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "orderflow" {
  name         = "${var.project_name}-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.orderflow.id

  # Configuração de fluxos de autenticação
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Token validity
  access_token_validity  = 1  # 1 hora
  id_token_validity      = 1  # 1 hora
  refresh_token_validity = 30 # 30 dias

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevenir segredo do cliente (não necessário para este caso de uso)
  generate_secret = false
}

# IAM Role para Lambda
resource "aws_iam_role" "lambda_auth" {
  name = "${var.project_name}-lambda-auth-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-auth-role-${var.environment}"
  }
}

# Policy para Lambda acessar Cognito
resource "aws_iam_role_policy" "lambda_cognito" {
  name = "${var.project_name}-lambda-cognito-policy-${var.environment}"
  role = aws_iam_role.lambda_auth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminSetUserPassword",
          "cognito-idp:AdminInitiateAuth",
          "cognito-idp:ListUsers"
        ]
        Resource = aws_cognito_user_pool.orderflow.arn
      }
    ]
  })
}

# Attach AWS managed policy para logs do CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_auth.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group para Lambda
resource "aws_cloudwatch_log_group" "lambda_auth" {
  name              = "/aws/lambda/${var.project_name}-auth-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-lambda-auth-logs-${var.environment}"
  }
}

# Secrets Manager para JWT Secret
resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "${var.project_name}-jwt-secret-${var.environment}"
  description = "JWT secret key for OrderFlow authentication"

  tags = {
    Name = "${var.project_name}-jwt-secret-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret
}

# Policy para Lambda acessar Secrets Manager
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.project_name}-lambda-secrets-policy-${var.environment}"
  role = aws_iam_role.lambda_auth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.jwt_secret.arn
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "auth" {
  filename         = var.lambda_zip_path
  function_name    = "${var.project_name}-auth-${var.environment}"
  role             = aws_iam_role.lambda_auth.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  runtime          = "nodejs20.x"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.orderflow.id
      CLIENT_ID    = aws_cognito_user_pool_client.orderflow.id
      JWT_SECRET   = var.jwt_secret
      AWS_REGION   = var.aws_region
      ENVIRONMENT  = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_auth,
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy.lambda_cognito,
    aws_iam_role_policy.lambda_secrets
  ]

  tags = {
    Name = "${var.project_name}-auth-lambda-${var.environment}"
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "orderflow" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "API Gateway for OrderFlow authentication"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-api-gateway-${var.environment}"
  }
}

# API Gateway Resource
resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.orderflow.id
  parent_id   = aws_api_gateway_rest_api.orderflow.root_resource_id
  path_part   = "auth"
}

# API Gateway Method
resource "aws_api_gateway_method" "auth_post" {
  rest_api_id   = aws_api_gateway_rest_api.orderflow.id
  resource_id   = aws_api_gateway_resource.auth.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.orderflow.id
  resource_id             = aws_api_gateway_resource.auth.id
  http_method             = aws_api_gateway_method.auth_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth.invoke_arn
}

# Lambda Permission para API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.orderflow.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "orderflow" {
  rest_api_id = aws_api_gateway_rest_api.orderflow.id

  depends_on = [
    aws_api_gateway_integration.lambda
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "orderflow" {
  deployment_id = aws_api_gateway_deployment.orderflow.id
  rest_api_id   = aws_api_gateway_rest_api.orderflow.id
  stage_name    = var.environment

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage-${var.environment}"
  }
}

# CloudWatch Log Group para API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-api-gateway-logs-${var.environment}"
  }
}

# CORS Configuration
resource "aws_api_gateway_method" "auth_options" {
  rest_api_id   = aws_api_gateway_rest_api.orderflow.id
  resource_id   = aws_api_gateway_resource.auth.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "auth_options" {
  rest_api_id = aws_api_gateway_rest_api.orderflow.id
  resource_id = aws_api_gateway_resource.auth.id
  http_method = aws_api_gateway_method.auth_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "auth_options" {
  rest_api_id = aws_api_gateway_rest_api.orderflow.id
  resource_id = aws_api_gateway_resource.auth.id
  http_method = aws_api_gateway_method.auth_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "auth_options" {
  rest_api_id = aws_api_gateway_rest_api.orderflow.id
  resource_id = aws_api_gateway_resource.auth.id
  http_method = aws_api_gateway_method.auth_options.http_method
  status_code = aws_api_gateway_method_response.auth_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.auth_options
  ]
}
