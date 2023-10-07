#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys a dashboard showing cluster-wide information
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v10.0.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local barChart = grafonnet.panel.barChart;
local prometheus = grafonnet.query.prometheus;
local var = grafonnet.dashboard.variable;
local row = grafonnet.panel.row;

local jupyterhub = import './jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local variables = [
  var.datasource.new(
    'PROMETHEUS_DS', 'prometheus'
  ),
];

// Cluster-wide stats
local userNodes = ts.new(
  'Node Count'
) + {
  description: 'Number of nodes in each nodepool in this cluster',
  options: {
    tooltip: {
      mode: 'multi',
    },
  },
  fieldConfig: {
    min: 0,
    defaults: {
      // Only show whole numbers
      decimals: 0,
      custom: {
        stacking: {
          mode: 'normal',
        },
      },

    },
  },
} + ts.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      # sum up all nodes by nodepool
      sum(
        # kube_pod_labels comes from
        # https://github.com/kubernetes/kube-state-metrics, and there is a particular
        # label (kubernetes_node) that lists the node on which the kube-state-metrics pod
        # s running! So that's totally irrelevant to these queries, but when a nodepool
        # is rotated it caused there to exist two metrics with the same node value (which
        # we care about) but different kubernetes_node values (because kube-state-metrics
        # was running in a different node, even though we don't care about that). This
        # group really just drops all labels except the two we care about to
        # avoid messing things up.
        group(
          kube_node_labels
        ) by (node, %s)
      ) by (%s)
    ||| % std.repeat([jupyterhub.nodePoolLabels], 2)
  ) + prometheus.withLegendFormat(jupyterhub.nodePoolLabelsLegendFormat),
]);

local userPods = ts.new(
  'Running Users',
) + {
  description: |||
    Count of running users, grouped by namespace
  |||,
} + ts.fieldConfig.defaults.custom.withStacking(
  true
) + ts.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      # Sum up all running user pods by namespace
      sum(
        # Grab a list of all running pods.
        # The group aggregator always returns "1" for the number of times each
        # unique label appears in the time series. This is desirable for this
        # use case because we're merely identifying running pods by name,
        # not how many times they might be running.
        group(
          kube_pod_status_phase{phase="Running"}
        ) by (pod)
        * on (pod) group_right() group(
          kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server"}
        ) by (namespace, pod)
      ) by (namespace)
    |||,
  ) + prometheus.withLegendFormat('{{namespace}}'),
]);

local clusterMemoryCommitment = ts.new(
  'Memory commitment %',
) + {
  description: |||
    % of total memory in the cluster currently requested by to non-placeholder pods.

    If autoscaling is efficient, this should be a fairly constant, high number (>70%).
  |||,
  fieldConfig: {
    defaults: {
      min: 0,
      // max=1 may be exceeded in exceptional circumstances like evicted pods
      // but full is still full. This gets a better view of 'fullness' most of the time.
      // If the commitment is "off the chart" it doesn't super matter by how much.
      max: 1,
      unit: 'percentunit',
    },
  },
} + ts.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      sum(
        # Get individual container memory requests
        kube_pod_container_resource_requests{resource="memory"}
        # Add node pool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (%s)
      /
      sum(
        # Total allocatable memory on a node
        kube_node_status_allocatable{resource="memory"}
        # Add nodepool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
      ) by (%s)
    ||| % std.repeat([jupyterhub.nodePoolLabels], 6),
  ) + prometheus.withLegendFormat(jupyterhub.nodePoolLabelsLegendFormat),
]);

local clusterCPUCommitment = ts.new(
  'CPU commitment %',
) + {
  description: |||
    % of total CPU in the cluster currently requested by to non-placeholder pods.

    JupyterHub users mostly are capped by memory, so this is not super useful.
  |||,
  fieldConfig: {
    defaults: {
      unit: 'percentunit',
      min: 0,
      // max=1 may be exceeded in exceptional circumstances like evicted pods
      // but full is still full. This gets a better view of 'fullness' most of the time.
      // If the commitment is "off the chart" it doesn't super matter by how much.
      max: 1,
    },
  },
} + ts.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      sum(
        # Get individual container memory requests
        kube_pod_container_resource_requests{resource="cpu"}
        # Add node pool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (%s)
      /
      sum(
        # Total allocatable CPU on a node
        kube_node_status_allocatable{resource="cpu"}
        # Add nodepool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
      ) by (%s)
    ||| % std.repeat([jupyterhub.nodePoolLabels], 6),
  ) + prometheus.withLegendFormat(jupyterhub.nodePoolLabelsLegendFormat),
]);

