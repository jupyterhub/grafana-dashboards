#!/usr/bin/env -S jsonnet -J ../vendor --tla-code 'datasources=["prometheus-test"]'
// Deploys one dashboard - "Global usage dashboard",
// with useful stats about usage across all datasources
local grafonnet = import 'grafonnet/main.libsonnet';
local dashboard = grafonnet.dashboard;
local barGauge = grafonnet.panel.barGauge;
local prometheus = grafonnet.query.prometheus;

function(datasources)
  local weeklyActiveUsers =
    barGauge.new('Active users (over 7 days)')
    + barGauge.standardOptions.color.withMode('fixed')
    + barGauge.standardOptions.color.withFixedColor('green')
    + barGauge.queryOptions.withInterval('7d')
    + barGauge.queryOptions.withTargets([
      prometheus.new(
        x,
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
      )
      + prometheus.withLegendFormat(x)
      // Create a target for each datasource
      for x in datasources
    ]);

  dashboard.new('Global Usage Dashboard')
  + dashboard.withUid('global-usage-dashboard')
  + dashboard.withTags(['jupyterhub', 'global'])
  + dashboard.withEditable(true)
  + dashboard.time.withFrom('now-7d')
  + dashboard.withPanels(
    grafonnet.util.grid.makeGrid(
      [
        weeklyActiveUsers,
      ],
      panelWidth=24,
      panelHeight=10,
    )
  )
