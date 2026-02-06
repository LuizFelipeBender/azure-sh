# 🚀 Guia: Importar Contrato OpenAPI no AWS API Gateway

## 📋 Visão Geral

Este guia mostra como importar o contrato OpenAPI (`openapi-spec.yaml`) no AWS API Gateway e configurar a integração com sua Lambda.

---

## 🎯 Opção 1: Importar via AWS Console (Mais Fácil)

### Passo 1: Acessar API Gateway

1. Acesse o [AWS Console](https://console.aws.amazon.com)
2. Navegue para **API Gateway**
3. Clique em **Create API**

### Passo 2: Importar OpenAPI

1. Escolha **REST API** (não HTTP API)
2. Selecione **Import from OpenAPI 3**
3. Clique em **Upload** e selecione `openapi-spec.yaml`
4. Configure:
   - **API name:** Cases Management API
   - **Endpoint Type:** Regional
5. Clique em **Import**

### Passo 3: Configurar Integração Lambda

Para CADA método/rota:

1. Clique no método (ex: `POST /cases`)
2. Em **Integration Request**, selecione:
   - **Integration type:** Lambda Function
   - **Lambda Function:** `fastapi-cases-api` (sua função)
   - **Use Lambda Proxy integration:** ✅ MARCAR
3. Salvar

**OU use a automação abaixo!** ⬇️

---

## 🤖 Opção 2: Importar via AWS CLI (Automatizado)

### Passo 1: Importar API

```bash
# 1. Importar OpenAPI spec
API_ID=$(aws apigatewayv2 import-api \
  --body file://openapi-spec.yaml \
  --region us-east-1 \
  --query 'ApiId' \
  --output text)

echo "API criada: $API_ID"
```

**PROBLEMA:** Isso cria HTTP API, mas nosso spec é REST API!

Para REST API, use:

```bash
# Importar como REST API
aws apigateway import-rest-api \
  --body file://openapi-spec.yaml \
  --region us-east-1
```

### Passo 2: Obter API ID

```bash
# Listar APIs e pegar ID
aws apigateway get-rest-apis --region us-east-1

# Salvar ID
export API_ID="abc123xyz"
```

### Passo 3: Configurar Lambda Integration (Automatizado)

```bash
#!/bin/bash

# Configurações
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
LAMBDA_FUNCTION_NAME="fastapi-cases-api"
API_ID="SEU_API_ID_AQUI"  # Obtenha do console ou comando acima

# Lambda ARN
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function/${LAMBDA_FUNCTION_NAME}"

# Listar todos os recursos
RESOURCES=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --region $REGION \
  --query 'items[*].[id,path,resourceMethods]' \
  --output text)

# Para cada recurso, configurar integration
# (Script simplificado - na prática, precisa iterar)

# Exemplo para um endpoint específico:
RESOURCE_ID="xyz123"  # ID do recurso /cases
METHOD="POST"

# Criar integration
aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method $METHOD \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
  --region $REGION

# Dar permissão ao API Gateway para invocar Lambda
aws lambda add-permission \
  --function-name $LAMBDA_FUNCTION_NAME \
  --statement-id apigateway-${API_ID}-${RESOURCE_ID}-${METHOD} \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/${METHOD}/cases" \
  --region $REGION
```

### Passo 4: Deploy

```bash
# Criar deployment
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --region $REGION

# URL da API
echo "API URL: https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod"
```

---

## ⚡ Opção 3: Usar Extensão x-amazon-apigateway (Recomendado!)

Adicione extensões AWS no YAML para configuração automática da Lambda.

### Modificar openapi-spec.yaml

Adicione isto no topo do arquivo:

```yaml
x-amazon-apigateway-request-validators:
  all:
    validateRequestBody: true
    validateRequestParameters: true

x-amazon-apigateway-gateway-responses:
  DEFAULT_4XX:
    responseParameters:
      gatewayresponse.header.Access-Control-Allow-Origin: "'*'"
  DEFAULT_5XX:
    responseParameters:
      gatewayresponse.header.Access-Control-Allow-Origin: "'*'"
```

E para CADA path, adicione:

```yaml
paths:
  /auth/login/access-token:
    post:
      # ... configuração existente ...
      x-amazon-apigateway-integration:
        type: aws_proxy
        httpMethod: POST
        uri: 
          Fn::Sub: arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS::Region}:${AWS::AccountId}:function:fastapi-cases-api/invocations
        passthroughBehavior: when_no_match
```

**Depois importe:**

```bash
aws apigateway import-rest-api \
  --body file://openapi-spec-with-extensions.yaml \
  --region us-east-1
```

Já vai criar TUDO configurado! 🎉

---

## 🔧 Opção 4: Usar AWS SAM (Infrastructure as Code)

Crie arquivo `template.yaml`:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  CasesApi:
    Type: AWS::Serverless::Api
    Properties:
      Name: Cases Management API
      StageName: prod
      DefinitionBody:
        # Colar conteúdo do openapi-spec.yaml aqui
        # OU referenciar arquivo:
        DefinitionUri: ./openapi-spec.yaml
      
  FastApiFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: fastapi-cases-api
      CodeUri: ./
      Handler: lambda_handler.lambda_handler
      Runtime: python3.11
      Events:
        ProxyApiRoot:
          Type: Api
          Properties:
            RestApiId: !Ref CasesApi
            Path: /
            Method: ANY
        ProxyApiGreedy:
          Type: Api
          Properties:
            RestApiId: !Ref CasesApi
            Path: /{proxy+}
            Method: ANY

Outputs:
  ApiUrl:
    Description: API Gateway endpoint URL
    Value: !Sub 'https://${CasesApi}.execute-api.${AWS::Region}.amazonaws.com/prod'
```

**Deploy:**

```bash
sam build
sam deploy --guided
```

---

## 📊 Opção 5: Melhor Abordagem (Proxy Catch-All + Documentação)

### Estratégia Híbrida

**API Gateway:** Apenas 2 rotas (proxy catch-all)
```
ANY /
ANY /{proxy+}
```

**Documentação:** Usar o OpenAPI spec para:
- Swagger UI (docs interativa)
- Geração de SDKs
- Validação de contratos
- Testes automatizados

### Como Fazer

1. **Deploy Lambda com proxy:**

```bash
./deploy-complete.sh  # Script que você já tem
```

2. **Hospedar documentação:**

**Opção A - Swagger UI no S3:**

```bash
# 1. Baixar Swagger UI
wget https://github.com/swagger-api/swagger-ui/archive/refs/tags/v5.10.0.zip
unzip v5.10.0.zip
cd swagger-ui-5.10.0/dist/

# 2. Modificar index.html para apontar pro seu spec
sed -i 's|https://petstore.swagger.io/v2/swagger.json|./openapi-spec.yaml|g' index.html

# 3. Copiar seu spec
cp /path/to/openapi-spec.yaml .

# 4. Upload para S3
aws s3 sync . s3://meu-bucket-docs/ --acl public-read

# 5. Configurar S3 como website
aws s3 website s3://meu-bucket-docs/ --index-document index.html

# URL: http://meu-bucket-docs.s3-website-us-east-1.amazonaws.com
```

**Opção B - Endpoint /docs do FastAPI:**

Seu FastAPI já tem docs em `/docs` e `/redoc`! 🎉

URL: `https://sua-api.execute-api.us-east-1.amazonaws.com/prod/docs`

---

## ✅ Recomendação Final

### Para Produção:

1. **API Gateway:** Proxy catch-all (2 rotas)
   - Simples, barato, escalável
   - Use: `deploy-complete.sh`

2. **Documentação:** FastAPI Swagger UI
   - Já vem pronto em `/docs`
   - Sempre atualizado com o código
   - Não precisa importar no API Gateway

3. **Spec OpenAPI:** Usar para:
   - Geração de SDKs cliente
   - Testes de contrato
   - Validação de API
   - Onboarding de desenvolvedores

### Comandos Finais:

```bash
# 1. Deploy API (proxy)
cd ~/OneDrive/Documentos/backend
./deploy-complete.sh

# 2. Obter URL
API_URL="https://abc123.execute-api.us-east-1.amazonaws.com/prod"

# 3. Acessar documentação
open "${API_URL}/docs"

# 4. Testar endpoint
curl -X POST "${API_URL}/api/v1/auth/login/access-token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin@admin.com&password=admin123"
```

---

## 📚 Recursos Adicionais

**Ferramentas para OpenAPI:**
- **Swagger Editor:** https://editor.swagger.io/
- **Postman:** Importar collection do OpenAPI
- **Insomnia:** Importar spec
- **openapi-generator:** Gerar SDKs

**Validação:**
```bash
# Validar spec
npm install -g @apidevtools/swagger-cli
swagger-cli validate openapi-spec.yaml
```

**Conversão:**
```bash
# Converter YAML → JSON
yq eval -o=json openapi-spec.yaml > openapi-spec.json
```

---

## 🎯 Checklist

- [ ] OpenAPI spec validado
- [ ] Lambda deployada
- [ ] API Gateway configurado
- [ ] Permissions Lambda ↔ API Gateway
- [ ] Testes em /docs funcionando
- [ ] CORS configurado
- [ ] Rate limiting (se necessário)
- [ ] Custom domain (opcional)
- [ ] Monitoramento CloudWatch

Pronto! 🚀
