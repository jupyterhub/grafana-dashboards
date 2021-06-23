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

/*
 * Prometheus query for selecting pods
 *
 * @name componentLabel
 *
 * @param component The component being selected
 * @param cmp (default `'='`) The comparison to use for the component label, e.g. for exclusions.
 *
 * @return prometheus query string selecting pods for a certain component
 */
local componentLabel(component, cmp='=') =
  std.format(
    'kube_pod_labels{label_app="jupyterhub", label_component%s"%s", namespace="$hub"}',
    [
      cmp,
      component,
    ]
  );

/*
 * prometheus query join for filtering a metric to only pods for a given hub component
 *
 * @name onComponentLabel
 *
 * @param component The component being selected
 * @param cmp (default `'='`) The comparison to use for the component label, e.g. for exclusions.
 * @param group_left (optional) The body to use for a group_left on the join, e.g. `container` for `group_left(container)`
 * @param group_right (optional) The body to use for a group_right on the join, e.g. `container` for `group_right(container)`
 *
 * @return prometheus query string starting with `* on(namespace, pod)` to apply any metric only to pods of a given hub component
 */
local onComponentLabel(component, cmp='=', group_left=false, group_right=false) =

  std.format(
    '* on (namespace, pod) %s %s', [
      if group_left != false then
        std.format('group_left(%s)', [group_left])
      else if group_right != false then
        std.format('group_right(%s)', [group_right])
      else
        ''
      ,
      componentLabel(component, cmp=cmp),
    ]
  )
;


// Cluster-wide stats
local userNodes = graphPanel.new(
  'User Nodes',
  decimalsY1=0,
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
        %s
        and on (pod) (kube_pod_container_status_ready)
      ) / sum(
        kube_node_status_allocatable_memory_bytes{node=~".*user.*"}
      )
    ||| % onComponentLabel('singleuser-server'),
    legendFormat='User Pods'
  ),
  prometheus.target(
    |||
      sum(
        kube_pod_container_resource_requests_memory_bytes{node=~".*user.*"}
        %s
        and on (pod) (kube_pod_container_status_ready)
      ) / sum(
        kube_node_status_allocatable_memory_bytes{node=~".*user.*"}
      )
    ||| % onComponentLabel('.*placeholder', cmp='=~'),
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
        %s
      ) by (phase)
    ||| % onComponentLabel('singleuser-server', group_right='phase'),
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
    ||| % onComponentLabel('singleuser-server', group_left='container'),
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
    ||| % onComponentLabel('singleuser-server'),
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

/**
 * Creates a graph panel for a resource for one (or more) JupyterHub component(s).
 * The given metric will be summed across pods for the given component.
 * if `multi` a multi-component chart will be produced, with sums for each component.
 *
 * @name componentResourcePanel
 *
 * @param title The title of the graph panel.
 * @param metric The metric to be observed.
 * @param component The component to be measured (or excluded). Optional if `multi=true`, in which case it is an exclusion, otherwise required.
 * @param formatY1 (optional) Passthrough `formatY1` to `graphPanel.new`
 * @param decimalsY1 (optional) Passthrough `decimalsY1` to `graphPanel.new`
 * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
 *     The chart will have a legend table for each component.
 */
local componentResourcePanel(title, metric, component='', formatY1=null, decimalsY1=null, multi=false) = graphPanel.new(
  title,
  decimalsY1=decimalsY1,
  formatY1=formatY1,
  // show legend as a table with current, avg, max values
  legend_alignAsTable=true,
  legend_current=true,
  legend_avg=true,
  legend_max=true,
  legend_hideZero=true,
  // legend_values is required for any of the above to work
  legend_values=true,
  min=0,
).addTargets([
  prometheus.target(
    std.format(
      |||
        sum(
          %s
          %s
        ) by (label_component)
      |||,
      [
        metric,
        onComponentLabel(component, cmp=if multi then '!=' else '=', group_left='container, label_component'),
      ],
    ),
    legendFormat=if multi then '{{ label_component }}' else title,
  ),
],);

/**
 * Creates a memory (RSS) graph panel for one (or more) JupyterHub component(s).
 *
 * @name memoryPanel
 *
 * @param name The name of the resource. Used to create the title.
 * @param component The component to be measured (or excluded). Optional if `multi=true`, in which case it is an exclusion, otherwise required.
 * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
 *     The chart will have a legend table for each component.
 */
local memoryPanel(name, component, multi=false) = componentResourcePanel(
  std.format('%s Memory (RSS)', [name]),
  component=component,
  metric='container_memory_rss{name!=""}',
  formatY1='bytes',
  multi=multi,
);

/**
 * Creates a CPU usage graph panel for one (or more) JupyterHub component(s).
 *
 * @name cpuPanel
 *
 * @param name The name of the resource. Used to create the title.
 * @param component The component to be measured (or excluded). Optional if `multi=true`, in which case it is an exclusion, otherwise required.
 * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
 *     The chart will have a legend table for each component.
 */
local cpuPanel(name, component, multi=false) = componentResourcePanel(
  std.format('%s CPU', [name]),
  component=component,
  metric='irate(container_cpu_usage_seconds_total{name!=""}[5m])',
  // decimals=1 with percentunit means round to nearest 10%
  decimalsY1=1,
  formatY1='percentunit',
  multi=multi,
);

local proxyMemory = memoryPanel('Proxy', component='proxy');
local proxyCPU = cpuPanel('Proxy', component='proxy');
local hubMemory = memoryPanel('Hub', component='hub');
local hubCPU = cpuPanel('Hub', component='hub');

// with multi=true, component='singleuser-server' means all components *except* singleuser-server
local allComponentsMemory = memoryPanel('All JupyterHub Components', component='singleuser-server', multi=true);
local allComponentsCPU = cpuPanel('All JupyterHub Components', component='singleuser-server', multi=true);

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
    ||| % onComponentLabel('singleuser-server', group_right='node'),
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
  clusterUtilization, { x: standardDims.w, y: 0 } + standardDims

).addPanel(
  row.new('Hub usage stats for $hub'), { y: 8 },
).addPanel(
  currentRunningUsers, { x: 0, y: 8 } + standardDims
).addPanel(
  usersPerNode, { x: standardDims.w, y: 16 } + standardDims
).addPanel(
  userAgeDistribution, { x: 0, y: 16 } + standardDims
).addPanel(
  userMemoryDistribution, { x: standardDims.w, y: 8 } + standardDims

).addPanel(
  row.new('Hub Diagnostics for $hub'), { y: 24 }
).addPanel(
  serverStartTimes, { x: 0, y: 24 } + standardDims
).addPanel(
  hubResponseLatency, { x: standardDims.w, y: 24 } + standardDims

).addPanel(
  hubCPU, { x: 0, y: 32 } + standardDims
).addPanel(
  hubMemory, { x: standardDims.w, y: 32 } + standardDims
).addPanel(
  proxyCPU, { x: 0, y: 40 } + standardDims
).addPanel(
  proxyMemory, { x: standardDims.w, y: 40 } + standardDims
).addPanel(
  allComponentsCPU, { x: 0, y: 48 } + standardDims + { h: standardDims.h * 1.5 },
).addPanel(
  allComponentsMemory, { x: standardDims.w, y: 48 } + standardDims + { h: standardDims.h * 1.5 },

).addPanel(
  row.new('Cluster Diagnostics'), { y: 64 }
).addPanel(
  userNodesRSS, { x: 0, y: 64 } + standardDims
).addPanel(
  userNodesCPU, { x: standardDims.w, y: 64 } + standardDims
).addPanel(
  nonRunningPods, { x: 0, y: 72 } + standardDims
)
