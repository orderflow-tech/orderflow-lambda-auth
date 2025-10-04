import {
  APIGatewayProxyEvent,
  APIGatewayProxyResult,
  Context,
} from 'aws-lambda';
import {
  CognitoIdentityProviderClient,
  AdminGetUserCommand,
  AdminCreateUserCommand,
  AdminSetUserPasswordCommand,
  MessageActionType,
} from '@aws-sdk/client-cognito-identity-provider';
import * as jwt from 'jsonwebtoken';

const cognitoClient = new CognitoIdentityProviderClient({
  region: process.env.COGNITO_REGION || process.env.AWS_REGION || 'us-east-1',
});

const USER_POOL_ID = process.env.USER_POOL_ID || '';
const JWT_SECRET = process.env.JWT_SECRET || 'default-secret-key';

interface AuthRequest {
  cpf: string;
}

interface AuthResponse {
  success: boolean;
  token?: string;
  message?: string;
  userId?: string;
}

/**
 * Valida o formato do CPF brasileiro
 * @param cpf - CPF a ser validado
 * @returns true se o CPF é válido, false caso contrário
 */
function isValidCPF(cpf: string): boolean {
  // Remove caracteres não numéricos
  const cleanCPF = cpf.replace(/\D/g, '');

  // Verifica se tem 11 dígitos
  if (cleanCPF.length !== 11) {
    return false;
  }

  // Verifica se todos os dígitos são iguais (CPF inválido)
  if (/^(\d)\1{10}$/.test(cleanCPF)) {
    return false;
  }

  // Validação dos dígitos verificadores
  let sum = 0;
  let remainder: number;

  // Valida primeiro dígito verificador
  for (let i = 1; i <= 9; i++) {
    sum += parseInt(cleanCPF.substring(i - 1, i)) * (11 - i);
  }
  remainder = (sum * 10) % 11;
  if (remainder === 10 || remainder === 11) {
    remainder = 0;
  }
  if (remainder !== parseInt(cleanCPF.substring(9, 10))) {
    return false;
  }

  // Valida segundo dígito verificador
  sum = 0;
  for (let i = 1; i <= 10; i++) {
    sum += parseInt(cleanCPF.substring(i - 1, i)) * (12 - i);
  }
  remainder = (sum * 10) % 11;
  if (remainder === 10 || remainder === 11) {
    remainder = 0;
  }
  if (remainder !== parseInt(cleanCPF.substring(10, 11))) {
    return false;
  }

  return true;
}

/**
 * Verifica se o usuário existe no Cognito
 * @param cpf - CPF do usuário
 * @returns true se o usuário existe, false caso contrário
 */
async function userExists(cpf: string): Promise<boolean> {
  try {
    const command = new AdminGetUserCommand({
      UserPoolId: USER_POOL_ID,
      Username: cpf,
    });

    await cognitoClient.send(command);
    return true;
  } catch (error: any) {
    if (error.name === 'UserNotFoundException') {
      return false;
    }
    throw error;
  }
}

/**
 * Cria um novo usuário no Cognito
 * @param cpf - CPF do usuário
 * @returns ID do usuário criado
 */
async function createUser(cpf: string): Promise<string> {
  try {
    // Cria o usuário
    const createCommand = new AdminCreateUserCommand({
      UserPoolId: USER_POOL_ID,
      Username: cpf,
      UserAttributes: [
        {
          Name: 'custom:cpf',
          Value: cpf,
        },
      ],
      MessageAction: MessageActionType.SUPPRESS, // Não envia email de boas-vindas
    });

    const createResponse = await cognitoClient.send(createCommand);

    // Define uma senha temporária (será substituída por autenticação sem senha)
    const tempPassword = `Temp@${Math.random().toString(36).slice(-8)}`;
    const setPasswordCommand = new AdminSetUserPasswordCommand({
      UserPoolId: USER_POOL_ID,
      Username: cpf,
      Password: tempPassword,
      Permanent: true,
    });

    await cognitoClient.send(setPasswordCommand);

    return createResponse.User?.Username || cpf;
  } catch (error: any) {
    console.error('Erro ao criar usuário:', error);
    throw new Error(`Falha ao criar usuário: ${error.message}`);
  }
}

/**
 * Gera um token JWT para o usuário
 * @param cpf - CPF do usuário
 * @param userId - ID do usuário no Cognito
 * @returns Token JWT
 */
function generateJWT(cpf: string, userId: string): string {
  const payload = {
    sub: userId,
    cpf: cpf,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600 * 24, // Expira em 24 horas
  };

  return jwt.sign(payload, JWT_SECRET, { algorithm: 'HS256' });
}

/**
 * Handler principal da função Lambda
 */
export const handler = async (
  event: APIGatewayProxyEvent,
  _context: Context
): Promise<APIGatewayProxyResult> => {
  console.log('Evento recebido:', JSON.stringify(event, null, 2));

  try {
    // Valida o corpo da requisição
    if (!event.body) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
        body: JSON.stringify({
          success: false,
          message: 'Corpo da requisição é obrigatório',
        } as AuthResponse),
      };
    }

    const body: AuthRequest = JSON.parse(event.body);

    // Valida o CPF
    if (!body.cpf) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
        body: JSON.stringify({
          success: false,
          message: 'CPF é obrigatório',
        } as AuthResponse),
      };
    }

    const cpf = body.cpf.replace(/\D/g, ''); // Remove caracteres não numéricos

    if (!isValidCPF(cpf)) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
        body: JSON.stringify({
          success: false,
          message: 'CPF inválido',
        } as AuthResponse),
      };
    }

    // Verifica se o usuário existe, senão cria
    let userId = cpf;
    const exists = await userExists(cpf);

    if (!exists) {
      console.log(`Usuário ${cpf} não encontrado. Criando novo usuário...`);
      userId = await createUser(cpf);
      console.log(`Usuário ${userId} criado com sucesso`);
    } else {
      console.log(`Usuário ${cpf} encontrado`);
    }

    // Gera o token JWT
    const token = generateJWT(cpf, userId);

    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
      body: JSON.stringify({
        success: true,
        token: token,
        userId: userId,
        message: 'Autenticação realizada com sucesso',
      } as AuthResponse),
    };
  } catch (error: any) {
    console.error('Erro ao processar autenticação:', error);

    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
      body: JSON.stringify({
        success: false,
        message: `Erro interno do servidor: ${error.message}`,
      } as AuthResponse),
    };
  }
};
