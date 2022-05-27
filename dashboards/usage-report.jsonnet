local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local prometheus = grafana.prometheus;
local template = grafana.template;
local barGaugePanel = grafana.barGaugePanel;

local jupyterhub = import 'jupyterhub.libsonnet';

local standardDims = { w: 30, h: 30 };

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
).addTargets([
  prometheus.target(
    |||
      max(
        kube_pod_labels{
          label_app="jupyterhub",
          label_component="singleuser-server",
          namespace=~"$hub"
        }
        * on (namespace, pod, hub_jupyter_org_username) group_left()
        container_memory_working_set_bytes{
          namespace=~"$hub",
          container="notebook",
          hub_jupyter_org_node_purpose="user"
        }
      ) by (namespace, pod, label_hub_jupyter_org_username)
    |||,
    legendFormat='{{label_hub_jupyter_org_username}}',
  ),
]);

dashboard.new(
  'Usage Report',
  uid='usage-report',
  tags=['jupyterhub'],
  editable=true,
).addTemplates(
  templates
)

.addPanel(
  memoryUsageUserPods, {},
)