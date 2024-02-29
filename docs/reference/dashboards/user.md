# User Diagnostics

```{warning}
This section is a Work in Progress!
```

## Memory Usage

Per-user per-server memory usage

## CPU Usage

Per-user per-server CPU usage

## Home Directory Usage (on shared home directories)

Per user home directory size, when using a shared home directory.

Requires https://github.com/yuvipanda/prometheus-dirsize-exporter to
    be set up.

Similar to server pod names, user names will be *encoded* here
using the escapism python library (https://github.com/minrk/escapism).
You can unencode them with the following python snippet:

from escapism import unescape
unescape('<escaped-username>', '-')

## Memory Requests

Per-user per-server memory Requests

## CPU Requests

Per-user per-server CPU Requests