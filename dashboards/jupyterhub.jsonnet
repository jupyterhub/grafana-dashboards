#!/usr/bin/env -S jsonnet -J ../vendor
// Deploys one dashboard - "JupyterHub dashboard",
// with useful stats about usage & diagnostics.
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v11.1.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local ts = grafonnet.panel.timeSeries;
local prometheus = grafonnet.query.prometheus;
local table = grafonnet.panel.table;
local heatmap = grafonnet.panel.heatmap;
local row = grafonnet.panel.row;

local common = import './common.libsonnet';
local jupyterhub = import 'jupyterhub.libsonnet';

local userMemoryDistribution =
  common.heatmapOptions
  + heatmap.new('User memory usage distribution')
  + heatmap.options.yAxis.withUnit('bytes')
  + heatmap.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          # exclude name="" because the same container can be reported
          # with both no name and `name=k8s_...`,
          # in which case sum() by (pod) reports double the actual metric
          container_memory_working_set_bytes{name!=""}
          %s
        ) by (pod)
      |||
      % jupyterhub.onComponentLabel('singleuser-server', group_left='container'),
    )
    + prometheus.withIntervalFactor(1),
  ]);

local userCPUDistribution =
  common.heatmapOptions
  + heatmap.new('User CPU usage distribution')
  + heatmap.options.yAxis.withUnit('sishort')
  + heatmap.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          # exclude name="" because the same container can be reported
          # with both no name and `name=k8s_...`,
          # in which case sum() by (pod) reports double the actual metric
          irate(container_cpu_usage_seconds_total{name!=""}[5m])
          %s
        ) by (pod)
      |||
      % jupyterhub.onComponentLabel('singleuser-server', group_left='container'),
    )
    + prometheus.withIntervalFactor(1),
  ]);

local userAgeDistribution =
  common.heatmapOptions
  + heatmap.new('User active age distribution')
  + heatmap.options.yAxis.withUnit('s')
  + heatmap.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        (
          time()
          - (
            kube_pod_created
            %s
          )
        )
      |||
      % jupyterhub.onComponentLabel('singleuser-server'),
    )
    + prometheus.withIntervalFactor(1),
  ]);

// Hub diagnostics
local hubResponseLatency =
  common.heatmapOptions
  + heatmap.new('Hub response latency')
  + heatmap.options.yAxis.withUnit('s')
  + heatmap.options.withCalculate(false)
  + heatmap.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        # Ignore SpawnProgressAPIHandler, as it is a EventSource stream
        # and keeps long lived connections open
        sum by (le) (
          jupyterhub_request_duration_seconds_bucket{
            app="jupyterhub",
            namespace=~"$hub",
            handler!="jupyterhub.apihandlers.users.SpawnProgressAPIHandler"
          }
          -
          jupyterhub_request_duration_seconds_bucket{
            app="jupyterhub",
            namespace=~"$hub",
            handler!="jupyterhub.apihandlers.users.SpawnProgressAPIHandler"
          }
          offset $__rate_interval
        )
      |||,
    )
    + prometheus.withFormat('heatmap'),
  ]);

local hubResponseCodes =
  common.tsOptions
  + ts.new('Hub response status codes')
  + ts.standardOptions.withUnit('short')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          increase(
            jupyterhub_request_duration_seconds_count{
              app="jupyterhub",
              namespace=~"$hub",
            }[2m]
          )
        ) by (code)
      |||
    )
    + prometheus.withLegendFormat('{{ code }}'),
  ]);


// with multi=true, component='singleuser-server' means all components *except* singleuser-server
local allComponentsMemory = jupyterhub.memoryPanel(
  'All JupyterHub Components',
  component='singleuser-server',
  multi=true,
);
local allComponentsCPU = jupyterhub.cpuPanel(
  'All JupyterHub Components',
  component='singleuser-server',
  multi=true,
);

