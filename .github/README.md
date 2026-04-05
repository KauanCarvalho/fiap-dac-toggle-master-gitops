# TECH CHALLENGE - FASE 3: Automação e GitOps ToggleMaster

## 1. Introdução

Este projeto contempla a automação completa da infraestrutura e dos processos de entrega contínua (CI/CD) para o ecossistema de microsserviços ToggleMaster (Auth, Flag, Targeting, Evaluation e Analytics). A solução adota práticas avançadas de Infraestrutura como Código (IaC) com Terraform, Segurança (DevSecOps) e Entrega baseada em GitOps com ArgoCD.

## 2. Requisitos Técnicos Implementados

### 2.1. Infraestrutura como Código (Terraform)

A infraestrutura foi componentizada em módulos reutilizáveis, garantindo isolamento e manutenibilidade:
- **Networking**: VPC customizada com isolamento de Subnets Públicas e Privadas, Internet Gateway e Tabelas de Roteamento configuradas para alta disponibilidade.
- **Cluster EKS**: Provisionamento do Amazon Elastic Kubernetes Service com Node Groups associados à **LabRole** da AWS Academy (conforme restrição técnica do ambiente).
- **Bancos de Dados**:
    - Três instâncias RDS (PostgreSQL) independentes para isolamento de dados.
    - Um Cluster ElastiCache (Redis) para suporte à latência reduzida.
    - Uma Tabela DynamoDB para o serviço de Analytics.
- **Mensageria**: Fila AWS SQS para integração assíncrona entre os serviços.
- **Repositórios**: Cinco repositórios no AWS ECR configurados via Terraform para armazenamento de imagens Docker.
- **Estado Remoto**: O arquivo de estado do Terraform (`terraform.tfstate`) é gerenciado remotamente em um Bucket S3 com mecanismos de Lock via DynamoDB.

### 2.2. Segurança e DevSecOps (CI)

As pipelines de Integração Contínua (GitHub Actions) foram configuradas para cada microsserviço, implementando os seguintes estágios de segurança:
1. **Linter/Static Analysis**: Verificação de qualidade do código fonte.
2. **Security Scan (SAST/SCA)**: Utilização de ferramentas como Trivy para análise de vulnerabilidades em dependências e código (bloqueio automático em caso de falhas críticas).
3. **Container Scan**: Análise de vulnerabilidades na imagem final antes do push para o ECR.
4. **Secrets Management**: Integração com AWS Secrets Manager e External Secrets Operator (ESO) para evitar o uso de credenciais em texto plano.

### 2.3. Entrega Contínua e GitOps (CD)

O deploy das aplicações não é mais realizado via Push direto, mas sim via **Pull/GitOps**:
- **ArgoCD**: Instalado via Helm Provider no Terraform, gerenciando o ciclo de vida dos recursos no cluster.
- **Atualização de Imagens**: O workflow de CI atualiza dinamicamente as tags de imagem nos manifestos Kubernetes do repositório GitOps.
- **External Secrets**: Sincronização automática de segredos da infraestrutura para o cluster sem intervenção manual através do ClusterSecretStore.

---

## 3. Configuração de Variáveis (GitHub Secrets)

Configure as seguintes **8 chaves** no seu repositório (**Settings > Secrets and variables > Actions**):

- **Credenciais AWS Academy**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
- **Bancos de Dados (RDS)**: `DB_PASSWORD_AUTH`, `DB_PASSWORD_FLAG`, `DB_PASSWORD_TARGETING`
- **Segurança (Apps)**: `AUTH_MASTER_KEY`, `EVAL_API_KEY`

---

## 4. Guia de Implantação (Setup)

Para reproduzir o ambiente de forma íntegra, siga a sequência abaixo:

### Passo 1: Gênese da Infraestrutura (Terraform Bootstrap)

Execute o workflow de **Terraform Bootstrap** no GitHub Actions. Este passo criará o Bucket S3 e a Tabela DynamoDB necessários para o armazenamento do Backend Remoto.

### Passo 2: Provisionamento da Infraestrutura AWS (Terraform Production)

Execute o workflow de **Terraform Production**. Este passo provisionará todos os serviços gerenciados (EKS, RDS, Redis, DynamoDB, SQS, ECR).

