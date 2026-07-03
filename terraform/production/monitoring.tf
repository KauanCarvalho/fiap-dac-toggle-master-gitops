# ----- Namespace de Monitoramento -----
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [module.eks]
}

# ----- AlertManager Config Secret (Injeção dinâmica de Webhook e Chaves) -----
resource "kubernetes_secret_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  type = "Opaque"

  data = {
    "alertmanager.yaml" = <<-EOT
      global:
        resolve_timeout: 5m

      route:
        group_by: ['alertname', 'namespace', 'service']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 1h
        receiver: 'discord'
        routes:
          - matchers:
              - alertname =~ ".*"
            receiver: 'discord'
          - matchers:
              - alertname =~ ".*"
            receiver: 'pagerduty'

      receivers:
        - name: 'discord'
          webhook_configs:
            - url: "${var.discord_webhook_url}"
              send_resolved: true
              title: '{{ if eq .Status "firing" }}🔥 ALERTA DISPARADO{{ else }}✅ RESOLVIDO{{ end }}'
              text: |
                **{{ .CommonAnnotations.summary }}**
                {{ range .Alerts }}
                - **Serviço:** {{ .Labels.service }}
                - **Namespace:** {{ .Labels.namespace }}
                - **Severidade:** {{ .Labels.severity }}
                - **Descrição:** {{ .Annotations.description }}
                {{ end }}

        - name: 'pagerduty'
          pagerduty_configs:
            - routing_key: "${var.pagerduty_integration_key}"
              description: '{{ .CommonAnnotations.summary }}'
              details:
                namespace: '{{ .CommonLabels.namespace }}'
                service: '{{ .CommonLabels.service }}'
                severity: '{{ .CommonLabels.severity }}'
    EOT
  }

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# ----- kube-prometheus-stack (Prometheus + Grafana + AlertManager) -----
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
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
        storageSpec:
          emptyDir:
            medium: ""

    alertmanager:
      alertmanagerSpec:
        configSecret: alertmanager-config
        storageSpec:
          emptyDir:
            medium: ""

    kubeStateMetrics:
      enabled: true

    nodeExporter:
      enabled: true
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    kubernetes_secret_v1.alertmanager_config
  ]
}

# ----- Loki (log aggregation) -----
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  version          = "6.6.4"
  timeout          = 300

  values = [
    <<-EOT
    deploymentMode: SingleBinary
    loki:
      useTestSchema: true
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      auth_enabled: false
    singleBinary:
      replicas: 1
      persistence:
        enabled: false
      extraVolumes:
        - name: loki-data
          emptyDir: {}
      extraVolumeMounts:
        - name: loki-data
          mountPath: /var/loki
    minio:
      enabled: false
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
    EOT
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# Promtail removido: o OTel Collector coleta logs via filelog receiver e envia para Loki

# ----- OpenTelemetry Collector (DaemonSet) -----
resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  version          = "0.97.1"
  timeout          = 300

  values = [
    <<-EOT
    mode: daemonset

    image:
      repository: otel/opentelemetry-collector-contrib

    presets:
      logsCollection:
        enabled: true
        includeCollectorLogs: false

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
                  - targets: ['$${HOSTNAME}:8888']

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
          endpoint: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
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
        hostPort: 0
        protocol: TCP
      otlp-http:
        enabled: true
        containerPort: 4318
        servicePort: 4318
        hostPort: 0
        protocol: TCP
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_stack,
    helm_release.loki,
  ]
}

# ----- Datadog Agent -----
resource "helm_release" "datadog" {
  name             = "datadog"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
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

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    module.eks
  ]
}

# Saída do Grafana LoadBalancer
output "grafana_url" {
  description = "Grafana LoadBalancer hostname"
  value       = "http://${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname}"
}

data "kubernetes_service" "grafana" {
  metadata {
    name      = "kube-prometheus-stack-grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_stack
  ]
}
