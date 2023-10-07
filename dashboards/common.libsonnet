local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v10.0.0/main.libsonnet';
local ts = grafonnet.panel.timeSeries;
local barChart = grafonnet.panel.barChart;

{
  tsOptions: ts.standardOptions.withMin(
    // Y axes should *always* start from 0
    0
  ) + ts.options.withTooltip({
    // Show all values in the legend tooltip
    mode: 'multi',
  }),

  barChartOptions: barChart.standardOptions.withMin(
    // Y axes should *always* start from 0
    0
  ) + barChart.options.withTooltip({
    // Show all values in the legend tooltip
    mode: 'multi',
  }),

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
}
