#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys a dashboard showing information about NFS server and Prometheus.
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;
local row = grafonnet.panel.row;

local common = import './common.libsonnet';


// NFS usage diagnostics
// ---------------------
local nfsReqPerNode =
  common.tsOptions
  + ts.new('NFS requests, per node')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(node_nfs_requests_total[5m])) by (node) > 0
      |||
    )
    + prometheus.withLegendFormat('{{ node }}'),
  ]);

local nfsReqPerOp =
  common.tsOptions
  + ts.new('NFS requests, per operation')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(node_nfs_requests_total[5m])) by (method) > 0
      |||
    )
    + prometheus.withLegendFormat('{{ method }}'),
  ]);


// NFS server diagnostics
// ----------------------
local nfsServerCPU =
  common.tsOptions
  + common.tsRequestLimitStylingOverrides
  + ts.new('NFS server CPU usage')
  + ts.panelOptions.withDescription(
    |||
      The measured unit are CPU cores, and they are written out with SI prefixes, so 100m means 0.1 CPU cores.
    |||
  )
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_cpu_usage_seconds_total{pod=~".*home-nfs.*", container!=""}[5m])) by (namespace, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{container}}'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_requests{pod=~".*home-nfs-.*", container!="", resource="cpu"}) by (namespace, container)
        and on() vector($show_requests) == 1
      |||
    )
    + prometheus.withLegendFormat('request ({{namespace}}: {{container}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_limits{pod=~".*home-nfs-.*", container!="", resource="cpu"}) by (namespace, container)
        and on() vector($show_limits) == 1
      |||
    )
    + prometheus.withLegendFormat('limit ({{namespace}}: {{container}})'),
  ]);

local nfsServerMemory =
  common.tsOptions
  + common.tsRequestLimitStylingOverrides
  + ts.new('NFS server memory usage (working set)')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(container_memory_working_set_bytes{pod=~".*home-nfs-.*", container!=""}) by (namespace, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{container}}'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_requests{pod=~".*home-nfs-.*", container!="", resource="memory"}) by (namespace, container)
        and on() vector($show_requests) == 1
      |||
    )
    + prometheus.withLegendFormat('request ({{namespace}}: {{container}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_limits{pod=~".*home-nfs-.*", container!="", resource="memory"}) by (namespace, container)
        and on() vector($show_limits) == 1
      |||
    )
    + prometheus.withLegendFormat('limit ({{namespace}}: {{container}})'),
  ]);

local nfsServerDiskSpace =
  common.tsOptions
  + common.tsCapacityStylingOverrides
  + ts.new('NFS server used disk space')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kubelet_volume_stats_used_bytes{persistentvolumeclaim=~".*home-nfs"}) by (namespace, persistentvolumeclaim)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{persistentvolumeclaim}}'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=~".*home-nfs"}) by (namespace, persistentvolumeclaim)
        and on() vector($show_capacity) == 1
      |||
    )
    + prometheus.withLegendFormat('capacity ({{namespace}}: {{persistentvolumeclaim}})'),
  ]);

local nfsServerNetwork =
  common.tsOptions
  + ts.new('NFS server network usage')
  + ts.standardOptions.withUnit('binBps')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_network_receive_bytes_total{pod=~".*-home-nfs-.*"}[5m])) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('receive ({{namespace}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_network_transmit_bytes_total{pod=~".*-home-nfs-.*"}[5m])) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('transmit ({{namespace}})'),
  ]);


// Prometheus server diagnostics
// -----------------------------
local promServerCPU =
  common.tsOptions
  + common.tsRequestLimitStylingOverrides
  + ts.new('Prometheus server CPU usage')
  + ts.panelOptions.withDescription(
    |||
      The measured unit are CPU cores, and they are written out with SI prefixes, so 100m means 0.1 CPU cores.
    |||
  )
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_cpu_usage_seconds_total{pod=~".*prometheus-server-.*", container!=""}[5m])) by (namespace, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{container}}'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_requests{pod=~".*prometheus-server-.*", container!="", resource="cpu"}) by (namespace, container)
        and on() vector($show_requests) == 1
      |||
    )
    + prometheus.withLegendFormat('request ({{namespace}}: {{container}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_limits{pod=~".*prometheus-server-.*", container!="", resource="cpu"}) by (namespace, container)
        and on() vector($show_limits) == 1
      |||
    )
    + prometheus.withLegendFormat('limit ({{namespace}}: {{container}})'),
  ]);

local promServerMemory =
  common.tsOptions
  + common.tsRequestLimitStylingOverrides
  + ts.new('Prometheus server memory usage (working set)')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(container_memory_working_set_bytes{pod=~".*prometheus-server-.*", container!=""}) by (namespace, container)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{container}}'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_requests{pod=~".*prometheus-server-.*", container!="", resource="memory"}) by (namespace, container)
        and on() vector($show_requests) == 1
      |||
    )
    + prometheus.withLegendFormat('request ({{namespace}}: {{container}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kube_pod_container_resource_limits{pod=~".*prometheus-server-.*", container!="", resource="memory"}) by (namespace, container)
        and on() vector($show_limits) == 1
      |||
    )
    + prometheus.withLegendFormat('limit ({{namespace}}: {{container}})'),
  ]);

local promServerDiskSpace =
  common.tsOptions
  + common.tsCapacityStylingOverrides
  + ts.new('Prometheus server used disk space')
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kubelet_volume_stats_used_bytes{persistentvolumeclaim=~".*-prometheus-server"}) by (namespace, persistentvolumeclaim)
      |||
    )
    + prometheus.withLegendFormat('{{namespace}}: {{persistentvolumeclaim}}'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=~".*-prometheus-server"}) by (namespace, persistentvolumeclaim)
        and on() vector($show_capacity) == 1
      |||
    )
    + prometheus.withLegendFormat('capacity ({{namespace}}: {{persistentvolumeclaim}})'),
  ]);

local promServerNetwork =
  common.tsOptions
  + ts.new('Prometheus server network usage')
  + ts.standardOptions.withUnit('binBps')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_network_receive_bytes_total{pod=~".*-prometheus-server-.*"}[5m])) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('receive ({{namespace}})'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(irate(container_network_transmit_bytes_total{pod=~".*-prometheus-server-.*"}[5m])) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('transmit ({{namespace}})'),
  ]);


// Dashboard definition
// --------------------
dashboard.new('NFS usage, NFS server, and Prometheus server diagnostics')
+ dashboard.withTags(['kubernetes', 'nfs', 'jupyterhub-home-nfs', 'prometheus'])
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.show_requests,
  common.variables.show_limits,
  common.variables.show_capacity,
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
        nfsServerCPU,
        nfsServerMemory,
        nfsServerDiskSpace,
        nfsServerNetwork,
      ]),
      row.new('Prometheus server diagnostics')
      + row.withPanels([
        promServerCPU,
        promServerMemory,
        promServerDiskSpace,
        promServerNetwork,
      ]),
    ],
    panelWidth=12,
    panelHeight=10,
  )
)