### Passo 3: Configuração de Credenciais Locais (AWS Academy)

Para interagir com o cluster e os repositórios via CLI, certifique-se de que o arquivo `~/.aws/credentials` (ou as variáveis de ambiente equivalentes) contém as credenciais do seu Lab atualizadas.

### Passo 4: Publicação das Imagens e Atualização dos Manifestos

1. **Publicar Imagens no ECR**:
Execute o script abaixo em seu terminal para realizar o build e push de todos os serviços para os repositórios criados via Terraform:

```bash
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || openssl rand -hex 4 | cut -c1-7)

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

SERVICES=("auth-service" "flag-service" "targeting-service" "evaluation-service" "analytics-service")

for SERVICE in "${SERVICES[@]}"; do
    REPO_NAME="togglemaster-${SERVICE%-service}" 
    FULL_IMAGE="${ECR_REGISTRY}/${REPO_NAME}:${GIT_SHA}"
    docker build -t ${FULL_IMAGE} local/services/${SERVICE}
    docker push ${FULL_IMAGE}
done
```

2. **Sincronização de Tags (GitOps Sync)**:

Atualize as imagens nos manifestos de aplicação para os 5 serviços utilizando o utilitário `sed` ou editando os arquivos manualmente. O comando abaixo usa os templates como base para gerar o manifesto final em `k8s/apps/`:

```bash
# Exemplo para o serviço de Auth (Obrigatório repetir para os 5 serviços)
sed "s|\$IMAGE_URI|YOUR_ECR_IMAGE_URL_HERE|g" k8s/templates/auth-service/deployment.tmpl.yaml > k8s/apps/auth-service/deployment.yaml
```

**Nota**: O uso do `sed` é meramente ilustrativo para agilizar o processo; você pode optar por copiar o conteúdo do template e colar a URL da imagem manualmente no arquivo de destino.

**Importante**: Após gerar os manifestos atualizados, é obrigatório realizar o `git commit` e `git push` dessas mudanças. O ArgoCD monitora o repositório remoto e só iniciará a sincronização para o cluster após detectar o novo commit na ramificação principal.

### Passo 5: Preparação do Cluster Kubernetes

Conecte-se ao cluster via terminal e aplique os namespaces de fundação:
```bash
aws eks update-kubeconfig --name togglemaster-cluster --region us-east-1
kubectl apply -f k8s/apps/00-namespaces.yaml
```
*Observação: O Ingress Nginx e o External Secrets Operator já estarão instalados automaticamente pelo Terraform via Helm.*

### Passo 6: Inicialização do GitOps (ArgoCD)

Para acessar e configurar o seu ecossistema GitOps, execute os comandos abaixo:

1. **Obter Endpoint do ArgoCD**:

```bash
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

2. **Obter Senha do Administrador**:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

3. **Aplicar Definições de Apps**:

Acesse a URL obtida no passo 1 (usuário `admin`), e então aplique os manifestos do ArgoCD via terminal:

```bash
kubectl apply -f argocd/
```

No painel do ArgoCD, realize a sincronização do aplicativo `core-infra` antes de proceder com a sincronização dos microsserviços individuais.

---

## 5. Validação e Evidência de Operação

Após a sincronização, os serviços podem ser validados através dos endereços de Health Check fornecidos pelo Ingress Load Balancer:

- **Auth Service**: `http://<LB_DNS>/auth/health` -> `{"status":"ok"}`
- **Flag Service**: `http://<LB_DNS>/flags/health` -> `{"status":"ok"}`
- **Evaluation Service**: `http://<LB_DNS>/evaluate/health` -> `{"status":"ok"}`
- **Analytics Service**: `http://<LB_DNS>/analytics/health` -> `{"status":"ok"}`

### Evidência de Operação - Cluster Status

![ToggleMaster Cluster Status](https://github.com/user-attachments/assets/052eee61-a3f6-4133-a131-b1dd6386e160)

---

## 6. Considerações Finais

Toda a infraestrutura descrita foi projetada sob o princípio de imutabilidade. Conflitos de versão foram eliminados através da centralização no repositório de GitOps, e a segurança foi reforçada com a injeção dinâmica de segredos via AWS Secrets Manager, atendendo integralmente aos requisitos da Fase 3 do Tech Challenge.
