#!/usr/bin/env -S jsonnet -J ../vendor
local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-v10.4.0/main.libsonnet';
local dashboard = grafonnet.dashboard;
local barGauge = grafonnet.panel.barGauge;
local prometheus = grafonnet.query.prometheus;

local common = import './common.libsonnet';

local memoryUsageUserPods =
  common.barGaugeOptions
  + barGauge.new('User pod memory usage')
  + barGauge.standardOptions.withUnit('bytes')
  + barGauge.standardOptions.color.withMode('fixed')
  + barGauge.standardOptions.color.withFixedColor('green')
  + barGauge.queryOptions.withTargets([
    // Computes sum of pod memory requests, grouped by username, for notebook pods
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        kube_pod_labels{
          label_app="jupyterhub",
          label_component="singleuser-server",
          namespace=~"$hub"
        }
        * on (namespace, pod) group_left()
        sum(
          container_memory_working_set_bytes{
            namespace=~"$hub",
            container="notebook",
            hub_jupyter_org_node_purpose="user",
            name!="",
          }
        ) by (namespace, pod)
      |||,
    )
    + prometheus.withLegendFormat('{{label_hub_jupyter_org_username}} ({{namespace}})'),
  ]);

// Dask-gateway related dashboard
local memoryUsageDaskWorkerPods =
  common.barGaugeOptions
  + barGauge.new('Dask-gateway worker pod memory usage')
  + barGauge.standardOptions.withUnit('bytes')
  + barGauge.standardOptions.color.withMode('fixed')
  + barGauge.standardOptions.color.withFixedColor('green')
  + barGauge.queryOptions.withTargets([
    // Computes sum of pod memory requests, grouped by username, and dask-gateway cluster
    // for dask-gateway worker pods
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_labels{
            namespace=~"$hub",
            label_app_kubernetes_io_component="dask-worker",
          }
          * on (namespace, pod) group_left()
          sum(
            container_memory_working_set_bytes{
              namespace=~"$hub",
              container="dask-worker",
              k8s_dask_org_node_purpose="worker",
              name!="",
            }
          ) by (namespace, pod)
        ) by (label_hub_jupyter_org_username, label_gateway_dask_org_cluster)
      |||,
    )
    + prometheus.withLegendFormat('{{label_hub_jupyter_org_username}}-{{label_gateway_dask_org_cluster}}'),
  ]);


// dask-scheduler
local memoryUsageDaskSchedulerPods =
  common.barGaugeOptions
  + barGauge.new('Dask-gateway scheduler pod memory usage')
  + barGauge.standardOptions.withUnit('bytes')
  + barGauge.standardOptions.color.withMode('fixed')
  + barGauge.standardOptions.color.withFixedColor('green')
  + barGauge.queryOptions.withTargets([
    // Computes sum of pod memory requests, grouped by username, and dask-gateway cluster
    // for dask-gateway scheduler pods
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        sum(
          kube_pod_labels{
            namespace=~"$hub",
            label_app_kubernetes_io_component="dask-scheduler",
          }
          * on (namespace, pod) group_left()
          sum(
            container_memory_working_set_bytes{
              namespace=~"$hub",
              container="dask-scheduler",
              k8s_dask_org_node_purpose="scheduler",
              name!="",
            }
          ) by (namespace, pod)
        ) by (label_hub_jupyter_org_username, label_gateway_dask_org_cluster)
      |||,
    )
    + prometheus.withLegendFormat('{{label_hub_jupyter_org_username}}-{{label_gateway_dask_org_cluster}}'),
  ]);


// GPU memory usage dashboard
local memoryUsageGPUPods =
  common.barGaugeOptions
  + barGauge.new('GPU pod memory usage')
  + barGauge.standardOptions.withUnit('bytes')
  + barGauge.standardOptions.color.withMode('fixed')
  + barGauge.standardOptions.color.withFixedColor('green')
  + barGauge.queryOptions.withTargets([
    // Computes sum of pod memory requests, grouped by username for notebook gpu pods
    prometheus.new(
      '$PROMETHEUS_DS',
      |||
        kube_pod_labels{
          label_app="jupyterhub",
          label_component="singleuser-server",
          namespace=~"$hub"
        }
        * on (namespace, pod) group_left()
        sum(
          container_memory_working_set_bytes{
            namespace=~"$hub",
            container="notebook",
            hub_jupyter_org_node_purpose="user",
            cloud_google_com_gke_nodepool="nb-gpu-k80",
            cloud_google_com_gke_accelerator="nvidia-tesla-k80",
            name!="",
          }
        ) by (namespace, pod)
      |||,
    )
    + prometheus.withLegendFormat('{{label_hub_jupyter_org_username}}-{{label_gateway_dask_org_cluster}}'),
  ]);


dashboard.new('Usage Report')
+ dashboard.withTags(['jupyterhub', 'dask'])
+ dashboard.withEditable(true)
+ dashboard.withVariables([
  common.variables.prometheus,
  common.variables.hub,
])
+ dashboard.withPanels(
  grafonnet.util.grid.makeGrid(
    [
      memoryUsageUserPods,
      memoryUsageDaskWorkerPods,
      memoryUsageDaskSchedulerPods,
      memoryUsageGPUPods,
    ],
    panelWidth=24,
    panelHeight=10,
  )
)
