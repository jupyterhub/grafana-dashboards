#!/usr/bin/env jsonnet -J vendor
// Deploys one dashboard - "JupyterHub dashboard",
// with useful stats about usage & diagnostics.
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local tablePanel = grafana.tablePanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local row = grafana.row;
local heatmapPanel = grafana.heatmapPanel;

local standardDims = { w: 12, h: 12 };

local templates = [
  template.datasource(
    name='PROMETHEUS_DS',
    query='prometheus',
    current={},
    hide='label',
  ),
];

local monthlyActiveUsers = graphPanel.new(
  'Active users (over 30 days)',
  bars=true,
  lines=false,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    // Removes any pods caused by stress testing
    |||
      count(
        sum(
          min_over_time(
            kube_pod_labels{
              label_app="jupyterhub",
              label_component="singleuser-server",
              label_hub_jupyter_org_username!~"(service|perf|hubtraf)-",
            }[30d]
          )
        ) by (pod)
      )
    |||,
    legendFormat='Active Users',
    interval='30d'
  ),
]);


local dailyActiveUsers = graphPanel.new(
  'Active users (over 24 hours)',
  bars=true,
  lines=false,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    // count singleuser-server pods
    |||
      count(
        sum(
          min_over_time(
            kube_pod_labels{
              label_app="jupyterhub",
              label_component="singleuser-server",
              label_hub_jupyter_org_username!~"(service|perf|hubtraf)-",
            }[1d]
          )
        ) by (pod)
      )
    |||,
    legendFormat='Active Users',
    interval='1d'
  ),
]);

local userDistribution = graphPanel.new(
  'User Login Count distribution (over 90d)',
  bars=true,
  lines=false,
  min=0,
  x_axis_mode='histogram',
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    // count singleuser-server pods
    |||
      sum(
        min_over_time(
          kube_pod_labels{
            label_app="jupyterhub",
            label_component="singleuser-server",
            label_hub_jupyter_org_username!~"(service|perf|hubtraf)-",
          }[90d]
        )
      ) by (pod)
    |||,
    legendFormat='User logins Login Count',
  ),
]);

local currentRunningUsers = graphPanel.new(
  'Current running users',
  legend_min=true,
  legend_max=true,
  legend_current=true,
  min=0,
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_status_phase{phase="Running"}
        * on(pod, namespace) kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server"}
      )
    |||,
    legendFormat='Users'
  ),
]);

// Disk Usage stats
local pvcPercentageUsed = graphPanel.new(
  'Running PVCs Percentage Used',
  bars=false,
  lines=true,
  min=0,
  time_from='now-30d',
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    |||
      (
        max by (persistentvolumeclaim,namespace)
          (kubelet_volume_stats_used_bytes)
        )
      /
      (
        max by (persistentvolumeclaim,namespace)
          (kubelet_volume_stats_capacity_bytes)
      )
      * 100
    |||,
    legendFormat='{{persistentvolumeclaim}}',
    instant=false,
  ),
]);

local pvcStats = tablePanel.new(
  'PVCs Stats',
  datasource='$PROMETHEUS_DS',
  styles=[
      {
        "alias": "Used",
        "pattern": "Value #A",
        "unit": "bytes",
        "type": "number",
      },
      {
        "alias": "Capacity",
        "pattern": "Value #B",
        "unit": "bytes",
        "type": "number",
      },
      {
        "alias": "Free",
        "color": "green",
        "pattern": "Value #C",
        "type": "number",
        "unit": "bytes",
      },
    ],
).addTargets([
  prometheus.target(
    "max by (persistentvolumeclaim,namespace) (kubelet_volume_stats_used_bytes)",
    format="table",
    instant=true,
    intervalFactor=1,
  ),
  prometheus.target(
    "max by (persistentvolumeclaim,namespace) (kubelet_volume_stats_capacity_bytes)",
    format="table",
    instant=true,
  ),
  prometheus.target(
    "max by (persistentvolumeclaim,namespace) (kubelet_volume_stats_available_bytes)",
    format="table",
    instant=true,
  ),
]);

local userRate = graphPanel.new(
  'Daily Use Rate (over last 24h)',
  datasource='$PROMETHEUS_DS'
).addTargets([
  prometheus.target(
    'rate(kubelet_volume_stats_used_bytes[1d])',
    legendFormat='{{namespace}} ({{persistentvolumeclaim}})',
  ),
]);

dashboard.new(
  'Usage Dashboard',
  uid='usage-dashboard',
  tags=['jupyterhub'],
  editable=true,
  time_from='now-30d',
).addTemplates(
  templates
)
.addPanel(
  row.new('User stats'), {},
).addPanel(
  monthlyActiveUsers, {},
).addPanel(
  dailyActiveUsers, {},
).addPanel(
  currentRunningUsers, {},
  // FIXME: This graph does not seem to make sense yet
  // ).addPanel(userDistribution, {}
).addPanel(
  row.new('Storage stats'), {},
).addPanel(
  pvcPercentageUsed, {}
).addPanel(
  userRate, {}
).addPanel(
  pvcStats, {}
)
