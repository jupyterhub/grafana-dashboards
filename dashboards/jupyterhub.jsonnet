#!/usr/bin/env jsonnet -J ../vendor
# Deploys one dashboard - "JupyterHub dashboard",
# with useful stats about usage & diagnostics.
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local row = grafana.row;
local heatmapPanel = grafana.heatmapPanel;

local standardDims = { w: 12, h: 8};

local templates = [
   template.datasource(
    'PROMETHEUS_DS',
    'prometheus',
    'Prometheus',
    hide='label',
   ),
  template.new(
    'hub',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_namespace_status_phase, namespace)',
    regex='.*-(?:staging|prod)$',
    # FIXME: Grafana needs a manual 'refresh variables' before it populates this.
    # Maybe another API call?
    current="utoronto-prod"
  )
];

# Cluster-wide stats
local userNodes = graphPanel.new(
  'User Nodes',
).addTarget(
  prometheus.target('sum(kube_node_info{node=~\".*user.*\"})')
);

local clusterUtilization = graphPanel.new(
  'Cluster Utilization',
  formatY1='percentunit',
  stack=true
).addTargets([
  prometheus.target(
    expr='sum(kube_pod_container_resource_requests_memory_bytes{node=~\".*user.*\"} and on (pod) (kube_pod_container_status_ready{pod=~\"^jupyter.*\"})) / sum(kube_node_status_allocatable_memory_bytes{node=~\".*user.*\"})',
    legendFormat='User Pods'
  ),
  prometheus.target(
    expr='sum(kube_pod_container_resource_requests_memory_bytes{node=~\".*user.*\"} and on (pod) (kube_pod_container_status_ready{pod=~\"^user-placeholder.*\"})) / sum(kube_node_status_allocatable_memory_bytes{node=~\".*user.*\"})',
    legendFormat='Placeholder Pods'
  )
]);

# Hub usage stats
local currentRunningUsers = graphPanel.new(
  'Current running users',
).addTargets([
  prometheus.target(
    'sum(kube_pod_status_phase{phase="Running", pod=~"^jupyter-.*", namespace="$hub"}) by (phase)',
    legendFormat='{{phase}}'
  )
]);

local userMemoryDistribution = heatmapPanel.new(
    'User memory usage distribution',
    yAxis_format='bytes',
    color_colorScheme="interpolateViridis"
  ).addTargets([
    prometheus.target('sum(container_memory_working_set_bytes{pod=~\"^jupyter-.*\",namespace=\"$hub\"}) by (pod)')
]);

local userAgeDistribution = heatmapPanel.new(
  'User active age distribution',
  yAxis_format='s',
  color_colorScheme="interpolateViridis"
).addTargets([
  prometheus.target('(time() - kube_pod_created{pod=~"^jupyter.*", namespace="$hub"})')
]);

# Hub diagnostics
local hubResponseLatency = graphPanel.new(
  'Hub response latency',
  formatY1='s'
).addTargets([
  prometheus.target(
    'histogram_quantile(0.99, sum(rate(request_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat="99th percentile"
  ),
  prometheus.target(
    'histogram_quantile(0.50, sum(rate(request_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat="50th percentile"
  )
]);

local proxyMemory = graphPanel.new(
  'Proxy Memory (RSS)',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(container_memory_rss{pod=~"proxy-.*", namespace="$hub"})'
  )
]);

local proxyCPU = graphPanel.new(
  'Proxy CPU'
).addTargets([
  prometheus.target(
    'sum(rate(container_cpu_usage_seconds_total{pod=~"proxy-.*",namespace="$hub"}[5m]))'
  )
]);

local hubMemory = graphPanel.new(
  'Hub Memory (RSS)',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(container_memory_rss{pod=~"hub-.*", namespace="$hub"})'
  )
]);

local hubCPU = graphPanel.new(
  'Hub CPU'
).addTargets([
  prometheus.target(
    'sum(rate(container_cpu_usage_seconds_total{pod=~"hub-.*",namespace="$hub"}[5m]))'
  )
]);

