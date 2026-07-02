# ============================================================
# OBSERVABILITY STACK — Fase 4
# Prometheus + Grafana + Loki + OTel Collector + Datadog
# ============================================================

# ----- kube-prometheus-stack (Prometheus + Grafana + AlertManager) -----
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "61.3.2"
  timeout          = 600

  values = [
    <<-EOT
    grafana:
      enabled: true
      service:
        type: LoadBalancer
      adminPassword: "togglemaster@2024"
      sidecar:
        dashboards:
          enabled: true
          label: grafana_dashboard
          searchNamespace: monitoring
        datasources:
          enabled: true
      additionalDataSources:
        - name: Loki
          type: loki
          url: http://loki:3100
          access: proxy
          isDefault: false

    prometheus:
      prometheusSpec:
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false
        ruleSelectorNilUsesHelmValues: false

    alertmanager:
      alertmanagerSpec:
        configSecret: alertmanager-config

    kubeStateMetrics:
      enabled: true

    nodeExporter:
      enabled: true
    EOT
  ]

  depends_on = [module.eks]
}

# ----- Loki (log aggregation) -----
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = "monitoring"
  create_namespace = true
  version          = "6.6.4"
  timeout          = 300

  values = [
    <<-EOT
    deploymentMode: SingleBinary
    loki:
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      auth_enabled: false
    singleBinary:
      replicas: 1
    minio:
      enabled: false
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0
    EOT
  ]

  depends_on = [module.eks]
}

# ----- Promtail (log shipper → Loki) -----
resource "helm_release" "promtail" {
  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = "monitoring"
  create_namespace = true
  version          = "6.16.4"
  timeout          = 180

  values = [
    <<-EOT
    config:
      clients:
        - url: http://loki:3100/loki/api/v1/push
    EOT
  ]

  depends_on = [helm_release.loki]
}

# ----- OpenTelemetry Collector (DaemonSet) -----
resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  namespace        = "monitoring"
  create_namespace = true
  version          = "0.97.1"
  timeout          = 300

  values = [
    <<-EOT
    mode: daemonset

    config:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
        prometheus:
          config:
            scrape_configs:
              - job_name: otel-collector
                static_configs:
                  - targets: ['${HOSTNAME}:8888']

      processors:
        batch:
          timeout: 5s
          send_batch_size: 512
        memory_limiter:
          check_interval: 1s
          limit_mib: 400
          spike_limit_mib: 100
        resource:
          attributes:
            - action: insert
              key: cluster
              value: togglemaster-cluster

      exporters:
        prometheusremotewrite:
          endpoint: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write
        loki:
          endpoint: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
        otlp/datadog:
          endpoint: https://api.datadoghq.com
          headers:
            DD-Api-Key: ${var.datadog_api_key}
        debug:
          verbosity: basic

      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [otlp/datadog, debug]
          metrics:
            receivers: [otlp, prometheus]
            processors: [memory_limiter, batch, resource]
            exporters: [prometheusremotewrite, debug]
          logs:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [loki, debug]

    ports:
      otlp:
        enabled: true
        containerPort: 4317
        servicePort: 4317
        protocol: TCP
      otlp-http:
        enabled: true
        containerPort: 4318
        servicePort: 4318
        protocol: TCP
    EOT
  ]

  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.loki,
  ]
}

# ----- Datadog Agent -----
resource "helm_release" "datadog" {
  name             = "datadog"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  namespace        = "monitoring"
  create_namespace = true
  version          = "3.69.3"
  timeout          = 300

  values = [
    <<-EOT
    datadog:
      apiKey: ${var.datadog_api_key}
      appKey: ${var.datadog_app_key}
      site: datadoghq.com
      logs:
        enabled: true
        containerCollectAll: true
      apm:
        portEnabled: true
      processAgent:
        enabled: true
      otlp:
        receiver:
          protocols:
            grpc:
              enabled: true
              endpoint: 0.0.0.0:4317
    clusterAgent:
      enabled: true
    EOT
  ]

  depends_on = [module.eks]
}

# Saída do Grafana LoadBalancer
output "grafana_url" {
  description = "Grafana LoadBalancer hostname"
  value       = "http://${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname}"
}

data "kubernetes_service" "grafana" {
  metadata {
    name      = "kube-prometheus-stack-grafana"
    namespace = "monitoring"
  }
  depends_on = [helm_release.kube_prometheus_stack]
}
