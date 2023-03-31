#!/usr/bin/env jsonnet -J ../vendor
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
  ),
  template.new(
    'user_pod',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server", namespace=~"$hub"}, pod)',
    // Allow viewing dashboard for multiple users
    includeAll=true,
    multi=true
  ),
  template.new(
    'instance',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_node_info, node)',
    // Allow viewing dashboard for multiple nodes
    includeAll=true,
    multi=true
  ),
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
      ) by (pod)
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
      ) by (pod)
    |||,
    legendFormat='{{ pod }} - ({{ namespace }})'
  ),
);


dashboard.new(
  'User Pod Diagnostics Dashboard',
  tags=['jupyterhub'],
  uid='user-pod-diagnostics-dashboard',
  editable=true
).addTemplates(
  templates
).addPanel(
  memoryUsage, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
).addPanel(
  cpuUsage, { h: standardDims.h * 1.5, w: standardDims.w * 2 }
)
