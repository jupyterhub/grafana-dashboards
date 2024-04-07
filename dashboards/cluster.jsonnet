#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys a dashboard showing cluster-wide information
local grafonnet = import 'grafonnet/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local barChart = grafonnet.panel.barChart;
local prometheus = grafonnet.query.prometheus;
local row = grafonnet.panel.row;

local common = import './common.libsonnet';

// Cluster-wide stats
local userNodes =
  common.tsOptions
  + ts.new('Node Count')
  + ts.panelOptions.withDescription(
    |||
      Number of nodes in each nodepool in this cluster
    |||
  )
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
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
      |||
      % std.repeat([common.nodePoolLabels], 2)
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat),
  ]);

local userPods =
  common.tsOptions
  + ts.new('Running Users')
  + ts.panelOptions.withDescription(
    |||
      Number of currently running users per hub.

      Common shapes this visualization may take:
      1. A large number of users starting servers at exactly the same time will be
        visible here as a single spike, and may cause stability issues. Since
        they share the same cluster, such spikes happening on a *different* hub
        may still affect your hub.
    |||
  )
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
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
    )
    + prometheus.withLegendFormat('{{namespace}}'),
  ]);

local nodepoolMemoryCommitment =
  common.tsOptions
  + ts.new('Node Pool Memory commitment %')
  + ts.panelOptions.withDescription(
    |||
      % of memory in each node pool guaranteed to user workloads.

      Common shapes:
      1. If this is consistently low (<50%), you are paying for cloud compute that you do not
        need. Consider reducing the size of your nodes, or increasing the amount of
        memory guaranteed to your users. Some variability based on time of day is to be expected.
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  + ts.standardOptions.withMax(1)
  + ts.queryOptions.withTargets([
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
      |||
      % std.repeat([common.nodePoolLabels], 6),
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat),
  ]);

local nodepoolCPUCommitment =
  common.tsOptions
  + ts.new('Node Pool CPU commitment %')
  + ts.panelOptions.withDescription(
    |||
      % of CPU in each node pool guaranteed to user workloads.

      Most commonly, JupyterHub workloads are *memory bound*, not CPU bound. So this is
      not a particularly helpful graph.

      Common shapes:
      1. If this is *consistently high* but shaped differently than your memory commitment
        graph, consider changing your CPU requirements.
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  + ts.standardOptions.withMax(1)
  + ts.queryOptions.withTargets([
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
      |||
      % std.repeat([common.nodePoolLabels], 6),
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat),
  ]);

local nodeCPUCommit =
  common.tsOptions + ts.new('Node CPU Commit %')
  + ts.panelOptions.withDescription(
    |||
      % of each node guaranteed to pods on it
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  + ts.standardOptions.withMax(1)
  + ts.queryOptions.withTargets([
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
      |||
      % std.repeat([common.nodePoolLabels], 6),
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat + '/{{node}}'),
  ]);

local nodeMemoryCommit =
  common.tsOptions
  + ts.new('Node Memory Commit %')
  + ts.panelOptions.withDescription(
    |||
      % of each node guaranteed to pods on it.

      When this hits 100%, the autoscaler will spawn a new node and the scheduler will stop
      putting pods on the old node.
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  + ts.standardOptions.withMax(1)
  + ts.queryOptions.withTargets([
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
      |||
      % std.repeat([common.nodePoolLabels], 6),
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat + '/{{node}}'),
  ]);

local nodeMemoryUtil =
  common.tsOptions
  + ts.new('Node Memory Utilization %')
  + ts.panelOptions.withDescription(
    |||
      % of available Memory currently in use
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  + ts.standardOptions.withMax(1)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        1 - (
          sum (
            # Memory that can be allocated to processes when they need
            node_memory_MemFree_bytes + # Unused bytes
            node_memory_Cached_bytes + # Shared memory + temporary disk cache
            node_memory_Buffers_bytes # Very temporary buffer memory cache for disk i/o
          ) by (node)
          /
          sum(node_memory_MemTotal_bytes) by (node)
        ) * on(node) group_left(%s)
        group(
          kube_node_labels
        ) by (node, %s)
      |||
      % std.repeat([common.nodePoolLabels], 2),
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat + '/{{node}}'),
  ]);

local nodeCPUUtil =
  common.tsOptions
  + ts.new('Node CPU Utilization %')
  + ts.panelOptions.withDescription(
    |||
      % of available CPU currently in use
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  // max=1 may be exceeded in exceptional circumstances like evicted pods
  // but full is still full. This gets a better view of 'fullness' most of the time.
  // If the commitment is "off the chart" it doesn't super matter by how much.
  + ts.standardOptions.withMax(1)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        (
          sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (node)
          /
          sum(kube_node_status_capacity{resource="cpu"}) by (node)
        ) * on (node) group_left(%s)
        group(
          kube_node_labels
        ) by (node, %s)
      |||
      % std.repeat([common.nodePoolLabels], 2),
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat + '/{{node}}'),
  ]);

local nodeOOMKills =
  common.barChartOptions
  + barChart.new('Out of Memory Kill Count')
  + barChart.panelOptions.withDescription(
    |||
      Number of Out of Memory (OOM) kills in a given node.

      When users use up more memory than they are allowed, the notebook kernel they
      were running usually gets killed and restarted. This graph shows the number of times
      that happens on any given node, and helps validate that a notebook kernel restart was
      infact caused by an OOM
    |||
  )
  + barChart.standardOptions.withDecimals(0)
  + barChart.queryOptions.withTargets([
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
      |||
      % std.repeat([common.nodePoolLabels], 2)
    )
    + prometheus.withLegendFormat(common.nodePoolLabelsLegendFormat + '/{{node}}'),
  ]);

local nonRunningPods =
  common.barChartOptions
  + barChart.new('Pods not in Running state')
  + barChart.panelOptions.withDescription(
    |||
      Pods in states other than 'Running'.

      In a functional clusters, pods should not be in non-Running states for long.
    |||,
  )
  + barChart.standardOptions.withDecimals(0)
  + barChart.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_status_phase{phase!="Running"}) by (phase)
      |||
    )
    + prometheus.withLegendFormat('{{phase}}'),
  ]);

dashboard.new('Cluster Information')
+ dashboard.withTags(['jupyterhub', 'kubernetes'])
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      row.new('Cluster Utilization')
      + row.withPanels([
        userPods,  // FIXME: previously width 24
        userNodes,
        nodepoolMemoryCommitment,
        nodepoolCPUCommitment,
      ]),
      row.new('Cluster Health')
      + row.withPanels([
        nonRunningPods,
        nodeOOMKills,
      ]),
      row.new('Node Stats')
      + row.withPanels([
        nodeCPUCommit,
        nodeMemoryCommit,
        nodeCPUUtil,
        nodeMemoryUtil,
      ]),
    ],
    panelWidth=12,
    panelHeight=10,
  )
)
