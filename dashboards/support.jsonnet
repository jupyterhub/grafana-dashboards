#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys a dashboard showing information about support resources
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;
local row = grafonnet.panel.row;

local common = import './common.libsonnet';

// NFS Stats
local userNodesNFSOps =
  common.tsOptions
  + ts.new('User Nodes NFS Ops')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_nfs_requests_total[5m])) by (node) > 0
      |||
    )
    + prometheus.withLegendFormat('{{ node }}'),
  ]);

local userNodesIOWait =
  common.tsOptions
  + ts.new('iowait % on each node')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_nfs_requests_total[5m])) by (node)
      |||
    )
    + prometheus.withLegendFormat('{{ node }}'),
  ]);

local userNodesHighNFSOps =
  common.tsOptions
  + ts.new('NFS Operation Types on user nodes')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_nfs_requests_total[5m])) by (method) > 0
      |||
    )
    + prometheus.withLegendFormat('{{ method }}'),
  ]);

local nfsServerCPU =
  common.tsOptions
  + ts.new('NFS Server CPU')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        avg(rate(node_cpu_seconds_total{job="prometheus-nfsd-server", mode!="idle"}[2m])) by (mode)
      |||
    )
    + prometheus.withLegendFormat('{{ mode }}'),
  ]);

local nfsServerIOPS =
  common.tsOptions
  + ts.new('NFS Server Disk ops')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_nfsd_disk_bytes_read_total[5m]))
      |||
    )
    + prometheus.withLegendFormat('Read'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_nfsd_disk_bytes_written_total[5m]))
      |||
    )
    + prometheus.withLegendFormat('Write'),
  ]);

local nfsServerWriteLatency =
  common.tsOptions
  + ts.new('NFS Server disk write latency')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_disk_write_time_seconds_total{job="prometheus-nfsd-server"}[5m])) by (device) / sum(rate(node_disk_writes_completed_total{job="prometheus-nfsd-server"}[5m])) by (device)
      |||
    )
    + prometheus.withLegendFormat('{{ device }}'),
  ]);

local nfsServerReadLatency =
  common.tsOptions
  + ts.new('NFS Server disk read latency')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(node_disk_read_time_seconds_total{job="prometheus-nfsd-server"}[5m])) by (device) / sum(rate(node_disk_reads_completed_total{job="prometheus-nfsd-server"}[5m])) by (device)
      |||
    )
    + prometheus.withLegendFormat('{{ device }}'),
  ]);

// Support Metrics

// FIXME: Can we transition to using the function to generate the prometheus memory and cpu panels?
//
//        Currently held back by hardcoded label selection on the label
//        "component" and selection on a single label instead of optionally
//        multiple.
//
//local prometheusMemory = jupyterhub.memoryPanel(
//  'Prometheus Memory (Working Set)',
//  // app.kubernetes.io/component: server
//  // app.kubernetes.io/name: prometheus
//  component='singleuser-server',
//  multi=false,
//);

local prometheusMemory =
  common.tsOptions
  + ts.new('Prometheus Memory (Working Set)')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(container_memory_working_set_bytes{pod=~"support-prometheus-server-.*", namespace="support"})
      |||
    ),
  ]);

local prometheusCPU =
  common.tsOptions
  + ts.new('Prometheus CPU')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(container_cpu_usage_seconds_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))
      |||
    ),
  ]);

local prometheusDiskSpace =
  common.tsOptions
  + ts.new('Prometheus Free Disk space')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kubelet_volume_stats_available_bytes{namespace="support",persistentvolumeclaim="support-prometheus-server"})
      |||
    ),
  ]);

local prometheusNetwork =
  common.tsOptions
  + ts.new('Prometheus Network Usage')
  + ts.standardOptions.withUnit('bytes')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(container_network_receive_bytes_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))
      |||
    )
    + prometheus.withLegendFormat('receive'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(rate(container_network_send_bytes_total{pod=~"support-prometheus-server-.*",namespace="support"}[5m]))
      |||
    )
    + prometheus.withLegendFormat('send'),
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
    panelWidth=12,
    panelHeight=10,
  )
)
