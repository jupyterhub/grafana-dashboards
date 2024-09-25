local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v10.4.0/main.libsonnet';
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;

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
   * Creates a timeseries panel for a resource for one (or more) JupyterHub component(s).
   * The given metric will be summed across pods for the given component.
   *
   * @name jupyterhub.componentResourcePanel
   *
   * @param title The title of the timeseries panel.
   * @param metric The metric to be observed.
   * @param component The component to be measured (or excluded).
   *     Optional if `multi=true`, in which case it is an exclusion, otherwise required.
   * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
   *     The chart will have a legend table for each component.
   */
  componentResourcePanel(title, metric, component, multi, namespace)::
    ts.new(title)
    // show legend as a table with current, avg, max values
    //legend_hideZero=true,
    // legend_values is required for any of the above to work
    //legend_values=true,
    + ts.options.legend.withDisplayMode('table')
    + ts.options.legend.withCalcs(['min', 'mean', 'max'])
    + ts.queryOptions.withTargets([
      prometheus.new(
        '$PROMETHEUS_DS',
        std.format(
          |||
            sum(
              %s
              %s
            ) by (label_component)
          |||,
          [
            metric,
            self.onComponentLabel(
              component,
              cmp=if multi then '!=' else '=',
              group_left='container, label_component',
              namespace=namespace,
            ),
          ],
        )
      )
      + prometheus.withLegendFormat(if multi then '{{ label_component }}' else title),
    ]),

  /**
   * Creates a memory (working set) timeseries panel for one (or more) JupyterHub component(s).
   *
   * @name jupyterhub.memoryPanel
   *
   * @param name The name of the resource. Used to create the title.
   * @param component The component to be measured (or excluded).
   *     Optional if `multi=true`, in which case it is an exclusion, otherwise required.
   * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
   *     The chart will have a legend table for each component.
   */
  memoryPanel(name, component, multi=false, namespace='$hub')::
    self.componentResourcePanel(
      std.format('%s Memory (Working Set)', [name]),
      component=component,
      multi=multi,
      namespace=namespace,
      metric=|||
        # exclude name="" because the same container can be reported
        # with both no name and `name=k8s_...`,
        # in which case sum() reports double the actual metric
        container_memory_working_set_bytes{name!=""}
      |||,
    )
    + ts.standardOptions.withUnit('bytes')
  ,

  /**
   * Creates a CPU usage timeseries panel for one (or more) JupyterHub component(s).
   *
   * @name jupyterhub.cpuPanel
   *
   * @param name The name of the resource. Used to create the title.
   * @param component The component to be measured (or excluded).
   *     Optional if `multi=true`, in which case it is an exclusion, otherwise required.
   * @param multi (default `false`) If true, do a multi-component chart instead of single-component.
   *     The chart will have a legend table for each component.
   */
  cpuPanel(name, component, multi=false, namespace='$hub')::
    self.componentResourcePanel(
      std.format('%s CPU', [name]),
      component=component,
      multi=multi,
      namespace=namespace,
      metric=|||
        # exclude name="" because the same container can be reported
        # with both no name and `name=k8s_...`,
        # in which case sum() reports double the actual metric
        irate(container_cpu_usage_seconds_total{name!=""}[5m])
      |||,
    )
    + ts.standardOptions.withDecimals(1)
    + ts.standardOptions.withUnit('percentunit'),
}
