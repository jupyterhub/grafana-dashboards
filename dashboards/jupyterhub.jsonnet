#!/usr/bin/env jsonnet -J ../vendor
// Deploys one dashboard - "JupyterHub dashboard",
// with useful stats about usage & diagnostics.
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local tablePanel = grafana.tablePanel;
local row = grafana.row;
local heatmapPanel = grafana.heatmapPanel;

local jupyterhub = import 'jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local templates = [
  template.datasource(
    name='PROMETHEUS_DS',
    query='prometheus',
    current=null,
    hide='label',
  ),
  template.new(
    'hub',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_service_labels{service="hub"}, namespace)',
    // Allow viewing dashboard for multiple combined hubs
    includeAll=true,
    multi=true
  ),
];


// Hub usage stats
local currentRunningUsers = graphPanel.new(
  'Current running users',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
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
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # exclude name="" because the same container can be reported
        # with both no name and `name=k8s_...`,
        # in which case sum() by (pod) reports double the actual metric
        container_memory_working_set_bytes{name!=""}
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
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        # exclude name="" because the same container can be reported
        # with both no name and `name=k8s_...`,
        # in which case sum() by (pod) reports double the actual metric
        irate(container_cpu_usage_seconds_total{name!=""}[5m])
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
  datasource='$PROMETHEUS_DS'
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
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'histogram_quantile(0.99, sum(rate(jupyterhub_request_duration_seconds_bucket{app="jupyterhub", namespace=~"$hub"}[5m])) by (le))',
    legendFormat='99th percentile'
  ),
  prometheus.target(
    'histogram_quantile(0.50, sum(rate(jupyterhub_request_duration_seconds_bucket{app="jupyterhub", namespace=~"$hub"}[5m])) by (le))',
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
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    // Metrics from hub seems to have `namespace` rather than just `namespace`
    'histogram_quantile(0.99, sum(rate(jupyterhub_server_spawn_duration_seconds_bucket{app="jupyterhub", namespace=~"$hub"}[5m])) by (le))',
    legendFormat='99th percentile'
  ),
  prometheus.target(
    'histogram_quantile(0.5, sum(rate(jupyterhub_server_spawn_duration_seconds_bucket{app="jupyterhub", namespace=~"$hub"}[5m])) by (le))',
    legendFormat='50th percentile'
  ),
]);

local usersPerNode = graphPanel.new(
  'Users per node',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
          # kube_pod_info.node identifies the pod node,
          # while kube_pod_labels.node is the metrics exporter's node
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
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_status_phase{phase!="Running", namespace=~"$hub"}
      ) by (phase)
    |||,
    legendFormat='{{phase}}'
  ),
]);

// Anomalous tables
local oldUserpods = tablePanel.new(
  'Very old user pods',
  description=|||
    User pods that have been running for a long time (>8h).

    This often indicates problems with the idle culler
  |||,
  transform='timeseries_to_rows',
  styles=[
    {
      pattern: 'Value',
      type: 'number',
      unit: 's',
      alias: 'Age',
    },
  ],
  sort={
    col: 2,
    desc: true,
  },
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      (
        time() - (kube_pod_created %s)
      )  > (8 * 60 * 60) # 8 hours is our threshold
    ||| % jupyterhub.onComponentLabel('singleuser-server'),
    legendFormat='{{namespace}}/{{pod}}',
    instant=true
  ),
]).hideColumn('Time');

local highCPUUserPods = tablePanel.new(
  'User Pods with high CPU usage (>0.5)',
  description=|||
    User pods using a lot of CPU

    This could indicate a runaway process consuming resources
    unnecessarily.
  |||,
  transform='timeseries_to_rows',
  styles=[
    {
      pattern: 'Value',
      type: 'number',
      unit: 'percentunit',
      alias: 'CPU usage',
    },
  ],
  sort={
    col: 2,
    desc: true,
  },
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      max( # Ideally we just want 'current' value, so max will do
        irate(container_cpu_usage_seconds_total[5m])
        %s
      ) by (namespace, pod) > 0.5
    ||| % jupyterhub.onComponentLabel('singleuser-server', group_left=''),
    legendFormat='{{namespace}}/{{pod}}',
    instant=true
  ),
]).hideColumn('Time');

local highMemoryUsagePods = tablePanel.new(
  'User pods with high memory usage (>80% of limit)',
  description=|||
    User pods getting close to their memory limit

    Once they hit their memory limit, user kernels will start dying.
  |||,
  transform='timeseries_to_rows',
  styles=[
    {
      pattern: 'Value',
      type: 'number',
      unit: 'percentunit',
      alias: '% of mem limit consumed',
    },
  ],
  sort={
    col: 2,
    desc: true,
  },
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      max( # Ideally we just want 'current', but max will do. This metric is a gauge, so sum is inappropriate
        container_memory_working_set_bytes
        %(selector)s
      ) by (namespace, pod)
      /
      sum(
        kube_pod_container_resource_limits_memory_bytes
        %(selector)s
      ) by (namespace, pod)
      > 0.8
    ||| % {
      selector: jupyterhub.onComponentLabel('singleuser-server', group_left=''),
    },
    legendFormat='{{namespace}}/{{pod}}',
    instant=true
  ),
]).hideColumn('Time');


dashboard.new(
  'JupyterHub Dashboard',
  tags=['jupyterhub'],
  uid='hub-dashboard',
  editable=true
).addTemplates(
  templates
).addPanel(
  row.new('Hub usage stats'), {}
).addPanel(
  currentRunningUsers, {}
).addPanel(
  userAgeDistribution, {}
).addPanel(
  userCPUDistribution, {},
).addPanel(
  userMemoryDistribution, {}
).addPanel(
  row.new('Hub Diagnostics'), {}
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
).addPanel(
  row.new('Anomalous user pods'), {},
).addPanel(
  oldUserpods, { h: standardDims.h * 1.5 },
).addPanel(
  highCPUUserPods, { h: standardDims.h * 1.5 },
).addPanel(
  highMemoryUsagePods, { h: standardDims.h * 1.5 },
)
