#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v10.4.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local prometheus = grafonnet.query.prometheus;
local table = grafonnet.panel.table;

local common = import './common.libsonnet';

local homedirUsage =
  table.new('Home directory usage')
  + table.panelOptions.withDescription(
    |||
      Home directory usage by various users on the hub.

      Requires an installation of https://github.com/yuvipanda/prometheus-dirsize-exporter to work.
      If this table is empty, your infrastructure administrator needs to deploy that exporter correctly.
    |||
  )
  + table.queryOptions.withTargets([
    // Last Modified
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        min(dirsize_latest_mtime{namespace=~"$hub"}) by (directory) * 1000
      |||
    )
    + prometheus.withInstant(true)  // Only fetch latest value
    + prometheus.withFormat('table')
    ,
    // Total Size
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(dirsize_total_size_bytes{namespace=~"$hub"}) by (directory)
      |||
    )
    + prometheus.withInstant(true)
    + prometheus.withFormat('table'),
    // % of total usage
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(dirsize_total_size_bytes{namespace=~"$hub"}) by (directory)
        /
        ignoring (directory) group_left sum(dirsize_total_size_bytes{namespace=~"$hub"})
      |||
    )
    + prometheus.withInstant(true)
    + prometheus.withFormat('table'),
    // Total number of files
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max(dirsize_entries_count{namespace=~"$hub"}) by (directory)
      |||
    )
    + prometheus.withInstant(true)
    + prometheus.withFormat('table'),
  ])
  // Transform table from multiple series with same key to one unified table with shared key 'directory'
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
      // all these are instant data query targets that only display latest
      // values. So we hide all the time values.
      excludeByName: {
        'Time 1': true,
        'Time 2': true,
        'Time 3': true,
        'Time 4': true,
      },
      // Tables do not use the legend keys, and show Value #N for each Time #N. We
      // explicitly rename these here. This depends on the ordering of these series
      // above, so if the ordering changes, so must this.
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
      // Set units for all the columns. These can not be set elsewhere for tables
      overrides: [
        {
          matcher: {
            id: 'byName',
            // This is name provided by the `renameByName` transform
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
            // This is name provided by the `renameByName` transform
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
            // This is name provided by the `renameByName` transform
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
            // This is name provided by the `renameByName` transform
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
