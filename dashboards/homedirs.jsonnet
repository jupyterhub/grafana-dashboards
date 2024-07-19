#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'grafonnet/main.libsonnet';
local dashboard = grafonnet.dashboard;
local prometheus = grafonnet.query.prometheus;
local table = grafonnet.panel.table;

local common = import './common.libsonnet';

local homedirUsage =
  table.new('Home directory usage')
  + table.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        min(dirsize_latest_mtime{namespace=~"$hub"}) by (directory) * 1000
      |||
    )
    + prometheus.withLegendFormat('Last Modified')
    + prometheus.withInstant(true)
    + prometheus.withFormat('table')
    ,
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(dirsize_total_size_bytes{namespace=~"$hub"}) by (directory)
      |||
    )
    + prometheus.withLegendFormat('Total Size')
    + prometheus.withInstant(true)
    + prometheus.withFormat('table'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(dirsize_total_size_bytes{namespace=~"$hub"}) by (directory)
        /
        ignoring (directory) group_left sum(dirsize_total_size_bytes{namespace=~"$hub"})
      |||
    )
    + prometheus.withLegendFormat('% of total space used')
    + prometheus.withInstant(true)
    + prometheus.withFormat('table'),
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(dirsize_entries_count{namespace=~"$hub"}) by (directory)
      |||
    )
    + prometheus.withLegendFormat('Number of entries')
    + prometheus.withInstant(true)
    + prometheus.withFormat('table'),
  ])
  + table.queryOptions.withTransformations([
    table.queryOptions.transformation.withId('joinByField')
    + table.queryOptions.transformation.withOptions({
      byField: 'directory',
      mode: 'outer',
    }),

    table.queryOptions.transformation.withId('organize')
    + table.queryOptions.transformation.withOptions({
      // Grafana adds an individual 'Time #N' column for each timeseries we get.
      // They all display the same time. We don't care about time *at all*, since
      // all these are instant data query targets. So we hide all the time values.
      excludeByName: {
        'Time 1': true,
        'Time 2': true,
        'Time 3': true,
        'Time 4': true,
      },
      // Explicitly rename the column headers, so they do not display 'Value #N'
      renameByName: {
        'Value #A': 'Last Modified',
        'Value #B': 'Size',
        'Value #C': '% of total space usage',
        'Value #D': 'Number of Entries',
      },
    }),
  ])
  + {
    fieldConfig: {
      overrides: [
        {
          matcher: {
            id: 'byName',
            options: 'Size',
          },
          properties: [
            {
              id: 'unit',
              value: 'bytes',
            },
          ],
        },
        {
          matcher: {
            id: 'byName',
            options: 'Last Modified',
          },
          properties: [
            {
              id: 'unit',
              value: 'dateTimeFromNow',
            },
          ],
        },
        {
          matcher: {
            id: 'byName',
            options: 'Number of Entries',
          },
          properties: [
            {
              id: 'unit',
              value: 'short',
            },
          ],
        },
        {
          matcher: {
            id: 'byName',
            options: '% of total space usage',
          },
          properties: [
            {
              id: 'unit',
              value: 'percentunit',
            },
          ],
        },
      ],
    },
  };

dashboard.new('Home Directory Usage Dashboard')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.hub,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid([
    homedirUsage,
  ], panelWidth=24, panelHeight=24)
)
