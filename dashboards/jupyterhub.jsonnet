#!/usr/bin/env jsonnet -J ../vendor
// Deploys one dashboard - "JupyterHub dashboard",
// with useful stats about usage & diagnostics.
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local row = grafana.row;
local heatmapPanel = grafana.heatmapPanel;

local standardDims = { w: 12, h: 8 };

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
    // FIXME: Grafana needs a manual 'refresh variables' before it populates this.
    // Maybe another API call?
    current='jupyterhub'
  ),
];

// Cluster-wide stats
local userNodes = graphPanel.new(
  'User Nodes',
  legend_show=false,
  min=0,
).addTarget(
  prometheus.target(
    expr='sum(kube_node_info{node=~".*user.*"})',
  )
);

local clusterUtilization = graphPanel.new(
  'Cluster Utilization',
  formatY1='percentunit',
  min=0,
  stack=true,
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_container_resource_requests_memory_bytes{node=~".*user.*"}
        and on (pod, namespace) kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace="$hub"}
        and on (pod) (kube_pod_container_status_ready)
      ) / sum(
        kube_node_status_allocatable_memory_bytes{node=~".*user.*"}
      )
    |||,
    legendFormat='User Pods'
  ),
  prometheus.target(
    |||
      sum(
        kube_pod_container_resource_requests_memory_bytes{node=~".*user.*"}
        and on (pod, namespace) kube_pod_labels{label_app="jupyterhub", label_component=~".*placeholder", namespace="$hub"}
        and on (pod) (kube_pod_container_status_ready)
      ) / sum(
        kube_node_status_allocatable_memory_bytes{node=~".*user.*"}
      )
    |||,
    legendFormat='Placeholder Pods'
  ),
]);

// Hub usage stats
local currentRunningUsers = graphPanel.new(
  'Current running users',
  decimals=0,
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_status_phase{phase="Running"}
        * on (pod, namespace) group_right(phase) kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace="$hub"}

      ) by (phase)
    |||,
    legendFormat='{{phase}}'
  ),
]);

local userMemoryDistribution = heatmapPanel.new(
  'User memory usage distribution',
  // xBucketSize and interval must match to get correct values out of heatmaps
  xBucketSize='600s',
  yAxis_format='bytes',
  yAxis_min=0,
  color_colorScheme='interpolateViridis',
).addTargets([
  prometheus.target(
    |||
      sum(
        container_memory_working_set_bytes
        * on (pod, namespace) group_left(container) kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace="$hub"}
      ) by (pod)
    |||,
    interval='600s',
    intervalFactor=1,
  ),
]);

local userAgeDistribution = heatmapPanel.new(
  'User active age distribution',
  // xBucketSize and interval must match to get correct values out of heatmaps
  xBucketSize='600s',
  yAxis_format='s',
  yAxis_min=0,
  color_colorScheme='interpolateViridis',
).addTargets([
  prometheus.target(
    |||
      (
        time()
        - (
          kube_pod_created
          * on (pod, namespace) kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace="$hub"}
        )
      )
    |||,
    interval='600s',
    intervalFactor=1,
  ),
]);

// Hub diagnostics
local hubResponseLatency = graphPanel.new(
  'Hub response latency',
  formatY1='s',
  min=0,
).addTargets([
  prometheus.target(
    'histogram_quantile(0.99, sum(rate(jupyterhub_request_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat='99th percentile'
  ),
  prometheus.target(
    'histogram_quantile(0.50, sum(rate(jupyterhub_request_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat='50th percentile'
  ),
]);

local proxyMemory = graphPanel.new(
  'Proxy Memory (RSS)',
  formatY1='bytes',
  legend_show=false,
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        container_memory_rss{name!=""}
        * on (pod, namespace) group_left(container) kube_pod_labels{label_app="jupyterhub", label_component="proxy", namespace="$hub"}
      )
    |||,
  ),
]);

local proxyCPU = graphPanel.new(
  'Proxy CPU',
  // decimals=1 with percentunit means round to nearest 10%
  decimalsY1=1,
  formatY1='percentunit',
  legend_show=false,
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        rate(container_cpu_usage_seconds_total{name!=""}[5m])
        * on (pod, namespace) group_left(container) kube_pod_labels{label_app="jupyterhub", label_component="proxy", namespace="$hub"}
      )
    |||,
  ),
]);

local hubMemory = graphPanel.new(
  'Hub Memory (RSS)',
  formatY1='bytes',
  legend_show=false,
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        container_memory_rss{name!=""}
        * on (pod, namespace) group_left(container) kube_pod_labels{label_app="jupyterhub", label_component="hub", namespace="$hub"}
      )
    |||,
  ),
]);

local hubCPU = graphPanel.new(
  'Hub CPU',
  // decimals=1 means round to nearest 10%
  decimalsY1=1,
  formatY1='percentunit',
  legend_show=false,
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        rate(container_cpu_usage_seconds_total{name!=""}[5m])
        * on (pod, namespace) group_left(container) kube_pod_labels{label_app="jupyterhub", label_component="hub", namespace="$hub"}
      )
    |||,
  ),
]);

