#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'grafonnet/main.libsonnet';
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
          container_memory_working_set_bytes{name!="", instance=~"$instance"}
          * on (namespace, pod) group_left(container)
          group(
              kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace=~"$hub", pod=~"$user_pod"}
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
              kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace=~"$hub", pod=~"$user_pod"}
          ) by (pod, namespace)
        ) by (pod, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ pod }} - ({{ namespace }})'),
  ]);

local homedirSharedUsage =
  common.tsOptions
  + ts.new('Home Directory Usage (on shared home directories)')
  + ts.panelOptions.withDescription(
    |||
      Per user home directory size, when using a shared home directory.

      Requires https://github.com/yuvipanda/prometheus-dirsize-exporter to
      be set up.

      Similar to server pod names, user names will be *encoded* here
      using the escapism python library (https://github.com/minrk/escapism).
      You can unencode them with the following python snippet:

      from escapism import unescape
      unescape('<escaped-username>', '-')
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(
          dirsize_total_size_bytes{namespace="$hub"}
        ) by (directory, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ directory }} - ({{ namespace }})'),
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
          kube_pod_container_resource_requests{resource="memory", namespace=~"$hub", node=~"$instance"}
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
          kube_pod_container_resource_requests{resource="cpu", namespace=~"$hub", node=~"$instance"}
        ) by (pod, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ pod }} - ({{ namespace }})'),
  ]);

dashboard.new('User Diagnostics Dashboard')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withUid('user-pod-diagnostics-dashboard')
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.hub,
  common.variables.user_pod,
  common.variables.instance,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      memoryUsage,
      cpuUsage,
      homedirSharedUsage,
      memoryRequests,
      cpuRequests,
    ],
    panelWidth=24,
    panelHeight=16,
  )
)
