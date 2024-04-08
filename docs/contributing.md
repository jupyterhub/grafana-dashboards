(contributing)=
# Contributing

Hello and thank you for contributing to JupyterHub Grafana Dashboards!
We are really excited to have you here!

Below you'll find some useful tasks, guidelines, and instructions for working
in this repository.

Notice something that's missing? Please open an issue or file a pull request!

## Development tasks and guidelines

### Partial setup of a development environment

You need to have a Grafana instance with a Prometheus datasource collecting
metrics to test changes to the dashboards against. Assuming you have that,
prepare a Grafana API token to use. Further details on how is not included
currently in these docs.

With that setup, and Python installed, you only need `jsonnet` installed.
Install `jsonnet` distributed via the go-jsonnet project, for example via
[go-jsonnet's GitHub Releases] page. There is a C++ based version of `jsonnet`
developed in parallel, but this project is only tested against the go-jsonnet
project's binaries currently.

[`go-jsonnet`'s GitHub Releases]: https://github.com/google/go-jsonnet/releases

### Tweaking dashboard settings

Dashboards are `.json` files generated from `.jsonnet` files using `jsonnet`
like this:

```shell
# --tla-code flag is currently only relevant for global-dashboards
jsonnet -J vendor --tla-code 'datasources=["prometheus-test"]' dashboards/cluster.json
```

To tweak dashboard settings in the `.jsonnet` files can be tricky. One way to do
it is to first trial changes via Grafana's UI where you can edit dashboards, and
then look at [grafonnet's API docs] to figure out what you should change to
mimic what you did via the UI.

Once you have tweaked a `.jsonnet` file and optionally first tested it renders
with `jsonnet`, you can deploy dashboards to a Grafana instance like this:

```shell
# note the space before the sensitive command below,
# it makes it not get saved into shell history
 export GRAFANA_TOKEN=...

# deploy all dashboards in the dashboards folder using
# the environment variable GRAFANA_TOKEN
./deploy.py --dashboards-dir dashboards https://grafana-domain.example.com
```

[grafonnet's API docs]: https://grafana.github.io/grafonnet/API/index.html

### Upgrading the grafonnet version

The grafonnet jsonnet library is bundled here with [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler).
Just running `jb update` in the git repo root dir after installing jsonnet-bunder should bring
you up to speed.

### Metrics guidelines

Interpreting prometheus metrics and writing PromQL queries that serve a particular
purpose can be difficult. Here are some guidelines to help.

#### Container memory usage metric

"When will the OOM killer start killing processes in this container?" is the most useful
thing for us to know when measuring container memory usage. Of the many container memory
metrics, `container_memory_working_set_bytes` tracks this (see [this blog post](https://faun.pub/how-much-is-too-much-the-linux-oomkiller-and-used-memory-d32186f29c9d)
and [this issue](https://github.com/jupyterhub/grafana-dashboards/issues/13)).
So prefer using that metric as the default for 'memory usage' unless specific reasons
exist for using a different metric.

#### Available metrics

The most common prometheus on kubernetes setup in the JupyterHub community seems
to be the [prometheus helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus).

1. [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
   ([metrics documentation](https://github.com/kubernetes/kube-state-metrics/tree/master/docs))
   collects information about various kubernetes objects (pods, services, etc)
   by scraping the kubernetes API. Anything you can get via `kubectl` commands,
   you can probably get via a metric here. Very helpful as a way to query other
   metrics based on the kubernetes object they represent (like pod, node, etc).

2. [node-exporter](https://github.com/prometheus/node_exporter)
   ([metrics documentation](https://github.com/prometheus/node_exporter#enabled-by-default))
   collects information about each node - CPU usage, memory, disk space, etc. Since hostnames
   are usually random, you usually join these metrics with `kube-state-metrics` node
   metrics to get useful information out. If you are running a manual NFS server,
   it is recommended to run a node-exporter instance there as well to collect server
   metrics.

3. [cadvisor](https://github.com/google/cadvisor)
   ([metrics documentation](https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md))
   collects information about each *container*. Join these with pod metrics from
   `kube-state-metrics` for useful queries.

4. [jupyterhub](https://jupyterhub.readthedocs.io/en/latest/)
   ([metrics documentation](https://jupyterhub.readthedocs.io/en/latest/reference/metrics.html))
   collects information directly from the JupyterHubs.

5. Other components you have installed on your cluster - like prometheus,
   nginx-ingress, etc - will also emit their own metrics.

#### Avoid double-counting container metrics

It seems that one container's resource metrics can be reported multiple times,
with an empty `name` label and a `name=k8s_...` label.
Because of this, if we do `sum(container_resource_metric) by (pod)`,
we will often get twice the actual resource consumption of a given pod.
Since `name=""` is always redundant, make sure to exclude this in any query
that includes a sum across container metrics.
For example:

```promql
sum(
    irate(container_cpu_usage_seconds_total{name!=""}[5m])
) by (namespace, pod)
```

## Working with our documentation

### Building the docs locally with `nox`

[`nox`](https://nox.thea.codes/en/stable/) is a command line tool that automates
testing in multiple Python environments, using a standard Python file for configuration.

You can install `nox` using `pip` via:

```bash
pip install nox
```

To build the docs locally, you can then run:

```bash
nox -s docs
```

This will generate the html files and output them to the `docs/_build/html` folder.

If you would like to start a live server that reloads as you make changes, you can run:

```bash
nox -s docs -- live
```
