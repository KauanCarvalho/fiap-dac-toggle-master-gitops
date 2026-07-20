# Fase 4 — Observabilidade, APM e Alertas

Este documento cobre exclusivamente o que foi implementado neste repositório para a Fase 4 do Tech Challenge. A infraestrutura base (VPC, EKS, RDS, ElastiCache, SQS, DynamoDB, ECR) e os manifestos de deploy dos 5 microsserviços já existiam das fases anteriores e não são o foco aqui. A instrumentação do código das aplicações e o workflow de self-healing vivem no repositório [fiap-dac-toggle-master](https://github.com/KauanCarvalho/fiap-dac-toggle-master).

Toda a stack abaixo foi adicionada em `terraform/production/monitoring.tf`, provisionada via `helm_release` e orquestrada pelo ArgoCD App `monitoring` ([argocd/monitoring.yaml](argocd/monitoring.yaml)).

---

## 1. Monitoramento Opensource (Métricas e Logs)

| Componente | Chart | Função |
| :--- | :--- | :--- |
| **kube-prometheus-stack** | `prometheus-community/kube-prometheus-stack` | Prometheus (métricas) + Grafana (visualização) + AlertManager (roteamento de alertas). Grafana exposto via `LoadBalancer`. |
| **Loki** | `grafana/loki` (SingleBinary, filesystem) | Centralização e indexação de logs de todos os pods do cluster. |

Dashboard customizado provisionado via ConfigMap ([k8s/apps/monitoring/grafana-dashboard.yaml](k8s/apps/monitoring/grafana-dashboard.yaml)), carregado automaticamente pelo sidecar do Grafana, com painéis de: pods running por serviço, taxa de requisições, taxa de erro 5xx, CPU/memória por node, latência p95 por serviço e logs em tempo real (Loki).

---

## 2. OpenTelemetry Collector

DaemonSet `opentelemetry-collector` (chart oficial `open-telemetry/opentelemetry-helm-charts`) atuando como peça central de roteamento de telemetria — os microsserviços enviam OTLP (gRPC/HTTP) para o Collector, que distribui:

- **traces** → Datadog (`otlp/datadog` exporter)
- **metrics** → Prometheus (`prometheusremotewrite`, com `enableRemoteWriteReceiver` habilitado no Prometheus)
- **logs** → Loki

Promtail foi removido do stack — a coleta de logs passou a ser feita pelo próprio OTel Collector (`filelog` receiver via `presets.logsCollection`).

---

## 3. APM — Datadog

Datadog Agent (chart `datadoghq/datadog`) com OTLP receiver habilitado (porta 4317), APM e coleta de logs (`containerCollectAll`) ativos. Pipelines de log customizados (`datadog_logs_custom_pipeline`) corrigem falsos-positivos de status `ERROR` em logs do Loki e do nginx do `loki-gateway`, que escrevem por padrão em stderr.

---

## 4. Alertas, ChatOps e Incident Management

- **Regras de alerta** ([k8s/apps/monitoring/alert-rules.yaml](k8s/apps/monitoring/alert-rules.yaml)): taxa de erro 5xx do auth-service > 5%, serviço sem pods disponíveis, latência p95 do evaluation-service > 2s, CPU de node > 80%, memória de node < 20%.
- **AlertManager** roteia cada alerta para dois receivers em paralelo: **Discord** (webhook com embed detalhado) e **PagerDuty** (abertura de incidente via `routing_key`). Configuração injetada dinamicamente por Terraform (`kubernetes_secret_v1.alertmanager_config`), evitando hardcode de credenciais no manifesto.

---

## 5. Self-Healing

A automação de mitigação (rollout restart automático) vive no repositório de aplicação, em [`.github/workflows/self-healing.yml`](https://github.com/KauanCarvalho/fiap-dac-toggle-master/blob/release-TC4-Guilherme/.github/workflows/self-healing.yml).

> **Pendência conhecida**: falta a ponte entre o AlertManager e o `repository_dispatch` do GitHub Actions (hoje não há `webhook_config` nem Lambda fazendo essa chamada) — o self-healing está validado via disparo manual (`workflow_dispatch`), mas ainda não é 100% automático a partir do alerta real.

---

## 6. Variáveis sensíveis (Terraform)

Injetadas via `terraform.tfvars.secret` (não versionado): `datadog_api_key`, `datadog_app_key`, `discord_webhook_url`, `pagerduty_integration_key`.

---

## 7. Acesso rápido

| Ferramenta | Como acessar |
| :--- | :--- |
| **Grafana** | `terraform output -raw grafana_url` (LoadBalancer público) — login `admin` / senha definida em `monitoring.tf`. |
| **Prometheus** | `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` (ClusterIP, sem exposição externa). |
| **Loki** | Sem UI própria — consultar via datasource do Grafana (Explore) ou `kubectl port-forward -n monitoring svc/loki-gateway 3100:80`. |