local nodeCPUCommit = ts.new(
  'Node CPU Commit %'
) + {
  description: |||
    % of each node guaranteed to pods on it
  |||,
  fieldConfig: {
    defaults: {
      unit: 'percentunit',
      min: 0,
      // max=1 may be exceeded in exceptional circumstances like evicted pods
      // but full is still full. This gets a better view of 'fullness' most of the time.
      // If the commitment is "off the chart" it doesn't super matter by how much.
      max: 1,
    },
  },
} + ts.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      sum(
        # Get individual container cpu requests
        kube_pod_container_resource_requests{resource="cpu"}
        # Add node pool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (node, %s)
      /
      sum(
        # Total allocatable CPU on a node
        kube_node_status_allocatable{resource="cpu"}
        # Add nodepool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
      ) by (node, %s)
    ||| % std.repeat([jupyterhub.nodePoolLabels], 6),
  ) + prometheus.withLegendFormat(jupyterhub.nodePoolLabelsLegendFormat + '/{{node}}'),
]);

local nodeMemoryCommit = ts.new(
  'Node Memory Commit %'
) + {
  description: |||
    % of each node guaranteed to pods on it.

    When this hits 100%, the autoscaler will spawn a new node and the scheduler will stop
    putting pods on the old node.
  |||,
  fieldConfig: {
    defaults: {
      unit: 'percentunit',
      min: 0,
      // max=1 may be exceeded in exceptional circumstances like evicted pods
      // but full is still full. This gets a better view of 'fullness' most of the time.
      // If the commitment is "off the chart" it doesn't super matter by how much.
      max: 1,
    },
  },
} + ts.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      sum(
        # Get individual container memory requests
        kube_pod_container_resource_requests{resource="memory"}
        # Add node pool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
        # Ignore containers from pods that aren't currently running or scheduled
        # FIXME: This isn't the best metric here, evaluate what is.
        and on (pod) kube_pod_status_scheduled{condition='true'}
        # Ignore user and node placeholder pods
        and on (pod) kube_pod_labels{label_component!~'user-placeholder|node-placeholder'}
      ) by (node, %s)
      /
      sum(
        # Total allocatable memory on a node
        kube_node_status_allocatable{resource="memory"}
        # Add nodepool name as label
        * on(node) group_left(%s)
        # group aggregator ensures that node names are unique per
        # pool.
        group(
          kube_node_labels
        ) by (node, %s)
      ) by (node, %s)
    ||| % std.repeat([jupyterhub.nodePoolLabels], 6),
  ) + prometheus.withLegendFormat(jupyterhub.nodePoolLabelsLegendFormat + '/{{node}}'),
]);

// // Cluster diagnostics
// local nodeMemoryUtil = graphPanel.new(
//   'Node Memory Utilization %',
//   formatY1='percentunit',
//   description=|||
//     % of available Memory currently in use
//   |||,
//   min=0,
//   // since this is actual measured utilization, it should not be able to exceed max=1
//   max=1,
//   datasource='$PROMETHEUS_DS'
// ).addTargets([
//   prometheus.target(
//     |||
//       1 - (
//         sum (
//           # Memory that can be allocated to processes when they need
//           node_memory_MemFree_bytes + # Unused bytes
//           node_memory_Cached_bytes + # Shared memory + temporary disk cache
//           node_memory_Buffers_bytes # Very temporary buffer memory cache for disk i/o
//         ) by (node)
//         /
//         sum(node_memory_MemTotal_bytes) by (node)
//       )
//     |||,
//     legendFormat='{{node}}'
//   ),
// ]);

