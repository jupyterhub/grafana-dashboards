# Look at individual user metrics

A common support request for JupyterHub admins pertains to specific issues
faced by a particular user. The "User Diagnostics" dashboard helps displaying
metrics on a per-user level. It also helps look for *outliers* in a hub –
people using too much of a particular resource, or not enough of a particular
resource.

The "Pod Diagnostics" dashboard displays metrics on a per-user per-server level.
For example, a JupyterHub can be configured to [allow multiple named servers per user](https://jupyterhub.readthedocs.io/en/stable/howto/configuration/config-user-env.html#named-servers) running at the same time.

## Home directory size (with shared volumes)

If you use a shared volume (such as NFS) for home directory storage, you can
use the [prometheus-dirsize-exporter](https://github.com/yuvipanda/prometheus-dirsize-exporter)
to efficiently collect information about the *size* of each user's home directory.
Once [deployed](howto:deploy:per-user-home-dir), the exporter will collect slowly
collect informatiohn about the size of each user's home directory and make that
available to prometheus. The "Home directory usage (on shared home directories)"
graph will display this over time.

```{note}
The exporter is optimized to use as few IOPS as possible, to make sure we do
not reduce performance for end users actually using the home directories to store
stuff. As a result, the sizes will probably be out of date and take a while to
update, depending on how big the home directories are. Use these for general
monitoring, nothing realtime.
```
