local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local ts = grafonnet.panel.timeSeries;
local barChart = grafonnet.panel.barChart;
local barGauge = grafonnet.panel.barGauge;
local heatmap = grafonnet.panel.heatmap;
local table = grafonnet.panel.table;
local var = grafonnet.dashboard.variable;

/**
  * Local utility functions
  */
local _getDashedLineOverride(pattern, color) = {
  matcher: {
    id: 'byRegexp',
    options: pattern,
  },
  properties: [
    {
      id: 'color',
      value: {
        mode: 'fixed',
        fixedColor: color,
      },
    },
    {
      id: 'custom.fillOpacity',
      value: 0,
    },
    {
      id: 'custom.lineStyle',
      value: {
        fill: 'dash',
        dash: [10, 10],
      },
    },
  ],
};

{
  /**
   * Declare common panel options
   *
   * For the panels we configure, we want:
   * - Y axes to start from 0            -- withMin(0)
   * - Legend tooltip to show all values -- withTooltip({mode: 'multi'})
   *
   * ref: https://grafana.com/docs/grafana/v11.1/panels-visualizations/configure-panel-options/
   */

  // grafana ref:   https://grafana.com/docs/grafana/v11.1/panels-visualizations/visualizations/time-series/
  // grafonnet ref: https://grafana.github.io/grafonnet/API/panel/timeSeries/index.html
  tsOptions:
    ts.standardOptions.withMin(0)
    + ts.options.withTooltip({ mode: 'multi' })
    + ts.fieldConfig.defaults.custom.withLineInterpolation('stepAfter')
    + ts.fieldConfig.defaults.custom.withFillOpacity(10)
  ,

  // grafana ref:   https://grafana.com/docs/grafana/v11.1/panels-visualizations/visualizations/bar-chart/
  // grafonnet ref: https://grafana.github.io/grafonnet/API/panel/barChart/index.html
  barChartOptions:
    barChart.standardOptions.withMin(0)
    + barChart.options.withTooltip({ mode: 'multi' })
  ,

  // grafana ref:   https://grafana.com/docs/grafana/v11.1/panels-visualizations/visualizations/bar-gauge/
  // grafonnet ref: https://grafana.github.io/grafonnet/API/panel/barGauge/index.html
  barGaugeOptions:
    barGauge.standardOptions.withMin(0)
  ,

  // grafana ref:   https://grafana.com/docs/grafana/v11.1/panels-visualizations/visualizations/heatmap/
  // grafonnet ref: https://grafana.github.io/grafonnet/API/panel/heatmap/index.html
  heatmapOptions:
    heatmap.options.withCalculate(true)
    + heatmap.queryOptions.withMaxDataPoints('60')  // need to match xBuckets
    + heatmap.options.color.withScheme('Greens')
    + heatmap.options.calculation.xBuckets.withMode('count')
    + heatmap.options.calculation.xBuckets.withValue('60')  // need to match withMaxDataPoints
    + heatmap.options.calculation.yBuckets.withMode('count')
    + heatmap.options.calculation.yBuckets.withValue('12')
  ,

  tableOptions:
    table.standardOptions.withMin(0)
  ,

  tsRequestLimitStylingOverrides:
    ts.standardOptions.withOverrides([
      _getDashedLineOverride('/request.*/', 'orange'),
      _getDashedLineOverride('/limit.*/', 'red'),
    ])
  ,

  tsCapacityStylingOverrides:
    ts.standardOptions.withOverrides([
      _getDashedLineOverride('/capacity.*/', 'red'),
    ])
  ,

  tsPodStateStylingOverrides:
    ts.standardOptions.withOverrides([
      {
        matcher: { id: 'byName', options: 'Pending' },
        properties: [{
          id: 'color',
          value: {
            fixedColor: 'yellow',
            mode: 'fixed',
          },
        }],
      },
      {
        matcher: { id: 'byName', options: 'Running' },
        properties: [{
          id: 'color',
          value: {
            fixedColor: 'blue',
            mode: 'fixed',
          },
        }],
      },
      {
        matcher: { id: 'byName', options: 'Succeeded' },
        properties: [{
          id: 'color',
          value: {
            fixedColor: 'green',
            mode: 'fixed',
          },
        }],
      },
      {
        matcher: { id: 'byName', options: 'Unknown' },
        properties: [{
          id: 'color',
          value: {
            fixedColor: 'orange',
            mode: 'fixed',
          },
        }],
      },
      {
        matcher: { id: 'byName', options: 'Failed' },
        properties: [{
          id: 'color',
          value: {
            fixedColor: 'red',
            mode: 'fixed',
          },
        }],
      },
    ])
  ,

  // grafonnet ref: https://grafana.github.io/grafonnet/API/dashboard/variable.html
  variables: {
    prometheus:
      var.datasource.new('PROMETHEUS_DS', 'prometheus')
      + var.datasource.generalOptions.showOnDashboard.withValueOnly()
    ,
    hub:
      var.query.new('hub')
      + var.query.withDatasourceFromVariable(self.prometheus)
      + var.query.selectionOptions.withMulti()
      + var.query.selectionOptions.withIncludeAll(value=true, customAllValue='.*')
      + var.query.queryTypes.withLabelValues('namespace', 'kube_service_labels{service="hub"}')
    ,
    hub_name:
      var.query.new('hub_name')
      + var.query.withDatasourceFromVariable(self.prometheus)
      + var.query.selectionOptions.withMulti()
      + var.query.selectionOptions.withIncludeAll(value=true, customAllValue='.*')
      + var.query.queryTypes.withLabelValues('namespace', 'kube_service_labels{service="hub"}')
    ,
    namespace:
      var.query.new('namespace')
      + var.query.withDatasourceFromVariable(self.prometheus)
      + var.query.selectionOptions.withMulti()
      + var.query.selectionOptions.withIncludeAll(value=true, customAllValue='.*')
      + var.query.queryTypes.withLabelValues('namespace', 'kube_pod_labels')
    ,
    user_group:
      var.query.new('user_group')
      + var.query.withDatasourceFromVariable(self.prometheus)
      + var.query.selectionOptions.withMulti()
      + var.query.selectionOptions.withIncludeAll(value=true, customAllValue='.*')
      // If jupyterhub-groups-exporter is configured with `double_count=True` as
      // it is by default, a pseudo group named `multiple` will also be reported
      // by jupyterhub-groups-exporter next to real groups and the `none` group.
      // A user part of multiple real groups, will also be part of the `multiple`
      // pseudo-group. Presenting this groups is assumed to not improve the user
      // experience, so we exclude it.
      + var.query.withRegex('^(?!multiple$).+')
      + var.query.queryTypes.withLabelValues('usergroup', 'jupyterhub_user_group_info')
    ,
    user_name:
      var.query.new('user_name')
      + var.query.withDatasourceFromVariable(self.prometheus)
      + var.query.selectionOptions.withMulti()
      + var.query.selectionOptions.withIncludeAll(value=true, customAllValue='.*')
      + var.query.queryTypes.withLabelValues('annotation_hub_jupyter_org_username', 'kube_pod_annotations{ namespace=~"$hub_name"}')
    ,
    // Queries should use the 'instance' label when querying metrics that
    // come from collectors present on each node - such as node_exporter or
    // container_ metrics, and use the 'node' label when querying metrics
    // that come from collectors that are present once per cluster, like
    // kube_state_metrics.
    instance:
      var.query.new('instance')
      + var.query.withDatasourceFromVariable(self.prometheus)
      + var.query.selectionOptions.withMulti()
      + var.query.selectionOptions.withIncludeAll(value=true, customAllValue='.*')
      + var.query.queryTypes.withLabelValues('node', 'kube_node_info')
    ,
    show_requests:
      var.custom.new('show_requests', [
        { key: 'Show', value: '1' },
        { key: 'Hide', value: '0' },
      ])
      + var.custom.generalOptions.withLabel('CPU/Memory requests')
      + var.custom.generalOptions.withDescription("In panels showing containers' CPU/Memory usage, also show the containers' CPU/Memory requests.")
      + var.custom.generalOptions.withCurrent('Show', '1')
    ,
    show_limits:
      var.custom.new('show_limits', [
        { key: 'Show', value: '1' },
        { key: 'Hide', value: '0' },
      ])
      + var.custom.generalOptions.withLabel('CPU/Memory limits')
      + var.custom.generalOptions.withDescription("In panels showing containers' CPU/Memory usage, also show the containers' CPU/Memory limits.")
      + var.custom.generalOptions.withCurrent('Hide', '0')
    ,
    show_capacity:
      var.custom.new('show_capacity', [
        { key: 'Show', value: '1' },
        { key: 'Hide', value: '0' },
      ])
      + var.custom.generalOptions.withLabel('Storage capacity')
      + var.custom.generalOptions.withDescription("In panels showing storage usage, also show the storage's capacity.")
      + var.custom.generalOptions.withCurrent('Show', '1'),
  },

  _nodePoolLabelKeys: [
    'label_alpha_eksctl_io_nodegroup_name',  // EKS done via eksctl sets this label
    'label_cloud_google_com_gke_nodepool',  // GKE sets this label
    'label_kubernetes_azure_com_agentpool',  // AKS sets this label
  ],

  /**
   * List of labels applied onto nodes describing the nodegroup they belong to.
   * This is different per cloud provider, so we list them all here. Prometheus will just ignore
   * the labels that are not present.
   */
  nodePoolLabels: std.join(', ', self._nodePoolLabelKeys),

  /**
   * Legend used to display name of nodepool a timeseries belongs to, to be used in conjunction with
   * nodePoolLabels. Grafana will ignore all the labels that don't exist, and we will get to see a
   * human readable name of the nodepool in question.
   */
  nodePoolLabelsLegendFormat: '{{' + std.join('}}{{', self._nodePoolLabelKeys) + '}}',

  /**
   * Utility function to adjust a panel's height after a grid of panels has been
   * made.
   */
  adjustGridPanelHeight(grid, panelTitle, newHeight): std.map(
    function(p) (
      if p.title == panelTitle
      then p { gridPos+: { h: newHeight } }
      else p
    ),
    grid
  ),
}
