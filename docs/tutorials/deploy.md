(tutorials:deploy)=
# Deploying the dashboards

```{warning}
ANY CHANGES YOU MAKE VIA THE GRAFANA UI WILL BE OVERWRITTEN NEXT TIME YOU RUN deploy.bash.
TO MAKE CHANGES, EDIT THE JSONNET FILE AND DEPLOY AGAIN
```

## Pre-requisites

1. Locally, you need to have
   [jsonnet](https://github.com/google/jsonnet#packages) installed.  The
   [grafonnet](https://grafana.github.io/grafonnet-lib/) library is already
   vendored in, using
   [jsonnet-builder](https://github.com/jsonnet-bundler/jsonnet-bundler).

2. A recent version of prometheus installed on your cluster. Currently, it is assumed that your prometheus instance
   is installed using the [prometheus helm
   chart](https://github.com/prometheus-community/helm-charts), with
   [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics),
   [node-exporter](https://github.com/prometheus/node_exporter) and
   [cadvisor](https://github.com/google/cadvisor) enabled. In
   addition, you should scrape metrics from the hub instance as well.

    ```{tip}
    If you're using a prometheus chart older than version `14.*`, then you can deploy the dashboards available prior to the upgrade, in the [`1.0 tag`](https://github.com/jupyterhub/grafana-dashboards/releases/tag/1.0).
    ```

3. `kube-state-metrics` must be configured to add some labels to metrics
   [since version 2.0](https://kubernetes.io/blog/2021/04/13/kube-state-metrics-v-2-0/).
   If deployed with the prometheus helm chart, the config should look like this:

   ```yaml
   kube-state-metrics:
      metricLabelsAllowlist:
         # to select jupyterhub component pods and get the hub usernames
         - pods=[app,component,hub.jupyter.org/username]
         # allowing all labels is probably fine for nodes, since they don't churn much, unlike pods
         - nodes=[*]
   ```

   ```{tip}
   Make sure this is indented correctly where it should be!
   ```

4. A recent version of Grafana, with a prometheus data source already added.

5. An API key with 'admin' permissions. This is per-organization, and you can make a new one
   by going to the configuration pane for your Grafana (the gear icon on the left bar), and
   selecting 'API Keys'. The admin permission is needed to query list of data sources so we
   can auto-populate template variable options (such as list of hubs).

## Additional prometheus exporters

Some very useful metrics (such as home directory free space) require
additional collectors to be installed in your cluster, customized to your
needs.

### Free space (%) in shared volume (Home directories, etc.)

In many common z2jh configurations, home directories are setup via a shared
filesystem (like NFS, AzureFile, etc). You can grab additional metrics by
a deployment of [prometheus node_exporter](https://prometheus.io/docs/guides/node-exporter/),
collecting just the filesystem metrics. Here is an example deployment YAML:

```yaml
# To provide data for the jupyterhub/grafana-dashboards dashboard about free
# space in the shared volume, which contains users home folders etc, we deploy
# prometheus node-exporter to collect this data for prometheus server to scrape.
#
# This is based on the Deployment manifest in jupyterhub/grafana-dashboards'
# readme: https://github.com/jupyterhub/grafana-dashboards#additional-collectors
#
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: jupyterhub
    component: shared-volume-metrics
  name: shared-volume-metrics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jupyterhub
      component: shared-volume-metrics
  template:
    metadata:
      annotations:
        # This enables prometheus to actually scrape metrics from here
        prometheus.io/scrape: "true"
        prometheus.io/port: "9100"
      labels:
        app: jupyterhub
        # The component label below should match a grafana dashboard definition
        # in jupyterhub/grafana-dashboards, do not change it!
        component: shared-volume-metrics
    spec:
      containers:
      - name: shared-volume-exporter
        image: quay.io/prometheus/node-exporter:v1.5.0
        args:
          # We only want filesystem stats
          - --collector.disable-defaults
          - --collector.filesystem
          - --web.listen-address=:9100
        ports:
          - containerPort: 9100
            name: metrics
            protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          runAsGroup: 65534
          runAsNonRoot: true
          runAsUser: 65534
        volumeMounts:
          - name: shared-volume
            # Mounting under /shared-volume is important as we reference this
            # path in our dashboard definition.
            mountPath: /shared-volume
            # Mount it readonly to prevent accidental writes
            readOnly: true
      securityContext:
        fsGroup: 65534
      volumes:
        # This is the volume that we will mount and monitor. You should reference
        # a shared volume containing home directories etc. This is often a PVC
        # bound to a PV referencing a NFS server.
        - name: shared-volume
          persistentVolumeClaim:
            claimName: home-nfs
```

You will likely only need to adjust the `claimName` above to use this example.

(howto:deploy:per-user-home-dir)=
### Per-user home directory metrics (size, last modified, total entries, etc)

When using a shared home directory for users, it is helpful to collect information
on each user's home directory - total size, last time any files within it were
modified, etc. This helps notice when a single user is using a lot of space,
often accidentally! The [prometheus-dirsize-exporter](https://github.com/yuvipanda/prometheus-dirsize-exporter)
can be deployed to collect this information efficiently for querying. Here is
an example YAML for deployment:

```yaml
# To provide data for the jupyterhub/grafana-dashboards dashboard about per-user
# home directories in the shared volume, which contains users home folders etc, we deploy
# prometheus node-exporter to collect this data for prometheus server to scrape.
#
# This is based on the Deployment manifest in jupyterhub/grafana-dashboards'
# readme: https://github.com/jupyterhub/grafana-dashboards#additional-collectors
#
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shared-dirsize-metrics
  labels:
    app: jupyterhub
    component: shared-dirsize-metrics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jupyterhub
      component: shared-dirsize-metrics
  template:
    metadata:
      annotations:
        # This enables prometheus to actually scrape metrics from here
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
      labels:
        app: jupyterhub
        component: shared-dirsize-metrics
    spec:
      containers:
        - name: dirsize-exporter
          # From https://github.com/yuvipanda/prometheus-dirsize-exporter
          image: quay.io/yuvipanda/prometheus-dirsize-exporter:v1.2
          resources:
            # Provide *very few* resources for this collector, as it can
            # baloon up (especially in CPU) quite easily. We are quite ok with
            # the collection taking a while as long as we aren't costing too much
            # CPU or RAM
            requests:
              memory: 16Mi
              cpu: 0.01
            limits:
              cpu: 0.05
              memory: 128Mi
          command:
            - dirsize-exporter
            - /shared-volume
            - "250" # Use only 250 io operations per second at most
            - "120" # Wait 2h between runs
            - --port=8000
          ports:
            - containerPort: 8000
              name: dirsize-metrics
              protocol: TCP
          securityContext:
            allowPrivilegeEscalation: false
            runAsGroup: 0
            runAsUser: 1000
          volumeMounts:
            - name: shared-volume
              mountPath: /shared-volume
              readOnly: true
      securityContext:
        fsGroup: 65534
      volumes:
        # This is the volume that we will mount and monitor. You should reference
        # a shared volume containing home directories etc. This is often a PVC
        # bound to a PV referencing a NFS server.
        - name: shared-volume
          persistentVolumeClaim:
            claimName: home-nfs

```

You will likely only need to adjust the `claimName` above to use this example.

## Deploy the dashbaords

There's a helper `deploy.py` script that can deploy the dashboards to any grafana installation.

```bash
export GRAFANA_TOKEN="<API-TOKEN-FOR-YOUR-GRAFANA>
./deploy.py <your-grafana-url>
```

This creates a folder called 'JupyterHub Default Dashboards' in your grafana, and adds
a couple of dashboards to it.

If your Grafana deployment supports more than one datasource, then apart from the default dashboards in the [`dashboards` directory](https://github.com/jupyterhub/grafana-dashboards/tree/main/dashboards), you should also consider deploying apart the dashboards in [`global-dashboards` directory](https://github.com/jupyterhub/grafana-dashboards/tree/main/global-dashboards).

```bash
export GRAFANA_TOKEN="<API-TOKEN-FOR-YOUR-GRAFANA>
./deploy.py <your-grafana-url> --dashboards-dir global-dashboards
```

The global dashboards will use the list of available dashboards in your Grafana provided to them and will build dashboards across all of them.

If your Grafana instance uses a self-signed certificate, use the `--no-tls-verify` flag when executing the `deploy.py` script. For example:

```bash
./deploy.py <your-grafana-url> --no-tls-verify
```
