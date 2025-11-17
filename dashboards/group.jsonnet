#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;

local common = import './common.libsonnet';

local memoryUsage =
  common.tsOptions
  + ts.new('Memory Usage')
  + ts.panelOptions.withDescription(
    |||
      Per group memory usage.

      User groups are derived from authenticator managed groups where available, e.g. GitHub teams. If a user is a member of multiple groups, then they will be assigned to the group 'other' by default. 

      Requires https://github.com/2i2c-org/jupyterhub-groups-exporter to
      be set up. If the panels show no data, then please try selecting another time range where usage was active.
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(

          # sum pod containers' Memory usage, for each namespace and user combination
          sum(
            container_memory_working_set_bytes{namespace=~"$hub_name", pod=~"jupyter-.*", name!=""}

            # add an annotation_hub_jupyter_org_username label
            * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
            group(
                kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~".*"}
            ) by (namespace, pod, annotation_hub_jupyter_org_username)
          ) by (namespace, annotation_hub_jupyter_org_username)

          # make namespace/user combinations become more namespace/user/usergroup combinations
          * on (namespace, annotation_hub_jupyter_org_username) group_right()
          group(
            # duplicate jupyterhub_user_group_info's username label as annotation_hub_jupyter_org_username
            label_replace(
              jupyterhub_user_group_info{namespace=~"$hub_name", username=~".*", usergroup=~"$user_group"},
              "annotation_hub_jupyter_org_username", "$1", "username", "(.+)"
            )
          ) by (namespace, annotation_hub_jupyter_org_username, usergroup)

        ) by (namespace, usergroup)
      |||
    )
    + prometheus.withLegendFormat('{{ usergroup }} - ({{ namespace }})'),
  ]);


local cpuUsage =
  common.tsOptions
  + ts.new('CPU Usage')
  + ts.panelOptions.withDescription(
    |||
      Per group CPU usage

      The measured unit are CPU cores, and they are written out with SI prefixes, so 100m means 0.1 CPU cores.

      User groups are derived from authenticator managed groups where available, e.g. GitHub teams. If a user is a member of multiple groups, then they will be assigned to the group 'other' by default. 

      Requires https://github.com/2i2c-org/jupyterhub-groups-exporter to
      be set up. If the panels show no data, then please try selecting another time range where usage was active.
    |||
  )
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(

          # sum pod containers' CPU usage, for each namespace and user combination
          sum(
            irate(container_cpu_usage_seconds_total{pod=~"jupyter-.*", name!=""}[5m])

            # add an annotation_hub_jupyter_org_username label
            * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
            group(
                kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~".*"}
            ) by (namespace, pod, annotation_hub_jupyter_org_username)
          ) by (namespace, annotation_hub_jupyter_org_username)

          # make namespace/user combinations become more namespace/user/usergroup combinations
          * on (namespace, annotation_hub_jupyter_org_username) group_right()
          group(
            # duplicate jupyterhub_user_group_info's username label as annotation_hub_jupyter_org_username
            label_replace(
              jupyterhub_user_group_info{namespace=~"$hub_name", username=~".*", usergroup=~"$user_group"},
              "annotation_hub_jupyter_org_username", "$1", "username", "(.+)"
            )
          ) by (namespace, annotation_hub_jupyter_org_username, usergroup)

        ) by (namespace, usergroup)
      |||
    )
    + prometheus.withLegendFormat('{{ usergroup }} - ({{ namespace }})'),
  ]);

local homedirSharedUsage =
  common.tsOptions
  + ts.new('Home Directory Usage (on shared home directories)')
  + ts.panelOptions.withDescription(
    |||
      Per group home directory size, when using a shared home directory.

      User groups are derived from authenticator managed groups where available, e.g. GitHub teams. If a user is a member of multiple groups, then they will be assigned to the group 'other' by default. 

      Requires https://github.com/yuvipanda/prometheus-dirsize-exporter and https://github.com/2i2c-org/jupyterhub-groups-exporter to
      be set up.
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

          # make namespace/directory combinations become more namespace/directory/usergroup combinations
          * on (namespace, directory) group_right()
          group(
            # match using username_safe (kubespawner's modern "safe" scheme)
            (
              # duplicate jupyterhub_user_group_info's username_safe label as directory
              label_replace(
                jupyterhub_user_group_info{namespace=~"$hub_name", username_safe=~".*", usergroup=~"$user_group"},
                "directory", "$1", "username_safe", "(.+)"
              )
            )
            or
            # match using username_escaped (kubespawner's legacy "escape" scheme)
            (
              # duplicate jupyterhub_user_group_info's username_escaped label as directory
              label_replace(
                jupyterhub_user_group_info{namespace=~"$hub_name", username_escaped=~".*", usergroup=~"$user_group"},
                "directory", "$1", "username_escaped", "(.+)"
              )
            )
          ) by (namespace, directory, usergroup)

        ) by (namespace, usergroup)
      |||
    )
    + prometheus.withLegendFormat('{{ usergroup }} - ({{ namespace }})'),
  ]);

