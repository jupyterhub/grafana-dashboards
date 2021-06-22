#!/usr/bin/env jsonnet -J vendor
# Deploys one dashboard - "JupyterHub dashboard",
# with useful stats about usage & diagnostics.
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
local prometheus = grafana.prometheus;
local template = grafana.template;
local row = grafana.row;
local heatmapPanel = grafana.heatmapPanel;

local standardDims = { w: 12, h: 12};

local templates = [
   template.datasource(
    'PROMETHEUS_DS',
    'prometheus',
    'Prometheus',
    hide='label',
   )
];


local monthlyActiveUsers = graphPanel.new(
  'Active users (over 30 days)',
  bars=true,
  lines=false
).addTargets([
  prometheus.target(
    # Removes any pods caused by stress testing
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
    interval="30d"
  )
]);


local dailyActiveUsers = graphPanel.new(
  'Active users (over 24 hours)',
  bars=true,
  lines=false
).addTargets([
  prometheus.target(
    # count singleuser-server pods
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
    interval="1d"
  )
]);

local userDistribution = graphPanel.new(
  'User Login Count distribution (over 90d)',
  bars=true,
  lines=false,
  x_axis_mode='histogram',
).addTargets([
  prometheus.target(
    # count singleuser-server pods
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
  )
]);

local currentRunningUsers = graphPanel.new(
  'Current running users',
  legend_min=true,
  legend_max=true,
  legend_current=true
).addTargets([
  prometheus.target(
    |||
      sum(
        kube_pod_status_phase{phase="Running"}
        * on(pod, namespace) kube_pod_labels{label_app="jupyterhub", label_component="singleuser-server"}
      )
    |||,
    legendFormat='Users'
  )
]);

dashboard.new(
  'Usage Dashboard',
  uid='usage-dashboard',
  tags=['jupyterhub'],
  editable=true,
  time_from='now-30d'
).addTemplates(
  templates

).addPanel(monthlyActiveUsers, {x: 12, y: 0} + standardDims
).addPanel(dailyActiveUsers, {x: 0, y: 12} + standardDims
).addPanel(currentRunningUsers, {x: 0, y: 24} + standardDims
# FIXME: This graph does not seem to make sense yet
// ).addPanel(userDistribution, {x: 0, y: 24} + standardDims
)
