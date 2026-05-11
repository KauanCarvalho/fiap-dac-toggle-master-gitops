# TECH CHALLENGE - FASE 3: Automação e GitOps ToggleMaster

## 1. Introdução

Este projeto contempla a automação completa da infraestrutura e dos processos de entrega contínua (CI/CD) para o ecossistema de microsserviços ToggleMaster (Auth, Flag, Targeting, Evaluation e Analytics). A solução adota práticas avançadas de Infraestrutura como Código (IaC) com Terraform, Segurança (DevSecOps) e Entrega baseada em GitOps com ArgoCD.

## 2. Estrutura do Repositório

```
.
├── .github/
│   ├── README.md
│   └── workflows/
│       ├── terraform-bootstrap.yml   # Cria S3 + DynamoDB para o estado remoto
│       └── terraform-production.yml  # Provisiona VPC, EKS, RDS ×3, ElastiCache, DynamoDB, SQS, ECR ×5, ArgoCD, Ingress Nginx, ESO, Secrets Manager
├── argocd/
│   ├── core-infra.yaml               # App ArgoCD para recursos base do cluster
│   ├── auth-service.yaml
│   ├── flag-service.yaml
│   ├── targeting-service.yaml
│   ├── evaluation-service.yaml
│   └── analytics-service.yaml
├── k8s/
│   ├── apps/                         # Manifestos Kubernetes (fonte de verdade do GitOps)
│   │   ├── 00-namespaces.yaml
│   │   ├── cluster-secret-store.yaml
│   │   ├── ingress.yaml
│   │   └── <service>/                # deployment, service, configmap, hpa, external-secret
│   └── templates/                    # Templates usados pelo CI para atualizar tags de imagem
└── terraform/
    ├── bootstrap/                    # Estado remoto: S3 + DynamoDB lock
    ├── modules/aws/                  # Módulos reutilizáveis: vpc, eks, rds, ecr, sqs, etc.
    └── production/                   # Orquestração principal da infra + Helm (ArgoCD, ESO, Ingress)
```

