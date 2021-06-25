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

local jupyterhub = import 'jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local templates = [
  template.new(
    'hub',
    datasource='prometheus',
    query='label_values(kube_service_labels{service="hub"}, namespace)',
  ),
];


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
        %s
      ) by (phase)
    ||| % jupyterhub.onComponentLabel('singleuser-server', group_right='phase'),
    legendFormat='{{phase}}',
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
        %s
      ) by (pod)
    ||| % jupyterhub.onComponentLabel('singleuser-server', group_left='container'),
    interval='600s',
    intervalFactor=1,
  ),
]);

local userCPUDistribution = heatmapPanel.new(
  'User CPU usage distribution',
  // xBucketSize and interval must match to get correct values out of heatmaps
  xBucketSize='600s',
  yAxis_format='percentunit',
  yAxis_min=0,
  color_colorScheme='interpolateViridis',
).addTargets([
  prometheus.target(
    |||
      sum(
        irate(container_cpu_usage_seconds_total[5m])
        %s
      ) by (pod)
    ||| % jupyterhub.onComponentLabel('singleuser-server', group_left='container'),
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
          %s
        )
      )
    ||| % jupyterhub.onComponentLabel('singleuser-server'),
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


// with multi=true, component='singleuser-server' means all components *except* singleuser-server
local allComponentsMemory = jupyterhub.memoryPanel('All JupyterHub Components', component='singleuser-server', multi=true);
local allComponentsCPU = jupyterhub.cpuPanel('All JupyterHub Components', component='singleuser-server', multi=true);

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
          %s
      ) by (node)
    ||| % jupyterhub.onComponentLabel('singleuser-server', group_right='node'),
    legendFormat='{{ node }}'
  ),
]);


local nonRunningPods = graphPanel.new(
  'Non Running Pods',
  description=|||
    Pods in a non-running state in the hub's namespace.

    Pods stuck in non-running states often indicate an error condition
  |||,
  decimalsY1=0,
  min=0,
  stack=true,
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_status_phase{phase!="Running", namespace="$hub"}
      ) by (phase)
    |||,
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
  row.new('Hub usage stats for $hub'), {}
).addPanel(
  currentRunningUsers, {}
).addPanel(
  userAgeDistribution, {}
).addPanel(
  userCPUDistribution, {},
).addPanel(
  userMemoryDistribution, {}
).addPanel(
  row.new('Hub Diagnostics for $hub'), {}
).addPanel(
  serverStartTimes, {}
).addPanel(
  hubResponseLatency, {}
).addPanel(
  allComponentsCPU, { h: standardDims.h * 1.5 },
).addPanel(
  allComponentsMemory, { h: standardDims.h * 1.5 },
).addPanel(
  nonRunningPods, {}
).addPanel(
  usersPerNode, {}
)
