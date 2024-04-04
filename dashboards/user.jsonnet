#!/usr/bin/env -S jsonnet -J ../vendor
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local tablePanel = grafana.tablePanel;
local row = grafana.row;
local heatmapPanel = grafana.heatmapPanel;

local jupyterhub = import 'jupyterhub.libsonnet';
local standardDims = jupyterhub.standardDims;

local templates = [
  template.datasource(
    name='PROMETHEUS_DS',
    query='prometheus',
    current=null,
    hide='label',
  ),
  template.new(
    'hub',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_service_labels{service="hub"}, namespace)',
    // Allow viewing dashboard for multiple combined hubs
    includeAll=true,
    multi=true
  ) + {
    // Explicitly set '$hub' to be `.*` when 'All' is selected, as we always use `$hub` as a regex
    allValue: '.*',
  },
  template.new(
    'user_pod',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace=~"$hub"}, pod)',
    // Allow viewing dashboard for multiple users
    includeAll=true,
    multi=true
  ) + {
    // Explicitly set '$user_pod' to be `.*` when 'All' is selected, as we always use `$user_pod` as a regex
    allValue: '.*',
  },
  template.new(
    // Queries should use the 'instance' label when querying metrics that
    // come from collectors present on each node - such as node_exporter or
    // container_ metrics, and use the 'node' label when querying metrics
    // that come from collectors that are present once per cluster, like
    // kube_state_metrics.
    'instance',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_node_info, node)',
    // Allow viewing dashboard for multiple nodes
    includeAll=true,
    multi=true
  ) + {
    // Explicitly set '$instance' to be `.*` when 'All' is selected, as we always use `$instance` as a regex
    allValue: '.*',
  },
];


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

dashboard.new(
  'User Diagnostics Dashboard',
  tags=['jupyterhub'],
  uid='user-pod-diagnostics-dashboard',
  editable=true
).addTemplates(
  templates
).addPanel(
  memoryUsage, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
).addPanel(
  cpuUsage, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
).addPanel(
  homedirSharedUsage, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
).addPanel(
  memoryRequests, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
).addPanel(
  cpuRequests, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
)
