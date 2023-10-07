local grafonnet = import "github.com/grafana/grafonnet/gen/grafonnet-v10.0.0/main.libsonnet";
local graphPanel = grafonnet.graphPanel;
local prometheus = grafonnet.prometheus;

{
  /*
   * standard panel dimensions
   */
  standardDims:: { w: 12, h: 8 },

  /*
   * Prometheus query for selecting pods
   *
   * @name jupyterhub.componentLabel
   *
   * @param component The component being selected
   * @param cmp (default `'='`) The comparison to use for the component label, e.g. for exclusions.
   *
   * @return prometheus query string selecting pods for a certain component
   */
  componentLabel(component, cmp='=', namespace='$hub')::
    std.format(
      // group aggregator is used to ensure named pods are unique per namespace
      '\n  group(\n    kube_pod_labels{label_app="jupyterhub", label_component%s"%s"%s}\n  ) by (label_component, pod%s)',
      [
        cmp,
        component,
        if namespace != null then
          ', namespace=~"%s"' % namespace
        else
          '',
        if namespace != null then
          ', namespace'
        else
          '',
      ]
    ),

  /*
   * prometheus query join for filtering a metric to only pods for a given hub component
   *
   * @name jupyterhub.onComponentLabel
   *
   * @param component The component being selected
   * @param cmp (default `'='`) The comparison to use for the component label, e.g. for exclusions.
   * @param group_left (optional) The body to use for a group_left on the join, e.g. `container` for `group_left(container)`
   * @param group_right (optional) The body to use for a group_right on the join, e.g. `container` for `group_right(container)`
   * @param namepsace (default $hub) The namespace to use. If `null`, use all namespaces
   *
   * @return prometheus query string starting with `* on(namespace, pod)` to apply any metric only to pods of a given hub component
   */
  onComponentLabel(component, cmp='=', group_left=false, group_right=false, namespace='$hub')::
    std.format(
      '* on (namespace, pod) %s %s', [
        if group_left != false then
          std.format('group_left(%s)', [group_left])
        else if group_right != false then
          std.format('group_right(%s)', [group_right])
        else
          ''
        ,
        self.componentLabel(component, cmp=cmp, namespace=namespace),
      ]
    )
  ,
  /**
   * Creates a graph panel for a resource for one (or more) JupyterHub component(s).
   * The given metric will be summed across pods for the given component.
   * if `multi` a multi-component chart will be produced, with sums for each component.
   *
   * @name jupyterhub.componentResourcePanel
   *
   * @param title The title of the graph panel.
   * @param metric The metric to be observed.
   * @param component The component to be measured (or excluded). Optional if `multi=true`, in which case it is an exclusion, otherwise required.
   * @param formatY1 (optional) Passthrough `formatY1` to `graphPanel.new`
   * @param decimalsY1 (optional) Passthrough `decimalsY1` to `graphPanel.new`
   * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
   *     The chart will have a legend table for each component.
   */
  componentResourcePanel(title, metric, component='', formatY1=null, decimalsY1=null, multi=false):: graphPanel.new(
    title,
    decimalsY1=decimalsY1,
    formatY1=formatY1,
    // show legend as a table with current, avg, max values
    legend_alignAsTable=true,
    legend_current=true,
    legend_avg=true,
    legend_max=true,
    legend_hideZero=true,
    // legend_values is required for any of the above to work
    legend_values=true,
    min=0,
  ).addTargets([
    prometheus.target(
      std.format(
        |||
          sum(
            %s
            %s
          ) by (label_component)
        |||,
        [
          metric,
          self.onComponentLabel(component, cmp=if multi then '!=' else '=', group_left='container, label_component'),
        ],
      ),
      legendFormat=if multi then '{{ label_component }}' else title,
    ),
  ],),

  /**
   * Creates a memory (working set) graph panel for one (or more) JupyterHub component(s).
   *
   * @name jupyterhub.memoryPanel
   *
   * @param name The name of the resource. Used to create the title.
   * @param component The component to be measured (or excluded). Optional if `multi=true`, in which case it is an exclusion, otherwise required.
   * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
   *     The chart will have a legend table for each component.
   */
  memoryPanel(name, component, multi=false):: self.componentResourcePanel(
    std.format('%s Memory (Working Set)', [name]),
    component=component,
    metric=|||
      # exclude name="" because the same container can be reported
      # with both no name and `name=k8s_...`,
      # in which case sum() reports double the actual metric
      container_memory_working_set_bytes{name!=""}
    |||,
    formatY1='bytes',
    multi=multi,
  ),

  /**
   * Creates a CPU usage graph panel for one (or more) JupyterHub component(s).
   *
   * @name jupyterhub.cpuPanel
   *
   * @param name The name of the resource. Used to create the title.
   * @param component The component to be measured (or excluded). Optional if `multi=true`, in which case it is an exclusion, otherwise required.
   * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
   *     The chart will have a legend table for each component.
   */
  cpuPanel(name, component, multi=false):: self.componentResourcePanel(
    std.format('%s CPU', [name]),
    component=component,
    metric=|||
      # exclude name="" because the same container can be reported
      # with both no name and `name=k8s_...`,
      # in which case sum() reports double the actual metric
      irate(container_cpu_usage_seconds_total{name!=""}[5m])
    |||,
    // decimals=1 with percentunit means round to nearest 10%
    decimalsY1=1,
    formatY1='percentunit',
    multi=multi,
  ),
}
