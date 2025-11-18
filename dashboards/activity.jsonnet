#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;
local row = grafonnet.panel.row;
local var = grafonnet.dashboard.variable;

local common = import './common.libsonnet';

local activeUserTsOptions =
  common.tsOptions
  + ts.standardOptions.withDecimals(0)
  // stacking is used here as the total number of users is as relevant as the
  // number of users per hub
  + ts.fieldConfig.defaults.custom.stacking.withMode('normal')
  // stepAfter is used here as these metrics indicate what has happened the time
  // before the metric is read
  + ts.fieldConfig.defaults.custom.withLineInterpolation('stepAfter')
  + ts.panelOptions.withDescription(
    |||
      Number of unique users who were active within the preceding period.
    |||
  )
;

local runningServers =
  common.tsOptions
  + ts.new('Running Servers')
  + ts.standardOptions.withDecimals(0)
  + ts.fieldConfig.defaults.custom.stacking.withMode('normal')
  + ts.fieldConfig.defaults.custom.withLineInterpolation('stepBefore')
  + ts.panelOptions.withDescription(
    |||
      Number of running user servers at any given time.

      Note that a single user could have multiple servers running if the
      JupyterHub is configured with `c.JupyterHub.allow_named_servers = True`.
    |||
  )
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(
          jupyterhub_running_servers{namespace=~"$hub"}
        ) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ namespace }}'),
  ]);

local dailyActiveUsers =
  activeUserTsOptions
  + ts.new('Daily Active Users')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(
          jupyterhub_active_users{period="24h", namespace=~"$hub"}
        ) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ namespace }}'),
  ]);

local weeklyActiveUsers =
  activeUserTsOptions
  + ts.new('Weekly Active Users')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(
          jupyterhub_active_users{period="7d", namespace=~"$hub"}
        ) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ namespace }}'),
  ]);

local monthlyActiveUsers =
  activeUserTsOptions
  + ts.new('Monthly Active Users')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(
          jupyterhub_active_users{period="30d", namespace=~"$hub"}
        ) by (namespace)
      |||,
    )
    + prometheus.withLegendFormat('{{ namespace }}'),
  ]);


dashboard.new('Activity')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withUid('jhgd-activity')
+ dashboard.withEditable(true)
+ dashboard.time.withFrom('now-90d')
+ dashboard.withVariables([
  /*
   * This dashboard repeats the single row it defines once per datasource, due
   * to that we allow multiple or all datasources to be selected in this
   * dashboard but not in others. This repeating is only usable for repeating
   * panels or rows, as individual panels can't repeat queries based on the
   * available datasources.
  */
  common.variables.prometheus
  + var.query.selectionOptions.withMulti()
  + var.query.selectionOptions.withIncludeAll(),
  /*
   * The hub variable will behave weirdly when multiple datasources are selected,
   * only showing hubs from one datasource. This is currently an accepted issue.
   * Many deployments of these dashboard will only be in a Grafana instance with
   * a single prometheus datasource.
  */
  common.variables.hub,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      row.new('Activity ($PROMETHEUS_DS)')
      + row.withPanels([
        runningServers,
        dailyActiveUsers,
        weeklyActiveUsers,
        monthlyActiveUsers,
      ])
      + row.withRepeat('PROMETHEUS_DS'),
    ],
    panelWidth=6,
    panelHeight=8,
  )
)
