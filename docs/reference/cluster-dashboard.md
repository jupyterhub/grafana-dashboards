# The Cluster Information dashboard

The cluster dashboard contains several panels that show relevant cluster-wide information.

## Running Users

Count of running users, grouped by namespace.

## Memory commitment %

% of total memory in the cluster currently requested by to non-placeholder pods.
If autoscaling is efficient, this should be a fairly constant, high number (>70%).

## CPU commitment %

% of total CPU in the cluster currently requested by to non-placeholder pods.
JupyterHub users mostly are capped by memory, so this is not super useful.

## Node CPU Commit %

% of each node guaranteed to pods on it.

## Node Memory Commit %

% of each node guaranteed to pods on it.

## Node Memory Utilization %

% of available Memory currently in use.

## Node CPU Utilization %

% of available CPUs currently in use.

## Out of Memory kill count

Number of Out of Memory (OOM) kills in a given node.

When users use up more memory than they are allowed, the notebook kernel they
were running usually gets killed and restarted. This graph shows the number of times
that happens on any given node, and helps validate that a notebook kernel restart was
in fact caused by an OOM.

## Pods not in Running state

Pods in states other than 'Running'.
In a functional clusters, pods should not be in non-Running states for long.