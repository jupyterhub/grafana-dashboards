// Deploys one dashboard - "Global usage dashboard",
// with useful stats about usage across all datasources
local grafana = import '../vendor/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local barGaugePanel = grafana.barGaugePanel;
local prometheus = grafana.prometheus;

function(datasources)
local weeklyActiveUsers = barGaugePanel.new(
  'Active users (over 7 days)',
  datasource='-- Mixed --',
  thresholds=[
    {
    "value": 0,
    "color": "yellow"
    },
    {
    "value": 50,
    "color": "green"
    }
  ],
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
            }[7d]
          )
        ) by (pod)
      )
    |||,
    legendFormat=x,
    interval='7d',
    datasource=x
  ),
  // Create a target for each datasource
  for x in datasources
]);

dashboard.new(
  'Global Usage Dashboard',
  uid='global-usage-dashboard',
  tags=['jupyterhub', 'global'],
  editable=true,
  time_from='now-7d',
).addPanel(
  weeklyActiveUsers, {},
)