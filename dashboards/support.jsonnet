#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys a dashboard showing information about support resources
local grafonnet = import 'grafonnet/main.libsonnet';
local dashboard = grafonnet.dashboard;
local graphPanel = grafonnet.graphPanel;
local prometheus = grafonnet.prometheus;
local row = grafonnet.row;

local common = import './common.libsonnet';

// NFS Stats
local userNodesNFSOps = graphPanel.new(
  'User Nodes NFS Ops',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfs_requests_total[5m])) by (node) > 0',
    legendFormat='{{ node }}'
  ),
]);

local userNodesIOWait = graphPanel.new(
  'iowait % on each node',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfs_requests_total[5m])) by (node)',
    legendFormat='{{ node }}'
  ),
]);

local userNodesHighNFSOps = graphPanel.new(
  'NFS Operation Types on user nodes',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(node_nfs_requests_total[5m])) by (method) > 0',
    legendFormat='{{method}}'
  ),
]);

local nfsServerCPU = graphPanel.new(
  'NFS Server CPU',
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'avg(rate(node_cpu_seconds_total{job="prometheus-nfsd-server", mode!="idle"}[2m])) by (mode)',
    legendFormat='{{mode}}'
  ),
]);

local nfsServerIOPS = graphPanel.new(
  'NFS Server Disk ops',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
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
  'NFS Server disk write latency',
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(node_disk_write_time_seconds_total{job="prometheus-nfsd-server"}[5m])) by (device) / sum(rate(node_disk_writes_completed_total{job="prometheus-nfsd-server"}[5m])) by (device)',
    legendFormat='{{device}}'
  ),
]);

local nfsServerReadLatency = graphPanel.new(
  'NFS Server disk read latency',
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(node_disk_read_time_seconds_total{job="prometheus-nfsd-server"}[5m])) by (device) / sum(rate(node_disk_reads_completed_total{job="prometheus-nfsd-server"}[5m])) by (device)',
    legendFormat='{{device}}'
  ),
]);

// Support Metrics
local prometheusMemory = graphPanel.new(
  'Prometheus Memory (Working Set)',
  formatY1='bytes',
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(container_memory_working_set_bytes{pod=~"support-prometheus-server-.*", namespace="support"})'
  ),
]);

local prometheusCPU = graphPanel.new(
  'Prometheus CPU',
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(container_cpu_usage_seconds_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))'
  ),
]);

local prometheusDiskSpace = graphPanel.new(
  'Prometheus Free Disk space',
  formatY1='bytes',
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(kubelet_volume_stats_available_bytes{namespace="support",persistentvolumeclaim="support-prometheus-server"})'
  ),
]);

local prometheusNetwork = graphPanel.new(
  'Prometheus Network Usage',
  formatY1='bytes',
  decimals=0,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'sum(rate(container_network_receive_bytes_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))',
    legendFormat='receive'
  ),
  prometheus.target(
    'sum(rate(container_network_send_bytes_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))',
    legendFormat='send'
  ),
]);

dashboard.new('NFS and Support Information')
+ dashboard.withTags(['support', 'kubernetes'])
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      row.new('NFS diagnostics')
      + row.withPanels([
        userNodesNFSOps,
        userNodesIOWait,
        userNodesHighNFSOps,
        nfsServerCPU,
        nfsServerIOPS,
        nfsServerWriteLatency,
        nfsServerReadLatency,
      ]),
      row.new('Support system diagnostics')
      + row.withPanels([
        prometheusCPU,
        prometheusMemory,
        prometheusDiskSpace,
        prometheusNetwork,
      ]),
    ],
    // FIXME: panelWidth and panelHeight specified like cluster.jsonnet without visual check
    panelWidth=12,
    panelHeight=8,
  )
)
