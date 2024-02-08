# Cluster Information

The cluster dashboard contains several panels that show relevant cluster-wide information.

```{warning}
This section is a Work in Progress!
```

## Cluster Stats

### Running Users

Number of currently running users per hub. Common shapes this visualization may take:

1. A large number of users starting servers at exactly the same time will be visible here as a single spike, and may cause stability issues. Since they share the same cluster, such spikes happening on a *different* hub may still affect your hub.

### Memory commitment %

Percentage of memory in cluster guaranteed to user workloads. Common shapes:

1. If this is consistently low (<50%), you are paying for cloud compute that you do not need. Consider reducing the size of your nodes, or increasing the amount of memory guaranteed to your users. Some variability based on time of day is to be expected.

### CPU commitment %

Percentage of total CPU in the cluster currently guaranteed to user workloads.

Most commonly, JupyterHub workloads are *memory bound*, not CPU bound. So this is not a particularly helpful graph.

Common shapes:
1. If this is *consistently high* but shaped differently than your memory commitment graph, consider changing your CPU requirements.

### Node count

Number of nodes in each nodepool in this cluster.

### Pods not in Running state

Pods in states other than 'Running'.
In a functional clusters, pods should not be in non-Running states for long.

## Node stats

### Node CPU Commit %

Percentage of each node guaranteed to pods on it.

### Node Memory Commit %

Percentage of each node guaranteed to pods on it. When this hits 100%, the autoscaler will spawn a new node and the scheduler will stop putting pods on the old node.

### Node Memory Utilization %

Percentage of available Memory currently in use.

### Node CPU Utilization %

Percentage of available CPUs currently in use.

### Out of Memory kill count

Number of Out of Memory (OOM) kills in a given node.

When users use up more memory than they are allowed, the notebook kernel they
were running usually gets killed and restarted. This graph shows the number of times
that happens on any given node, and helps validate that a notebook kernel restart was
in fact caused by an OOM.