> As pipelines de CI/DevSecOps (Build, Lint, SAST/SCA, Docker, ECR) residem nos repositórios individuais de cada microsserviço em [fiap-dac-toggle-master](https://github.com/KauanCarvalho/fiap-dac-toggle-master). Este repositório é exclusivamente o **repositório de GitOps**: manifestos Kubernetes, definições ArgoCD e Terraform de infraestrutura.

---

## 3. Arquitetura Geral

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         REPOSITÓRIO DE APLICAÇÕES                        │
│          github.com/KauanCarvalho/fiap-dac-toggle-master                │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────┐        │
│  │               GitHub Actions CI Pipeline                     │        │
│  │  1. Build & Unit Test                                        │        │
│  │  2. Lint / Static Analysis (golangci-lint, pylint)           │        │
│  │  3. Security Scan → SCA (Trivy fs) + SAST (gosec/bandit)     │        │
│  │     └─ BLOQUEIO se vulnerabilidade CRÍTICA encontrada        │        │
│  │  4. Docker Build → Container Scan (Trivy image) → ECR Push  │        │
│  │     └─ Tag: v1.0.0-<commit-hash>                             │        │
│  │  5. Trigger GitOps → commit automático no repo abaixo ↓     │        │
│  └──────────────────────────────────────────────────────────────┘        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ commit automático (GitHub App)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    ESTE REPOSITÓRIO (GitOps)                             │
│          github.com/KauanCarvalho/fiap-dac-toggle-master-gitops         │
│                                                                           │
│  ├── terraform/       → IaC (VPC, EKS, RDS, Redis, DynamoDB, SQS, ECR) │
│  ├── k8s/apps/        → Manifestos Kubernetes (fonte de verdade)        │
│  │   └── <service>/deployment.yaml  ← tag atualizada pelo CI            │
│  └── argocd/          → ArgoCD Application definitions                  │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ monitoramento contínuo (pull)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          AWS EKS CLUSTER                                 │
│                                                                           │
│  ArgoCD (selfHeal: true, prune: true)                                    │
│  └─ Detecta mudança → Sincroniza automaticamente → Deploy da nova versão │
│                                                                           │
│  5 Microsserviços: auth · flag · targeting · evaluation · analytics      │
│  External Secrets Operator → AWS Secrets Manager (sem credenciais em     │
│  texto plano)                                                             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Requisitos Técnicos Implementados

### 4.1. Infraestrutura como Código (Terraform)

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

### 4.2. Segurança e DevSecOps (CI)

As pipelines de Integração Contínua (GitHub Actions) foram configuradas nos repositórios de cada microsserviço, implementando os seguintes estágios obrigatórios:

1. **Build & Unit Test**: Compilação do código e execução de testes unitários a cada Pull Request e Push na Main.
2. **Linter/Static Analysis**: Verificação de qualidade e estilo do código fonte (ex: `golangci-lint` para Go).
3. **Security Scan (SAST & SCA)**:
   - **SCA**: Varredura de vulnerabilidades em dependências via **Trivy** em modo `fs`.
   - **SAST**: Análise estática de segurança no código fonte (ex: **gosec** para Go).
   - **Regra de Bloqueio**: Vulnerabilidades com severidade **CRITICAL** interrompem o pipeline imediatamente.
4. **Docker Build & Push**:
   - Build da imagem Docker.
   - **Container Scan** com Trivy na imagem gerada antes do push.
   - Login e push para o **AWS ECR** com a tag baseada no commit hash (ex: `v1.0.0-a1b2c3d`).
5. **Trigger GitOps**: Ao final do pipeline, um commit automático é realizado **neste repositório** (via GitHub App) atualizando a tag da imagem nos manifestos `k8s/apps/`.
6. **Secrets Management**: Integração com AWS Secrets Manager e External Secrets Operator (ESO) para evitar o uso de credenciais em texto plano.

### 4.3. Entrega Contínua e GitOps (CD)

O deploy das aplicações não é mais realizado via Push direto, mas sim via **Pull/GitOps**:
- **ArgoCD**: Instalado via Helm Provider no Terraform, gerenciando o ciclo de vida dos 5 microsserviços no cluster EKS. A aplicação `core-infra` é sincronizada primeiro e instala os recursos base (namespaces, ClusterSecretStore, Ingress). Em seguida, cada microsserviço possui seu próprio objeto `Application` ArgoCD com `selfHeal: true` e `prune: true`.
- **Atualização de Imagens**: O workflow de CI atualiza dinamicamente as tags de imagem nos manifestos `k8s/apps/<service>/deployment.yaml` deste repositório GitOps via commit automatizado. Os arquivos `k8s/templates/` servem como base para geração desses manifests com a nova tag.
- **External Secrets**: Sincronização automática de segredos do AWS Secrets Manager para o cluster via `ClusterSecretStore`, sem intervenção manual.

---

## 5. Configuração de Variáveis (GitHub Secrets)

Configure as seguintes **8 chaves** no seu repositório (**Settings > Secrets and variables > Actions**):

- **Credenciais AWS Academy**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
- **Bancos de Dados (RDS)**: `DB_PASSWORD_AUTH`, `DB_PASSWORD_FLAG`, `DB_PASSWORD_TARGETING`
- **Segurança (Apps)**: `AUTH_MASTER_KEY`, `EVAL_API_KEY`

---

## 6. Guia de Implantação (Setup)

Para reproduzir o ambiente de forma íntegra, siga a sequência abaixo:

### Passo 1: Gênese da Infraestrutura (Terraform Bootstrap)

Execute o workflow de **Terraform Bootstrap** no GitHub Actions. Este passo criará o Bucket S3 e a Tabela DynamoDB necessários para o armazenamento do Backend Remoto.

### Passo 2: Provisionamento da Infraestrutura AWS (Terraform Production)

Execute o workflow de **Terraform Production**. Este passo provisionará todos os serviços gerenciados (EKS, RDS, Redis, DynamoDB, SQS, ECR).

### Passo 3: Configuração de Credenciais Locais (AWS Academy)

Para interagir com o cluster e os repositórios via CLI, certifique-se de que o arquivo `~/.aws/credentials` (ou as variáveis de ambiente equivalentes) contém as credenciais do seu Lab atualizadas.

### Passo 4: Publicação das Imagens e Atualização dos Manifestos

O ciclo de vida das imagens e do deploy é gerenciado de forma automatizada, permitindo que a imagem seja alterada via GitOps.

#### Automação via Pipelines (Recomendado)

O fluxo principal de deploy utiliza pipelines (GitHub Actions) nos repositórios dos microsserviços. Esse processo funciona de forma integrada:

1. **Compilar** o código e realizar o **Build** da imagem Docker.
2. Realizar os scans de segurança e fazer o **Push** para o Amazon ECR.
3. **Trigger de GitOps**: A pipeline do microserviço utiliza um **GitHub App** para realizar um commit automático **neste repositório de GitOps**, alterando a tag da imagem no respectivo manifesto em `k8s/apps/`.
4. **Deploy Automático**: O **ArgoCD** detecta o commit realizado pelo GitHub App e sincroniza o estado do cluster com a nova versão da imagem.

Este fluxo garante que a imagem em produção seja sempre rastreável, testada e implantada de forma declarativa.

*Como fazer*:

Execute o [workflow de deploy](https://github.com/KauanCarvalho/fiap-dac-toggle-master/actions/workflows/deploy.yml) para realizar o build e push dos serviços para os ECRs criados via Terraform, além de commitar aqui no repositório as versões das imagens que serão sincronizadas pelo ArgoCD.

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

## 7. Banco de Dados e Migrações

Certos microserviços (como Auth, Flag e Targeting) dependem da execução de queries iniciais ou migrations para o correto funcionamento das tabelas e procedimentos no PostgreSQL. Você pode encontrar os scripts SQL necessários no repositório de origem das aplicações: [Scripts SQL](https://github.com/KauanCarvalho/fiap-dac-toggle-master/tree/main/local/services).

### 7.1. Executando Queries Manualmente via Pod Temporário

Como o RDS está em uma sub-rede privada e o acesso direto via console pode estar restrito no AWS Academy, a forma recomendada de executar os scripts é subindo um Pod temporário dentro do cluster que tenha o cliente `psql` instalado.

1. **Obtenha as Credenciais**:
   As credenciais (Host, User, Password) podem ser visualizadas no **Output do Terraform** após o provisionamento ou através do **AWS Secrets Manager** no console da AWS.

2. **Crie o Pod de Ferramentas**:
   Execute o comando abaixo para subir um pod com o cliente do Postgres:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pg-temp
  namespace: default
spec:
  containers:
  - name: pg-temp
    image: postgres:16-alpine
    command: ["sleep", "3600"]
  restartPolicy: Never
EOF
```

3. **Acesse o Pod e Execute o psql**:
   Utilize as senhas configuradas nos **GitHub Secrets** (`DB_PASSWORD_AUTH`, `DB_PASSWORD_FLAG`, etc.) para realizar o login, a senha é definida no cofre de segredos do Github Actions que vai parar em um _Secret Manager_ da AWS via Terraform.

```bash
kubectl exec -it pg-temp -- psql -h <RDS_ENDPOINT> -U <USER> -d <DB_NAME>
```

### ⚠️ WARNING: O Problema das Migrações Manuais

No fluxo ideal de uma arquitetura de microsserviços, as alterações de banco de dados devem ser tratadas como **migrations versionadas** que executam automaticamente a cada inicialização da aplicação (ex: usando tools de **Migrators** como Flyway, Liquibase ou ferramentas nativas da linguagem).

**Por que não foi feito de forma automatizada aqui?**

Neste projeto específico, os scripts de banco não estavam previamente versionados como código de migração dentro dos repositórios originais dos serviços. Por esse motivo, a execução manual é necessária para a configuração inicial do ambiente.

**Por que migrações automatizadas são a melhor prática?**

- **Sincronia com o Código**: Garante que o schema do banco acompanhe exatamente a versão da imagem que está sendo implantada.
- **Evita Erros de Performance**: Execuções manuais e ad-hoc podem causar `drop` acidental de Procedures, Functions ou Views essenciais, resultando em erros de runtime e degradação de performance.
- **Governança e GitOps**: Em um ecossistema GitOps de elite, o banco de dados deve ser tão "autogerenciavel" e declarativo quanto os proprios containers no Kubernetes.

---

## 8. Validação e Evidência de Operação

Após a sincronização, os serviços podem ser validados através dos endereços de Health Check fornecidos pelo Ingress Load Balancer, que por sua vez é gerenciado pelo ArgoCD além de ser um dos _outputs_ do Terraform.

- **Auth Service**: `http://<LB_DNS>/auth/health` -> `{"status":"ok"}`
- **Flag Service**: `http://<LB_DNS>/flags/health` -> `{"status":"ok"}`
- **Evaluation Service**: `http://<LB_DNS>/evaluate/health` -> `{"status":"ok"}`
- **Analytics Service**: `http://<LB_DNS>/analytics/health` -> `{"status":"ok"}`
- **Targeting Service**: `http://<LB_DNS>/targeting/health` -> `{"status":"ok"}`

## 9. Validação de Integridade do Cluster

Para confirmar que o cluster está operando corretamente, no repositório de origem das aplicações existe um script que valida todas as chamadas possíveis e mapeadas. Ela se baseia em envs presentes no `.env.prod` que se originam de um `.env.prod.sample` altere para as _envs_ e sucesso!

```bash
make check-all ENV=prod
```

### Evidência de Operação - Cluster Status

![ToggleMaster Cluster Status](https://github.com/user-attachments/assets/052eee61-a3f6-4133-a131-b1dd6386e160)

---

## 10. Considerações Finais

Toda a infraestrutura descrita foi projetada sob o princípio de imutabilidade. Conflitos de versão foram eliminados através da centralização no repositório de GitOps, e a segurança foi reforçada com a injeção dinâmica de segredos via AWS Secrets Manager, atendendo integralmente aos requisitos da Fase 3 do Tech Challenge.
