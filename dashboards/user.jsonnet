#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local stateTimeline = grafonnet.panel.stateTimeline;
local prometheus = grafonnet.query.prometheus;

local common = import './common.libsonnet';

local memoryUsage =
  common.tsOptions
  + ts.new('Memory Usage')
  + ts.panelOptions.withDescription(
    |||
      Per user memory usage
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          container_memory_working_set_bytes{name!="", pod=~"jupyter-.*", namespace=~"$hub_name"}
            * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
            group(
                kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~"(?i).*$user_name.*", pod=~"jupyter-.*"}
            ) by (pod, namespace, annotation_hub_jupyter_org_username)
        ) by (annotation_hub_jupyter_org_username, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ annotation_hub_jupyter_org_username }} - ({{ namespace }})'),
  ]);


local cpuUsage =
  common.tsOptions
  + ts.new('CPU Usage')
  + ts.panelOptions.withDescription(
    |||
      Per user CPU usage

      The measured unit are CPU cores, and they are written out with SI prefixes, so 100m means 0.1 CPU cores.
    |||
  )
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          # exclude name="" because the same container can be reported
          # with both no name and `name=k8s_...`,
          # in which case sum() by (pod) reports double the actual metric
          irate(container_cpu_usage_seconds_total{name!="", pod=~"jupyter-.*"}[5m])
          * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
          group(
              kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~"(?i).*$user_name.*"}
          ) by (pod, namespace, annotation_hub_jupyter_org_username)
        ) by (annotation_hub_jupyter_org_username, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ annotation_hub_jupyter_org_username }} - ({{ namespace }})'),
  ]);

local homedirSharedUsage =
  common.tsOptions
  + ts.new('Home Directory Usage (on shared home directories)')
  + ts.panelOptions.withDescription(
    |||
      Per user home directory size, when using a shared home directory.

      Requires https://github.com/yuvipanda/prometheus-dirsize-exporter to
      be set up.

      Similar to server pod names, user names will be *encoded* here
      using the escapism python library (https://github.com/minrk/escapism).
      You can unencode them with the following python snippet:

      from escapism import unescape
      unescape('<escaped-username>', '-')
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(

          # max is used to de-duplicate data from multiple sources
          max(
            dirsize_total_size_bytes{namespace=~"$hub_name"}
          ) by (namespace, directory)

          # make namespace/directory combinations become more namespace/directory/username combinations
          * on (namespace, directory) group_right()
          group(
            # match using username_safe (kubespawner's modern "safe" scheme)
            # duplicate jupyterhub_user_group_info's username_safe label as directory
            label_replace(
              jupyterhub_user_group_info{namespace=~"$hub_name", username_safe=~".*"},
              "directory", "$1", "username_safe", "(.+)"
            )
            or
            # match using username_escaped (kubespawner's legacy "escape" scheme)
            # duplicate jupyterhub_user_group_info's username_escaped label as directory
            label_replace(
              jupyterhub_user_group_info{namespace=~"$hub_name", username_escaped=~".*"},
              "directory", "$1", "username_escaped", "(.+)"
            )
          ) by (namespace, directory, username)

        ) by (namespace, username)
      |||
    )
    + prometheus.withLegendFormat('{{ username }} - ({{ namespace }})'),
  ]);

local memoryRequests =
  common.tsOptions
  + ts.new('Memory Requests')
  + ts.panelOptions.withDescription(
    |||
      Per-user memory requests
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_container_resource_requests{resource="memory", namespace=~"$hub_name", pod=~"jupyter-.*"}  * on (namespace, pod)
          group_left(annotation_hub_jupyter_org_username) group(
            kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~"(?i).*$user_name.*"}
            ) by (pod, namespace, annotation_hub_jupyter_org_username)
        ) by (annotation_hub_jupyter_org_username, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ annotation_hub_jupyter_org_username }} - ({{ namespace }})'),
  ]);

