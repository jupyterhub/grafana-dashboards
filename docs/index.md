# Welcome to JupyterHub Grafana Dashboards's documentation!

Grafana Dashboards for use with [Zero to JupyterHub on Kubernetes](http://z2jh.jupyter.org/)

![Grafana Dasboard Screencast](../demo.gif)

## What?

Grafana dashboards displaying prometheus metrics are *extremely* useful in diagnosing
issues on Kubernetes clusters running JupyterHub. However, everyone has to build their
own dashboards - there isn't an easy way to standardize them across many clusters run
by many entities.

This project provides some standard [Grafana Dashboards as Code](https://grafana.com/blog/2020/02/26/how-to-configure-grafana-as-code/)
to help with this. It uses [jsonnet](https://jsonnet.org/) and
[grafonnet](https://github.com/grafana/grafonnet-lib) to generate dashboards completely
via code. This can then be deployed on any Grafana instance!

## How the documentation is organised

We are currently using the [diátaxis framework](https://diataxis.fr/) to organise
our docs into four main categories:

- [**Tutorials**](tutorials): Step-by-step guides to complete a specific task
- **How-To guides**: Directions to solve scenarios faced while using the project. Their titles often complete the sentence "How do I...?"
- [**Explanation**](explanation): More in-depth discussion of topics within the project to broaden understanding.
- [**Reference**](ref): Technical descriptions of the components within the project, and how to use them

### Tutorials

```{toctree}
:maxdepth: 2
tutorials/index.md
```

### How-to

```{toctree}
:maxdepth: 2
howto/deploy.md
howto/user-diagnostics.md
howto/images.md
```

### Explanation

```{toctree}
:maxdepth: 2
explanation/index.md
```

### Reference

```{toctree}
reference/index.md
```

## Contributing

Thank you for considering contributing! You can find some details to help you
get started in the sections below.

```{toctree}
:maxdepth: 2
contributing.md
```
