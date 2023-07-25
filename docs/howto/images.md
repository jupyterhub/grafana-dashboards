# Find what images users are using

With kubespawner's `profileList` feature, end users may choose different
images to launch. It is useful to measure what images are being used so we
can serve our users better over time.

The "Images used by user pods" graph in the JupyterHub dashboard helps with this.
It shows the popularity of various images used over time. Note that if an image
is no used at all, it will not be shown.