local hubDBUsage =
  common.tsOptions
  + ts.new('Hub DB Disk Space Availability %')
  + ts.panelOptions.withDescription(
    |||
      % of disk space left in the disk storing the JupyterHub sqlite database. If goes to 0, the hub will fail.
    |||
  )
  + ts.standardOptions.withDecimals(0)
  + ts.standardOptions.withMax(1)
  + ts.standardOptions.withUnit('percentunit')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        # Free bytes available on the hub db PVC
        sum(kubelet_volume_stats_available_bytes{persistentvolumeclaim="hub-db-dir", namespace=~"$hub"}) by (namespace) /
        # Total number of bytes available on the hub db PVC
        sum(kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="hub-db-dir", namespace=~"$hub"}) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ $hub }}'),
  ]);


local serverStartTimes =
  common.heatmapOptions
  + heatmap.new('Server Start Times')
  + heatmap.options.yAxis.withUnit('s')
  + heatmap.options.withCalculate(false)
  + heatmap.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum by (le) (
          jupyterhub_server_spawn_duration_seconds_bucket
          -
          jupyterhub_server_spawn_duration_seconds_bucket
          offset $__rate_interval
        )
      |||
    )
    + prometheus.withFormat('heatmap'),
  ]);


local serverSpawnFailures =
  common.tsOptions
  + ts.new('Server Start Failures')
  + ts.panelOptions.withDescription(
    |||
      Attempts by users to start servers that failed.
    |||
  )
  + ts.fieldConfig.defaults.custom.withDrawStyle('points')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withInterval('2m')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(increase(jupyterhub_server_spawn_duration_seconds_count{status!="success"}[2m])) by (status)
      |||
    )
    + prometheus.withLegendFormat('{{status}}'),
  ]);

local usersPerNode =
  common.tsOptions
  + ts.new('Users per node')
  + ts.standardOptions.withDecimals(0)
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
            # kube_pod_info.node identifies the pod node,
            # while kube_pod_labels.node is the metrics exporter's node
            kube_pod_info{node!=""}
            %s
        ) by (node)
      |||
      % jupyterhub.onComponentLabel('singleuser-server', group_left='')
    )
    + prometheus.withLegendFormat('{{ node }}'),
  ]);


local nonRunningPods =
  common.tsOptions
  + common.tsPodStateStylingOverrides
  + ts.new('Non Running Pods')
  + ts.panelOptions.withDescription(
    |||
      Pods in a non-running state in the hub's namespace.

      Pods stuck in non-running states often indicate an error condition
    |||
  )
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_status_phase{phase!="Running", namespace=~"$hub"}
        ) by (phase)
      |||
    )
    + prometheus.withLegendFormat('{{phase}}'),
  ]);

local sharedVolumeFreeSpace =
  common.tsOptions
  + ts.new('Free space (%) in shared volume (Home directories, etc.)')
  + ts.panelOptions.withDescription(
    |||
      % of disk space left in a shared storage volume, typically used for users'
      home directories.

      Requires an additional node_exporter deployment to work. If this graph
      is empty, look at the README for jupyterhub/grafana-dashboards to see
      what extra deployment is needed.
    |||
  )
  + ts.standardOptions.withMax(1)
  + ts.standardOptions.withUnit('percentunit')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        min(
          node_filesystem_avail_bytes{mountpoint="/shared-volume", component="shared-volume-metrics", namespace=~"$hub"}
          /
          node_filesystem_size_bytes{mountpoint="/shared-volume", component="shared-volume-metrics", namespace=~"$hub"}
        ) by (namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ namespace }}'),
  ]);

// Anomalous tables
local oldUserpods =
  common.tableOptions
  + table.new('Very old user pods')
  + table.panelOptions.withDescription(
    |||
      User pods that have been running for a long time (>8h).

      This often indicates problems with the idle culler
    |||
  )
  + table.standardOptions.withUnit('s')
  + table.options.withSortBy({ displayName: 'Age', desc: true })
  + table.queryOptions.withTransformations([
    {
      id: 'reduce',
      options: {
        reducers: ['last'],
      },
    },
    {
      id: 'organize',
      options: {
        renameByName: {
          Field: 'User pod',
          Last: 'Age',
        },
      },
    },
  ])
  + table.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        (
          time() - (kube_pod_created %s)
        )  > (8 * 60 * 60) # 8 hours is our threshold
      |||
      % jupyterhub.onComponentLabel('singleuser-server')
    )
    + prometheus.withInstant(true)
    + prometheus.withLegendFormat('{{ namespace }}/{{ pod }}'),
  ]);

