# JupyterHub Dashboard

The JupyterHub dashboard contains several panels with useful stats about usage & diagnostics.

```{warning}
This section is a Work in Progress!
```

## Currently Active Users

## Daily Active Users

Number of unique users who were active within the preceeding 24h period.

Requires JupyterHub 3.1.

## Weekly Active Users

Number of unique users who were active within the preceeding 7d period.

Requires JupyterHub 3.1.

## Monthly Active Users

Number of unique users who were active within the preceeding 7d period.

Requires JupyterHub 3.1.

## Hub DB Disk Space Availability %

% of disk space left in the disk storing the JupyterHub sqlite database. If goes to 0, the hub will fail.

## Server Start Times

## Server Start Failures

Attempts by users to start servers that failed.

## Users per node

## Non Running Pods

Pods in a non-running state in the hub's namespace.

Pods stuck in non-running states often indicate an error condition.

## Free space (%) in shared volume (Home directories, etc.)

% of disk space left in a shared storage volume, typically used for users' home directories.

Requires an additional node_exporter deployment to work. If this graph is empty, look at the README for jupyterhub/grafana-dashboards to see what extra deployment is needed.

## Very old user pods

User pods that have been running for a long time (>8h).

This often indicates problems with the idle culler

## User Pods with high CPU usage (>0.5)

User pods using a lot of CPU

This could indicate a runaway process consuming resources unnecessarily.

## User pods with high memory usage (>80% of limit)

User pods getting close to their memory limit

Once they hit their memory limit, user kernels will start dying.

## Images used by user pods

Number of user servers using a container image.
