#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;

local common = import './common.libsonnet';

local memoryUsage =
  common.tsOptions
  + ts.new('Memory Usage')
  + ts.panelOptions.withDescription(
    |||
      Per-user per-server memory usage
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          # exclude name="" because the same container can be reported
          # with both no name and `name=k8s_...`,
          # in which case sum() by (pod) reports double the actual metric
          container_memory_working_set_bytes{name!="", instance=~"$instance", namespace=~"$namespace"}
          * on (namespace, pod) group_left(container)
          group(
              kube_pod_labels{namespace=~"$namespace"}
          ) by (pod, namespace)
        ) by (pod, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ pod }} - ({{ namespace }})'),
  ]);


local cpuUsage =
  common.tsOptions
  + ts.new('CPU Usage')
  + ts.panelOptions.withDescription(
    |||
      Per-user per-server CPU usage
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          # exclude name="" because the same container can be reported
          # with both no name and `name=k8s_...`,
          # in which case sum() by (pod) reports double the actual metric
          irate(container_cpu_usage_seconds_total{name!="", instance=~"$instance"}[5m])
          * on (namespace, pod) group_left(container)
          group(
              kube_pod_labels{namespace=~"$namespace"}
          ) by (pod, namespace)
        ) by (pod, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ pod }} - ({{ namespace }})'),
  ]);

local memoryRequests =
  common.tsOptions
  + ts.new('Memory Requests')
  + ts.panelOptions.withDescription(
    |||
      Per-user per-server memory Requests
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_container_resource_requests{resource="memory", namespace=~"$namespace", node=~"$instance"}
        ) by (pod, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ pod }} - ({{ namespace }})'),
  ]);

local cpuRequests =
  common.tsOptions
  + ts.new('CPU Requests')
  + ts.panelOptions.withDescription(
    |||
      Per-user per-server CPU Requests
    |||
  )
  + ts.standardOptions.withUnit('percentunit')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_container_resource_requests{resource="cpu", namespace=~"$namespace", node=~"$instance"}
        ) by (pod, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ pod }} - ({{ namespace }})'),
  ]);

dashboard.new('Pod Diagnostics Dashboard')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withUid('pod-diagnostics-dashboard')
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.namespace,
  common.variables.instance,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      memoryUsage,
      cpuUsage,
      memoryRequests,
      cpuRequests,
    ],
    panelWidth=24,
    panelHeight=12,
  )
)