local userSchedulerMemory = graphPanel.new(
  'User Scheduler Memory (RSS)',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(container_memory_rss{pod=~"user-scheduler-.*", namespace="$hub"})'
  )
]);

local userSchedulerCPU = graphPanel.new(
  'User Scheduler CPU'
).addTargets([
  prometheus.target(
    'sum(rate(container_cpu_usage_seconds_total{pod=~"user-scheduler-.*",namespace="$hub"}[5m]))'
  )
]);

local serverStartTimes =   graphPanel.new(
  'Server Start Times',
  formatY1='s',
  lines=false,
  points=true,
  pointradius=2
).addTargets([
  prometheus.target(
    # Metrics from hub seems to have `kubernetes_namespace` rather than just `namespace`
    'histogram_quantile(0.99, sum(rate(server_spawn_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat="99th percentile"
  ),
  prometheus.target(
    'histogram_quantile(0.5, sum(rate(server_spawn_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat="50th percentile"
  )
]);

local usersPerNode = graphPanel.new(
  'Users per node'
).addTargets([
  prometheus.target(
    'sum(kube_pod_info{pod=~"jupyter-.*", namespace="$hub"}) by (node)',
    legendFormat='{{node}}'
  )
]);


# Cluster diagnostics
local userNodesRSS = graphPanel.new(
  'User Nodes Memory usage (RSS)',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(node_memory_Active_bytes{kubernetes_node=~".*user.*"}) by (kubernetes_node)',
    legendFormat="{{kubernetes_node}}"
  )
]);

#
local userNodesCPU = graphPanel.new(
  'User Nodes CPU',
  formatY1='short'
).addTargets([
  prometheus.target(
    'sum(rate(node_cpu_seconds_total{mode!="idle", kubernetes_node=~".*user.*"}[5m])) by (kubernetes_node)',
    legendFormat="{{kubernetes_node}}}"
  )
]);


local nonRunningPods = graphPanel.new(
  'Non Running User Pods',
  stack=true
).addTargets([
  prometheus.target(
    'sum(kube_pod_status_phase{phase!="Running"}) by (phase)',
    legendFormat='{{phase}}'
  )
]);

# NFS Stats
local userNodesNFSOps = graphPanel.new(
  'User Nodes NFS Ops'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfs_requests_total{kubernetes_node=~".*user.*"}[5m])) by (kubernetes_node)',
    legendFormat="{{kubernetes_node}}"
  )
]);

local userNodesIOWait = graphPanel.new(
  'iowait % on each node'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfs_requests_total{kubernetes_node=~".*user.*"}[5m])) by (kubernetes_node)',
    legendFormat="{{kubernetes_node}}"
  )
]);

local userNodesHighNFSOps = graphPanel.new(
  'NFS Operation Types on user nodes (>1/s)'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfs_requests_total[5m])) by (method) > 1',
    legendFormat="{{method}}"
  )
]);

local nfsServerCPU = graphPanel.new(
  'NFS Server CPU'
).addTargets([
  prometheus.target(
    'avg(rate(node_cpu_seconds_total{job="prometheus-nfsd-server", mode!="idle"}[2m])) by (mode)',
    legendFormat="{{mode}}"
  )
]);

local nfsServerIOPS = graphPanel.new(
  'NFS Server Disk ops'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfsd_disk_bytes_read_total[5m]))',
    legendFormat='Read'
  ),
  prometheus.target(
    'sum(rate(node_nfsd_disk_bytes_written_total[5m]))',
    legendFormat='Write'
  ),
]);

local nfsServerWriteLatency = graphPanel.new(
  'NFS Server disk write latency'
).addTargets([
  prometheus.target(
    'sum(rate(node_disk_write_time_seconds_total{job="prometheus-nfsd-server"}[5m])) by (device) / sum(rate(node_disk_writes_completed_total{job="prometheus-nfsd-server"}[5m])) by (device)',
    legendFormat="{{device}}"
  )
]);