local allComponentsMemory = graphPanel.new(
  'All Hub component Memory (RSS)',
  formatY1='bytes',
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        container_memory_rss{name!=""}
        * on (pod, namespace) group_left(container, label_component) kube_pod_labels{label_app="jupyterhub", label_component!="singleuser-server", namespace="$hub"}
      ) by (label_component)
    |||,
    legendFormat='{{ label_component }}',
  ),
]);

local allComponentsCPU = graphPanel.new(
  'All Hub component CPU',
  // decimals=1 means round to nearest 10%
  decimalsY1=1,
  formatY1='percentunit',
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
        rate(container_cpu_usage_seconds_total{name!=""}[5m])
        * on (pod, namespace) group_left(container, label_component) kube_pod_labels{label_app="jupyterhub", label_component!="singleuser-server", namespace="$hub"}
      ) by (label_component)
    |||,
    legendFormat='{{ label_component }}',
  ),
]);

local serverStartTimes = graphPanel.new(
  'Server Start Times',
  formatY1='s',
  lines=false,
  min=0,
  points=true,
  pointradius=2,
).addTargets([
  prometheus.target(
    // Metrics from hub seems to have `kubernetes_namespace` rather than just `namespace`
    'histogram_quantile(0.99, sum(rate(jupyterhub_server_spawn_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat='99th percentile'
  ),
  prometheus.target(
    'histogram_quantile(0.5, sum(rate(jupyterhub_server_spawn_duration_seconds_bucket{app="jupyterhub", kubernetes_namespace="$hub"}[5m])) by (le))',
    legendFormat='50th percentile'
  ),
]);

local usersPerNode = graphPanel.new(
  'Users per node',
  decimals=0,
  min=0,
).addTargets([
  prometheus.target(
    |||
      sum(
          # kube_pod_info.node identifies the pod node,
          # while kube_pod_labels.kubernetes_node is the metrics exporter's node
          kube_pod_info{node!=""}
          * on(pod, namespace) group_right(node)  kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server"}
      ) by (node)
    |||,
    legendFormat='{{ node }}'
  ),
]);


// Cluster diagnostics
local userNodesRSS = graphPanel.new(
  'User Nodes Memory usage (RSS)',
  formatY1='bytes',
  min=0,
).addTargets([
  prometheus.target(
    'sum(node_memory_Active_bytes{kubernetes_node=~".*user.*"}) by (kubernetes_node)',
    legendFormat='{{kubernetes_node}}'
  ),
]);

//
local userNodesCPU = graphPanel.new(
  'User Nodes CPU',
  formatY1='short',
  decimalsY1=0,
  min=0,
).addTargets([
  prometheus.target(
    'sum(rate(node_cpu_seconds_total{mode!="idle", kubernetes_node=~".*user.*"}[5m])) by (kubernetes_node)',
    legendFormat='{{kubernetes_node}}'
  ),
]);


local nonRunningPods = graphPanel.new(
  'Non Running User Pods',
  decimalsY1=0,
  min=0,
  stack=true,
).addTargets([
  prometheus.target(
    'sum(kube_pod_status_phase{phase!="Running"}) by (phase)',
    legendFormat='{{phase}}'
  ),
]);


dashboard.new(
  'JupyterHub Dashboard',
  tags=['jupyterhub'],
  uid='hub-dashboard',
  editable=true
).addTemplates(
  templates

).addPanel(
  row.new('Cluster Stats'), { y: 0 }
).addPanel(
  userNodes, { x: 0, y: 0 } + standardDims
).addPanel(
  clusterUtilization, { x: 12, y: 0 } + standardDims

).addPanel(
  row.new('Hub usage stats for $hub'), { y: 8 },
).addPanel(
  currentRunningUsers, { x: 0, y: 8 } + standardDims
).addPanel(
  userMemoryDistribution, { x: 12, y: 8 } + standardDims
).addPanel(
  userAgeDistribution, { x: 0, y: 16 } + standardDims

).addPanel(
  row.new('Hub Diagnostics for $hub'), { y: 24 }
).addPanel(
  serverStartTimes, { x: 0, y: 24 } + standardDims
).addPanel(
  hubResponseLatency, { x: 12, y: 24 } + standardDims

).addPanel(
  hubCPU, { x: 0, y: 32 } + standardDims
).addPanel(
  hubMemory, { x: 12, y: 32 } + standardDims
).addPanel(
  proxyCPU, { x: 0, y: 40 } + standardDims
).addPanel(
  proxyMemory, { x: 12, y: 40 } + standardDims
).addPanel(
  allComponentsCPU, { x: 0, y: 48 } + standardDims
).addPanel(
  allComponentsMemory, { x: 12, y: 48 } + standardDims
).addPanel(
  usersPerNode, { x: 0, y: 56 } + standardDims

).addPanel(
  row.new('Cluster Diagnostics'), { y: 56 }
).addPanel(
  userNodesRSS, { x: 0, y: 56 } + standardDims
).addPanel(
  userNodesCPU, { x: 12, y: 56 } + standardDims
).addPanel(
  nonRunningPods, { x: 0, y: 64 } + standardDims
)
