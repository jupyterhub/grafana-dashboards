#!/usr/bin/env jsonnet -J vendor
// Deploys one dashboard - "JupyterHub dashboard",
// with useful stats about usage & diagnostics.
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;
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
  monthlyActiveUsers, {},
).addPanel(
  dailyActiveUsers, {},
).addPanel(
  currentRunningUsers, {},
  // FIXME: This graph does not seem to make sense yet
  // ).addPanel(userDistribution, {}
)
