#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'grafonnet/main.libsonnet';
local dashboard = grafonnet.dashboard;
local singlestat = grafonnet.singlestat;
local graphPanel = grafonnet.graphPanel;
local prometheus = grafonnet.prometheus;
local tablePanel = grafonnet.tablePanel;
local row = grafonnet.row;
local heatmapPanel = grafonnet.heatmapPanel;

local common = import './common.libsonnet';
local jupyterhub = import 'jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local memoryUsage = graphPanel.new(
  'Memory Usage',
  description=|||
    Per-user per-server memory usage
  |||,
  formatY1='bytes',
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
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
    |||,
    legendFormat='{{ pod }} - ({{ namespace }})'
  ),
);

local cpuUsage = graphPanel.new(
  'CPU Usage',
  description=|||
    Per-user per-server CPU usage
  |||,
  formatY1='percentunit',
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
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
    |||,
    legendFormat='{{ pod }} - ({{ namespace }})'
  ),
);

local homedirSharedUsage = graphPanel.new(
  'Home Directory Usage (on shared home directories)',
  description=|||
    Per user home directory size, when using a shared home directory.

    Requires https://github.com/yuvipanda/prometheus-dirsize-exporter to
    be set up.

    Similar to server pod names, user names will be *encoded* here
    using the escapism python library (https://github.com/minrk/escapism).
    You can unencode them with the following python snippet:

    from escapism import unescape
    unescape('<escaped-username>', '-')
  |||,
  formatY1='bytes',
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
    |||
      max(
        dirsize_total_size_bytes{namespace="$hub"}
      ) by (directory, namespace)
    |||,
    legendFormat='{{ directory }} - ({{ namespace }})'
  ),
);

local memoryRequests = graphPanel.new(
  'Memory Requests',
  description=|||
    Per-user per-server memory Requests
  |||,
  formatY1='bytes',
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
    |||
      sum(
        kube_pod_container_resource_requests{resource="memory", namespace=~"$hub", node=~"$instance"}
      ) by (pod, namespace)
    |||,
    legendFormat='{{ pod }} - ({{ namespace }})'
  ),
);

local cpuRequests = graphPanel.new(
  'CPU Requests',
  description=|||
    Per-user per-server CPU Requests
  |||,
  formatY1='percentunit',
  datasource='$PROMETHEUS_DS'
).addTarget(
  prometheus.target(
    |||
      sum(
        kube_pod_container_resource_requests{resource="cpu", namespace=~"$hub", node=~"$instance"}
      ) by (pod, namespace)
    |||,
    legendFormat='{{ pod }} - ({{ namespace }})'
  ),
);

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
      memoryUsage,  // FIXME: previously specified as, is it ok now? { h: standardDims.h * 1.5, w: standardDims.w * 2 }
      cpuUsage,  // FIXME: previously specified as, is it ok now? { h: standardDims.h * 1.5, w: standardDims.w * 2 }
      homedirSharedUsage,  // FIXME: previously specified as, is it ok now? { h: standardDims.h * 1.5, w: standardDims.w * 2 }
      memoryRequests,  // FIXME: previously specified as, is it ok now? { h: standardDims.h * 1.5, w: standardDims.w * 2 }
      cpuRequests,  // FIXME: previously specified as, is it ok now? { h: standardDims.h * 1.5, w: standardDims.w * 2 }
    ],
    // FIXME: panelWidth and panelHeight specified like cluster.jsonnet without visual check
    panelWidth=12,
    panelHeight=8,
  )
)
