# Grafana Dashboards for JupyterHub

Grafana Dashboards for use with [Zero to JupyterHub on Kubernetes](http://z2jh.jupyter.org/)

## What?

Grafana dashboards displaying prometheus metrics are *extremely* useful in diagnosing
issues on Kubernetes clusters running JupyterHub. However, everyone has to build their
own dashboards - there isn't an easy way to standardize them across many clusters run
by many entities.

This project provides some standard [Grafana Dashboards as Code](https://grafana.com/blog/2020/02/26/how-to-configure-grafana-as-code/)
to help with this. It uses [jsonnet](https://jsonnet.org/) and
[grafonnet](https://github.com/grafana/grafonnet-lib) to generate dashboards completely
via code. This can then be deployed on any Grafana instance!

## Pre-requisites

1. Locally, you need to have
   [jsonnet](https://github.com/google/jsonnet#packages) installed.  The
   [grafonnet](https://grafana.github.io/grafonnet-lib/) library is already
   vendored in, using
   [jsonnet-builder](https://github.com/jsonnet-bundler/jsonnet-bundler).

2. A recent version of prometheus installed on your cluster. Currently, it is assumed that your prometheus instance
   is installed using the prometheus helm chart, with [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics),
   [node-exporter](https://github.com/prometheus/node_exporter) and [cadvisor](https://github.com/google/cadvisor)
   enabled. In addition, you should scrape metrics from the hub instance as well.

3. A recent version of Grafana, with a prometheus data source already added.

4. An API key with 'editor' permissions. This is per-organization, and you can make a new one
   by going to the configuration pane for your Grafana (the gear icon on the left bar), and
   selecting 'API Keys'. 
   
## Deployment

There's a helper `deploy.py` script that can deploy the dashboard to any grafana installation.

```bash
export GRAFANA_TOKEN="<API-TOKEN-FOR-YOUR-GRAFANA>
./deploy.py <url-to-your-grafana-install> jupyterhub.jsonnet
```

This should create a dashboard called 'JupyterHub Dashboard' in your grafana installation!

Grafana doesn't populate the 'hub' variable properly by default. You'll need to:

1. Go to your Dashboard 
2. Go to settings (gear icon in top right)
3. Select the 'hub' variable
4. Click the 'Update' button

This will show you the hubs on your cluster, and then you can select them from the dropdown.

**NOTE: ANY CHANGES YOU MAKE VIA THE GRAFANA UI WILL BE OVERWRITTEN NEXT TIME YOU RUN deploy.py.
TO MAKE CHANGES, EDIT THE JSONNET FILE AND DEPLOY AGAIN**