// local nodeCPUUtil = graphPanel.new(
//   'Node CPU Utilization %',
//   formatY1='percentunit',
//   description=|||
//     % of available CPUs currently in use
//   |||,
//   min=0,
//   // since this is actual measured utilization, it should not be able to exceed max=1
//   max=1,
//   datasource='$PROMETHEUS_DS'
// ).addTargets([
//   prometheus.target(
//     |||
//       sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (node)
//       /
//       sum(kube_node_status_capacity{resource="cpu"}) by (node)
//     |||,
//     legendFormat='{{ node }}'
//   ),
// ]);

// local nodeOOMKills = graphPanel.new(
//   'Out of Memory kill count',
//   description=|||
//     Number of Out of Memory (OOM) kills in a given node.

//     When users use up more memory than they are allowed, the notebook kernel they
//     were running usually gets killed and restarted. This graph shows the number of times
//     that happens on any given node, and helps validate that a notebook kernel restart was
//     infact caused by an OOM
//   |||,
//   min=0,
//   legend_hideZero=true,  // Declutter graph by hiding 0s, which we don't care about
//   decimals=0,
//   datasource='$PROMETHEUS_DS'
// ).addTargets([
//   prometheus.target(
//     |||
//       # We use [2m] here, as node_exporter usually scrapes things at 1min intervals
//       # And oom kills are distinct events, so we want to see 'how many have just happened',
//       # rather than average over time.
//       increase(node_vmstat_oom_kill[2m])
//     |||,
//     legendFormat='{{ node }}'
//   ),
// ]);

local nodeOOMKills = barChart.new(
  'Out of Memory Kill Count'
) + {
  description: |||
    Number of Out of Memory (OOM) kills in a given node.

    When users use up more memory than they are allowed, the notebook kernel they
    were running usually gets killed and restarted. This graph shows the number of times
    that happens on any given node, and helps validate that a notebook kernel restart was
    infact caused by an OOM
  |||,
  fieldConfig: {
    defaults: {
      unit: 'short',
      min: 0,
      decimals: 0,
    },
  },
} + barChart.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      # We use [2m] here, as node_exporter usually scrapes things at 1min intervals
      # And oom kills are distinct events, so we want to see 'how many have just happened',
      # rather than average over time.
      increase(node_vmstat_oom_kill[2m]) * on(node) group_left(%s)
      group(
        kube_node_labels
      )
      by(node, %s)
    ||| % std.repeat([jupyterhub.nodePoolLabels], 2)
  ) + prometheus.withLegendFormat(jupyterhub.nodePoolLabelsLegendFormat + '/{{node}}'),
]);

local nonRunningPods = barChart.new(
  'Pods not in Running state'
) + {
  description: |||
    Pods in states other than 'Running'.

    In a functional clusters, pods should not be in non-Running states for long.
  |||,
  fieldConfig: {
    defaults: {
      unit: 'short',
      min: 0,
      decimals: 0,
    },
  },
} + barChart.queryOptions.withTargets([
  prometheus.new(
    '$PROMETHEUS_DS',
    |||
      sum(kube_pod_status_phase{phase!="Running"}) by (phase)
    |||
  ) + prometheus.withLegendFormat('{{phase}}'),
]);

dashboard.new(
  'Cluster Information',
) + dashboard.withTags(
  ['jupyterhub', 'kubernetes']
) + dashboard.withEditable(
  true
) + dashboard.withVariables(
  variables
) + dashboard.withPanels(
  grafonnet.util.grid.makeGrid([
    row.new(
      'Cluster Utilization'
    ) + row.withPanels([
      userPods,
      userNodes,
      clusterMemoryCommitment,
      clusterCPUCommitment,
    ]),
    row.new('Cluster Health') + row.withPanels([
      nonRunningPods,
      nodeOOMKills,
    ]),
    row.new('Node Stats') + row.withPanels([
      nodeCPUCommit,
      nodeMemoryCommit,
    ]),
    // nodeCPUUtil,
    // nodeMemoryUtil,
  ], panelWidth=12, panelHeight=8)
)
