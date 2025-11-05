#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys a dashboard showing information about NFS server and Prometheus.
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;
local row = grafonnet.panel.row;

local common = import './common.libsonnet';

// NFS Stats
local nfsReqPerNode =
  common.tsOptions
  + ts.new('NFS requests per node')
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

local nfsReqPerOp =
  common.tsOptions
  + ts.new('NFS requests per operation')
  + ts.standardOptions.withDecimals(0)
  + ts.standardOptions.withUnit('percentunit')
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
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_cpu_usage_seconds_total{pod=~".*home-nfs.*", container!=""}[5m])) by (namespace, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{pod}} ({{container}})'),
  ]);

local nfsServerMemory =
  common.tsOptions
  + ts.new('NFS Server Memory (Working Set)')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(container_memory_working_set_bytes{pod=~".*home-nfs-.*", container!=""}) by (namespace, pod, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{pod}} ({{container}})'),
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
        sum(container_memory_working_set_bytes{pod=~".*prometheus-server-.*", container!=""}) by (namespace, pod, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{pod}} ({{container}})'),
  ]);

local prometheusCPU =
  common.tsOptions
  + ts.new('Prometheus CPU')
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_cpu_usage_seconds_total{pod=~".*prometheus-server-.*", container!=""}[5m])) by (namespace, pod, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{pod}} ({{container}})'),
  ]);

local prometheusDiskSpace =
  common.tsOptions
  + ts.new('Prometheus Free Disk space')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kubelet_volume_stats_available_bytes{persistentvolumeclaim=~".*-prometheus-server"}) by (namespace, persistentvolumeclaim)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{persistentvolumeclaim}}'),
  ]);

local prometheusNetwork =
  common.tsOptions
  + ts.new('Prometheus Network Usage')
  + ts.standardOptions.withUnit('binBps')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_network_receive_bytes_total{pod=~".*-prometheus-server-.*"}[5m])) by (namespace, pod)
      |||
    )
    + prometheus.withLegendFormat('receive ({{namespace}}: {{pod}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_network_transmit_bytes_total{pod=~".*-prometheus-server-.*"}[5m])) by (namespace, pod)
      |||
    )
    + prometheus.withLegendFormat('transmit ({{namespace}}: {{pod}})'),
  ]);

dashboard.new('NFS and Prometheus Information')
+ dashboard.withTags(['kubernetes', 'nfs', 'prometheus'])
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      row.new('NFS usage diagnostics')
      + row.withPanels([
        nfsReqPerNode,
        nfsReqPerOp,
      ]),
      row.new('NFS server diagnostics')
      + row.withPanels([
        nfsServerIOPS,
        nfsServerCPU,
        nfsServerMemory,
        nfsServerWriteLatency,
        nfsServerReadLatency,
      ]),
      row.new('Prometheus server diagnostics')
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
