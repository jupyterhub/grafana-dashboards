local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local prometheus = grafana.prometheus;
local template = grafana.template;
local barGaugePanel = grafana.barGaugePanel;

local templates = [
  template.datasource(
    name='PROMETHEUS_DS',
    query='prometheus',
    current={},
    hide='label',
  ),
  template.new(
    'hub',
    datasource='$PROMETHEUS_DS',
    query='label_values(kube_service_labels{service="hub"}, namespace)',
    // Allow viewing dashboard for multiple combined hubs
    includeAll=true,
    multi=false
  ),
];

local memoryUsageUserPods = barGaugePanel.new(
  'User pod memory usage',
  datasource='$PROMETHEUS_DS',
  unit='bytes',
  thresholds=[
    {
      value: 0,
      color: 'green',
    },
    {
      value: 600,
      color: 'yellow',
    },
  ]
).addTargets([
  // Computes sum of pod memory requests, grouped by username, for notebook pods
  prometheus.target(
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
    legendFormat='{{label_hub_jupyter_org_username}} ({{namespace}})',
  ),
]);

# Dask-related
# dask-worker
local memoryUsageDaskWorkerPods = barGaugePanel.new(
  'Dask-gateway worker pod memory usage',
  datasource='$PROMETHEUS_DS',
  unit='bytes',
  thresholds=[
    {
      value: 0,
      color: 'green',
    },
    {
      value: 600,
      color: 'yellow',
    },
  ]
).addTargets([
  // Computes sum of pod memory requests, grouped by username, and dask-gateway cluster
  // for dask-gateway worker pods
  prometheus.target(
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
    legendFormat='{{label_hub_jupyter_org_username}}-{{label_gateway_dask_org_cluster}}',
  ),
]);

# dask-scheduler
local memoryUsageDaskSchedulerPods = barGaugePanel.new(
  'Dask-gateway scheduler pod memory usage',
  datasource='$PROMETHEUS_DS',
  unit='bytes',
  thresholds=[
    {
      value: 0,
      color: 'green',
    },
    {
      value: 600,
      color: 'yellow',
    },
  ]
).addTargets([
  // Computes sum of pod memory requests, grouped by username, and dask-gateway cluster
  // for dask-gateway scheduler pods
  prometheus.target(
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
    legendFormat='{{label_hub_jupyter_org_username}}-{{label_gateway_dask_org_cluster}}',
  ),
]);

dashboard.new(
  'Usage Report',
  uid='usage-report',
  tags=['jupyterhub', 'dask'],
  editable=true,
).addTemplates(
  templates
).addPanel(
  memoryUsageUserPods,
  gridPos={
    x: 0,
    y: 0,
    w: 25,
    h: 10,
  },
).addPanel(
  memoryUsageDaskWorkerPods,
  gridPos={
    x: 0,
    y: 10,
    w: 25,
    h: 10,
  },
).addPanel(
  memoryUsageDaskSchedulerPods,
  gridPos={
    x: 0,
    y: 20,
    w: 25,
    h: 10,
  },
)