local nfsServerReadLatency = graphPanel.new(
  'NFS Server disk read latency'
).addTargets([
  prometheus.target(
    'sum(rate(node_disk_read_time_seconds_total{job="prometheus-nfsd-server"}[5m])) by (device) / sum(rate(node_disk_reads_completed_total{job="prometheus-nfsd-server"}[5m])) by (device)',
    legendFormat="{{device}}"
  )
]);

# Support Metrics
local prometheusMemory = graphPanel.new(
  'Prometheus Memory (RSS)',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(container_memory_rss{pod=~"support-prometheus-server-.*", namespace="support"})'
  )
]);

local prometheusCPU = graphPanel.new(
  'Prometheus CPU'
).addTargets([
  prometheus.target(
    'sum(rate(container_cpu_usage_seconds_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))'
  )
]);

local prometheusDiskSpace = graphPanel.new(
  'Prometheus Free Disk space',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(kubelet_volume_stats_available_bytes{namespace="support",persistentvolumeclaim="support-prometheus-server"})'
  )
]);

local prometheusNetwork = graphPanel.new(
  'Prometheus Network Usage',
  formatY1='bytes'
).addTargets([
  prometheus.target(
    'sum(rate(container_network_receive_bytes_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))',
    legendFormat='receive'
  ),
  prometheus.target(
    'sum(rate(container_network_send_bytes_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))',
    legendFormat='send'
  )
]);

dashboard.new(
  'JupyterHub Dashboard',
  tags=['jupyterhub'],
  uid='hub-dashboard',
  editable=true
).addTemplates(
  templates

).addPanel(row.new("Cluster Stats"), {y: 0}
).addPanel(userNodes, {x: 0, y: 0 } + standardDims
).addPanel(clusterUtilization, {x:12, y:0} + standardDims

).addPanel(row.new("Hub usage stats for $hub"), {y: 8},
).addPanel(currentRunningUsers, {x: 0, y: 8} + standardDims
).addPanel(userMemoryDistribution, {x: 12, y: 8} + standardDims
).addPanel(userAgeDistribution, {x: 0, y: 16} + standardDims

).addPanel(row.new("Hub Diagnostics for $hub"), {y: 24}
).addPanel(serverStartTimes, {x: 0, y: 24} + standardDims
).addPanel(hubResponseLatency, {x: 12, y: 24} + standardDims

).addPanel(hubCPU, {x: 0, y: 32} + standardDims
).addPanel(hubMemory, {x: 12, y: 32} + standardDims
).addPanel(proxyCPU, {x: 0, y: 40} + standardDims
).addPanel(proxyMemory, {x: 12, y: 40} + standardDims
).addPanel(usersPerNode, {x: 0, y: 48} + standardDims

).addPanel(row.new('Cluster Diagnostics'), {y: 56}
).addPanel(userNodesRSS, {x: 0, y: 56} + standardDims
).addPanel(userNodesCPU, {x: 12, y: 56} + standardDims
).addPanel(nonRunningPods, {x: 0, y: 64 } + standardDims
).addPanel(row.new('NFS diagnostics'), {y: 72}
).addPanel(userNodesNFSOps, {x: 0, y: 72 } + standardDims
).addPanel(userNodesIOWait, {x: 12, y:72} + standardDims
).addPanel(userNodesHighNFSOps, {x: 0, y: 80} + standardDims
).addPanel(nfsServerCPU, {x: 12, y: 80} + standardDims
).addPanel(nfsServerIOPS, {x: 0, y: 88} + standardDims
).addPanel(nfsServerWriteLatency, {x: 0, y: 96} + standardDims
).addPanel(nfsServerReadLatency, {x: 12, y: 96} + standardDims

).addPanel(row.new('Support system diagnostics'), {y: 104}
).addPanel(prometheusCPU, {x: 0, y: 104} + standardDims
).addPanel(prometheusMemory, {x: 12, y: 104} + standardDims
).addPanel(prometheusDiskSpace, {x: 0, y: 112} + standardDims
).addPanel(prometheusNetwork, {x: 12, y: 112} + standardDims
)