local highCPUUserPods =
  common.tableOptions
  + table.new('User Pods with high CPU usage (>0.5)')
  + table.panelOptions.withDescription(
    |||
      User pods using a lot of CPU

      This could indicate a runaway process consuming resources
      unnecessarily.
    |||
  )
  + table.options.withSortBy({ displayName: 'CPU used', desc: true })
  + table.queryOptions.withTransformations([
    {
      id: 'reduce',
      options: {
        reducers: ['last'],
      },
    },
    {
      id: 'organize',
      options: {
        renameByName: {
          Field: 'User pod',
          Last: 'CPU used',
        },
      },
    },
  ])
  + table.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max( # Ideally we just want 'current' value, so max will do
          irate(container_cpu_usage_seconds_total[5m])
          %s
        ) by (namespace, pod) > 0.5
      |||
      % jupyterhub.onComponentLabel('singleuser-server', group_left='')
    )
    + prometheus.withInstant(true)
    + prometheus.withLegendFormat('{{ namespace }}/{{ pod }}'),
  ]);

local highMemoryUsagePods =
  common.tableOptions
  + table.new('User pods with high memory usage (>80% of limit)')
  + table.panelOptions.withDescription(
    |||
      User pods getting close to their memory limit

      Once they hit their memory limit, user kernels will start dying.
    |||
  )
  + table.standardOptions.withUnit('percentunit')
  + table.options.withSortBy({ displayName: '% of mem limit consumed', desc: true })
  + table.queryOptions.withTransformations([
    {
      id: 'reduce',
      options: {
        reducers: ['last'],
      },
    },
    {
      id: 'organize',
      options: {
        renameByName: {
          Field: 'User pod',
          Last: '% of mem limit consumed',
        },
      },
    },
  ])
  + table.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        max( # Ideally we just want 'current', but max will do. This metric is a gauge, so sum is inappropriate
          container_memory_working_set_bytes
          %(selector)s
        ) by (namespace, pod)
        /
        sum(
          kube_pod_container_resource_limits_memory_bytes
          %(selector)s
        ) by (namespace, pod)
        > 0.8
      |||
      % {
        selector: jupyterhub.onComponentLabel('singleuser-server', group_left=''),
      }
    )
    + prometheus.withInstant(true)
    + prometheus.withLegendFormat('{{ namespace }}/{{ pod }}'),
  ]);

// Show images used by different users on the hub
local notebookImagesUsed =
  common.tsOptions
  + ts.new('Images used by user pods')
  + ts.panelOptions.withDescription(
    |||
      Number of user servers using a container image.
    |||
  )
  + ts.standardOptions.withDecimals(0)
  + ts.fieldConfig.defaults.custom.stacking.withMode('normal')
  + ts.queryOptions.withTargets([
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum (
          # User pods are named "notebook" by kubespawner
          kube_pod_container_info{container="notebook", namespace=~"$hub"}
        ) by(image_spec, namespace)
      |||
    )
    + prometheus.withLegendFormat('{{ namespace }}: {{ image_spec }}'),
  ]);

dashboard.new('JupyterHub Dashboard')
+ dashboard.withTags(['jupyterhub'])
+ dashboard.withUid('hub-dashboard')
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.hub,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      row.new('Container Images')
      + row.withPanels([
        notebookImagesUsed,
      ]),
      row.new('User Resource Utilization stats')
      + row.withPanels([
        userAgeDistribution,
        userCPUDistribution,
        userMemoryDistribution,
      ]),
      row.new('Hub Diagnostics')
      + row.withPanels([
        serverStartTimes,
        serverSpawnFailures,
        hubResponseLatency,
        hubResponseCodes,
        allComponentsCPU,
        allComponentsMemory,
        usersPerNode,
        nonRunningPods,
        hubDBUsage,
        sharedVolumeFreeSpace,
      ]),
      row.new('Anomalous user pods')
      + row.withPanels([
        oldUserpods,
        highCPUUserPods,
        highMemoryUsagePods,
      ]),
    ],
    panelWidth=12,
    panelHeight=10,
  )
)