local cpuRequests =
  common.tsOptions
  + ts.new('CPU Requests')
  + ts.panelOptions.withDescription(
    |||
      Per user CPU requests

      The measured unit are CPU cores, and they are written out with SI prefixes, so 100m means 0.1 CPU cores.
    |||
  )
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_container_resource_requests{resource="cpu", namespace=~"$hub_name", pod=~"jupyter-.*"} * on (namespace, pod)
          group_left(annotation_hub_jupyter_org_username) group(
            kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~"(?i).*$user_name.*"}
            ) by (pod, namespace, annotation_hub_jupyter_org_username)
        ) by (annotation_hub_jupyter_org_username, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ annotation_hub_jupyter_org_username }} - ({{ namespace }})'),
  ]);

local userSessions =
  stateTimeline.new('User Sessions')
  + stateTimeline.panelOptions.withDescription(
    |||
      When each user's notebook server was running, over the selected time range.

      Each row is a user; a colored segment marks the periods their singleuser
      server pod was in the `Running` phase. The width of a segment is how long
      that server ran, and its position shows when it started and stopped.

      This is based on `kube_pod_status_phase{phase="Running"}` for `jupyter-*`
      pods, joined to the hub username annotation, so it reflects servers that
      were actually running (consistent with the CPU/Memory panels) rather than
      pods that merely still exist in a completed state.
    |||
  )
  + stateTimeline.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      // Keep the compact Y-axis label that fits the fixed axis width while
      // retaining annotation_hub_jupyter_org_username in the series labels for
      // the full username in hover details. Names longer than 15 characters
      // show their first 8 and last 6 characters separated by a Unicode
      // ellipsis (for example, "john.doe…le.com").
      |||
        label_replace(
          label_replace(
            max by (annotation_hub_jupyter_org_username, namespace) (
              (kube_pod_status_phase{namespace=~"$hub_name", phase="Running", pod=~"jupyter-.*"} == 1)
              * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
              group(
                kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~"(?i).*$user_name.*", pod=~"jupyter-.*"}
              ) by (namespace, pod, annotation_hub_jupyter_org_username)
            ),
            "user_disp", "$1…$2", "annotation_hub_jupyter_org_username", "(.{8}).*(.{6})"
          ),
          "user_disp", "$1", "annotation_hub_jupyter_org_username", "(^.{0,15})$"
        )
      |||
    )
    + prometheus.withLegendFormat('{{ user_disp }}'),
  ])
  + stateTimeline.options.withMergeValues(true)
  + stateTimeline.options.withShowValue('never')
  + stateTimeline.options.withAlignValue('left')
  + stateTimeline.options.withRowHeight(0.9)
  + stateTimeline.options.tooltip.withMode('single')
  + stateTimeline.standardOptions.withDecimals(0)
  + stateTimeline.fieldConfig.defaults.custom.withFillOpacity(100)
  + stateTimeline.fieldConfig.defaults.custom.withLineWidth(0)
  + {
    fieldConfig+: {
      defaults+: {
        // one distinct color per user row
        color: { mode: 'palette-classic-by-name' },
      },
    },
    options+: {
      // the y-axis already labels each row with the user
      legend: { showLegend: false },
    },
  };

// A fixed Y-axis width applied to every panel so their plot areas start at the
// same horizontal offset and the time (x) axes line up across panels. The
// "User Sessions" panel has a text (username) y-axis while the resource panels
// have numeric axes of a different width, so without this they do not align.
local axisWidth = 140;
local withFixedAxisWidth(panel) = panel {
  fieldConfig+: { defaults+: { custom+: { axisWidth: axisWidth } } },
};

dashboard.new('User Diagnostics Dashboard')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withUid('user-diagnostics-dashboard')
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.hub_name,
  common.variables.user_name,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    std.map(withFixedAxisWidth, [
      userSessions,
      memoryUsage,
      cpuUsage,
      homedirSharedUsage,
      memoryRequests,
      cpuRequests,
    ]),
    panelWidth=24,
    panelHeight=12,
  )
)