local memoryRequests =
  common.tsOptions
  + ts.new('Memory Requests')
  + ts.panelOptions.withDescription(
    |||
      Per group memory requests

      User groups are derived from authenticator managed groups where available, e.g. GitHub teams. If a user is a member of multiple groups, then they will be assigned to the group 'other' by default. 

      Requires https://github.com/2i2c-org/jupyterhub-groups-exporter to
      be set up. If the panels show no data, then please try selecting another time range where usage was active.
    |||
  )
  + ts.standardOptions.withUnit('bytes')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(

          # sum pod containers' Memory requests, for each namespace and user combination
          sum(
            kube_pod_container_resource_requests{resource="memory", namespace=~"$hub_name", pod=~"jupyter-.*"}

            # add an annotation_hub_jupyter_org_username label
            * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
            group(
                kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~".*"}
            ) by (namespace, pod, annotation_hub_jupyter_org_username)
          ) by (namespace, annotation_hub_jupyter_org_username)

          # make namespace/user combinations become more namespace/user/usergroup combinations
          * on (namespace, annotation_hub_jupyter_org_username) group_right()
          group(
            # duplicate jupyterhub_user_group_info's username label as annotation_hub_jupyter_org_username
            label_replace(
              jupyterhub_user_group_info{namespace=~"$hub_name", username=~".*", usergroup=~"$user_group"},
              "annotation_hub_jupyter_org_username", "$1", "username", "(.+)"
            )
          ) by (namespace, annotation_hub_jupyter_org_username, usergroup)

        ) by (namespace, usergroup)
      |||
    )
    + prometheus.withLegendFormat('{{ usergroup }} - ({{ namespace }})'),
  ]);

local cpuRequests =
  common.tsOptions
  + ts.new('CPU Requests')
  + ts.panelOptions.withDescription(
    |||
      Per group CPU requests

      The measured unit are CPU cores, and they are written out with SI prefixes, so 100m means 0.1 CPU cores.

      User groups are derived from authenticator managed groups where available, e.g. GitHub teams. If a user is a member of multiple groups, then they will be assigned to the group 'other' by default. 

      Requires https://github.com/2i2c-org/jupyterhub-groups-exporter to
      be set up. If the panels show no data, then please try selecting another time range where usage was active.
    |||
  )
  + ts.standardOptions.withUnit('sishort')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(

          # sum pod containers' CPU requests, for each namespace and user combination
          sum(
            kube_pod_container_resource_requests{resource="cpu", namespace=~"$hub_name", pod=~"jupyter-.*"}

            # add an annotation_hub_jupyter_org_username label
            * on (namespace, pod) group_left(annotation_hub_jupyter_org_username)
            group(
                kube_pod_annotations{namespace=~"$hub_name", annotation_hub_jupyter_org_username=~".*"}
            ) by (namespace, pod, annotation_hub_jupyter_org_username)
          ) by (namespace, annotation_hub_jupyter_org_username)

          # make namespace/user combinations become more namespace/user/usergroup combinations
          * on (namespace, annotation_hub_jupyter_org_username) group_right()
          group(
            # duplicate jupyterhub_user_group_info's username label as annotation_hub_jupyter_org_username
            label_replace(
              jupyterhub_user_group_info{namespace=~"$hub_name", username=~".*", usergroup=~"$user_group"},
              "annotation_hub_jupyter_org_username", "$1", "username", "(.+)"
            )
          ) by (namespace, annotation_hub_jupyter_org_username, usergroup)

        ) by (namespace, usergroup)
      |||
    )
    + prometheus.withLegendFormat('{{ usergroup }} - ({{ namespace }})'),
  ]);

dashboard.new('User Group Diagnostics Dashboard')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withUid('group-diagnostics-dashboard')
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.hub_name,
  common.variables.user_group,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      memoryUsage,
      cpuUsage,
      homedirSharedUsage,
      memoryRequests,
      cpuRequests,
    ],
    panelWidth=24,
    panelHeight=12,
  )
)
