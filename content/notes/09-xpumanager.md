+++
authors = ["Kalin Daskalov"]
title = "Lab Notes: XPU Manager 2.0 finally lets me delete my custom image"
date = "2026-06-13"
description = "A short lab note on replacing my custom Intel XPU Manager deployment with the upstream XPUMD 2.0 Helm chart and image."
categories = ["lab notes"]
tags = ["k8s", "intel", "gpu", "xpumanager", "xpumd", "dra", "kubernetes", "homelab", "fluxcd", "observability"]
+++

> Disclaimer: This is lab documentation, not production guidance. It describes what changed in my cluster and why I am happy to delete a workaround.

---

## Table of Contents

* [00 Finally, a boring XPU Manager install](#00-finally-a-boring-xpu-manager-install)
* [01 What I used to do](#01-what-i-used-to-do)
* [02 The DRA monitor shape I was patching toward](#02-the-dra-monitor-shape-i-was-patching-toward)
* [03 What changed upstream](#03-what-changed-upstream)
* [04 The new shape in my cluster](#04-the-new-shape-in-my-cluster)
* [05 The metric name situation](#05-the-metric-name-situation)
* [06 What this removes from my life](#06-what-this-removes-from-my-life)
* [References](#references)

---

## 00 Finally, a boring XPU Manager install

This is a small update, but it removes one of the uglier pieces of my GPU observability setup.

Intel XPU Manager has been one of those pieces in my homelab that I needed, but did not particularly enjoy maintaining.

I wanted GPU telemetry from the Intel Arc cards in my Kubernetes cluster. For a while, the implementation was very ugly.

Now XPU Manager 2.0 ships an upstream OCI Helm chart:

```text
oci://ghcr.io/intel/xpumanager/charts/xpumd
```

The chart pulls the upstream image:

```text
ghcr.io/intel/xpumanager/xpumd:v2.0.0
```

---

## 01 What I used to do

The old setup in my GitOps repo was not something I was proud of.

I had a Flux `GitRepository` pointed at `intel/xpumanager`, then a Flux `Kustomization` pointed into the upstream Kubernetes daemonset base.

On top of that I patched the DaemonSet hard enough to make it fit my cluster:

* replace both container images
* add a GPU-node toleration
* force scheduling to `sonda-core`
* add a DRA `ResourceClaimTemplate`
* attach the DRA claim to the container resources
* remove the original GPU resource limits
* set `ZES_ENABLE_SYSMAN=1`
* maintain a separate Service on port `29999`
* maintain a separate ServiceMonitor

The image was the worst part.

I had a custom image under `sonda-red/custom-images` because the public container path I had been using looked stale for my needs.

That was not some clever platform abstraction. It was just a workaround that became infrastructure.

The Dockerfile was doing more than I want a lab image to do:

* build on Ubuntu 24.04
* install a Python virtual environment
* pull the XPUM `1.3.7` deb from the GitHub release
* install Intel GPU userspace packages
* create an entrypoint that started `xpumd`
* expose the old REST exporter path through Gunicorn

In rough terms, it was this shape:

```text
ubuntu:24.04
  -> Python venv
  -> Flask / prometheus-client / grpcio / protobuf / gunicorn
  -> Intel graphics PPA packages
  -> xpumanager_1.3.7_...u24.04_amd64.deb
  -> custom entrypoint
  -> xpumd + REST exporter on port 29999
```

My old active image looked like this in the manifests:

```text
ghcr.io/sonda-red/xpumanager@sha256:...
```

That is useful when you need to unblock yourself. It is not where I want the lab to stay.

This is the kind of thing that works, then becomes normal, then becomes suspicious because you cannot quite remember all the reasons it exists.

---

## 02 The DRA monitor shape I was patching toward

The other reason my old setup became awkward was DRA.

I have written about DRA a few times in this series already, so I will not re-explain the whole model here. The specific part that matters for this note is monitor access.

Intel's GPU DRA documentation includes a monitor pod example using a `ResourceClaimTemplate` with monitor-style access.

The YAML is verbose, but the important part is the claim shape:

```yaml
apiVersion: resource.k8s.io/v1
kind: ResourceClaimTemplate
metadata:
  name: monitor-claim
spec:
  spec:
    devices:
      requests:
        - name: gpu
          exactly:
            deviceClassName: gpu.intel.com
            adminAccess: true
            allocationMode: "All"
            tolerations:
              - effect: NoExecute
              - effect: NoSchedule
---
apiVersion: v1
kind: Pod
metadata:
  name: monitor-pod
spec:
  restartPolicy: Never
  containers:
    - name: monitor
      image: registry.k8s.io/e2e-test-images/busybox:1.29-2
      command: ["sh", "-c", "ls -la /dev/dri/ && sleep 60"]
      resources:
        claims:
          - name: resource
  resourceClaims:
    - name: resource
      resourceClaimTemplateName: monitor-claim
```

That is the important distinction:

* a normal inference pod should request the GPU resources it needs
* a monitor needs visibility into devices on the node
* the monitor should not make those devices unavailable to actual workloads

So the shape I wanted was clear:

```text
DaemonSet
  -> runs on the GPU node
  -> gets DRA monitor access
  -> exposes Prometheus metrics
  -> does not consume a normal GPU allocation
```

The problem was that I was assembling that shape myself by patching upstream manifests after the fact.

---

## 03 What changed upstream

XPU Manager 2.0 changes the shape quite a bit.

The old 1.x world had a C++ daemon and a separate Python exporter path. Metrics came out with XPUM-specific names like:

```text
xpum_power_watts
xpum_temperature_celsius
xpum_memory_used_bytes
```

XPUMD 2.x is a Go daemon built around OpenTelemetry components and Level Zero Go bindings. The Prometheus endpoint is still there, but the exported metric names now follow OpenTelemetry-style conventions, for example:

```text
hw_gpu_utilization_ratio
hw_temperature_celsius
hw_memory_usage_bytes
```

The chart also understands GPU monitor access directly:

```yaml
gpuAccess: dra
```

That single value is the part I had been patching toward. It tells the chart to use the monitor shape above instead of making me splice that behavior into the DaemonSet after rendering.

So instead of patching the upstream DaemonSet after the fact, I can tell the chart what I mean.

---

## 04 The new shape in my cluster

The new local module is much simpler.

First, the OCI chart source:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: xpumanager
  namespace: intel
spec:
  interval: 1m
  type: oci
  url: oci://ghcr.io/intel/xpumanager/charts
```

Then the `HelmRelease`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: xpumanager
  namespace: intel
spec:
  interval: 5m
  chart:
    spec:
      chart: xpumd
      version: 2.0.0
      sourceRef:
        kind: HelmRepository
        name: xpumanager
        namespace: intel
```

And the values that matter for my cluster:

```yaml
fullnameOverride: intel-xpumanager

image:
  repository: ghcr.io/intel/xpumanager/xpumd
  tag: "v2.0.0"

gpuAccess: dra

nodeSelector:
  kubernetes.io/hostname: sonda-core

tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: PreferNoSchedule

extraEnv:
  - name: ZES_ENABLE_SYSMAN
    value: "1"

prometheus:
  monitor: true
  release: kube-prometheus-stack

config:
  service:
    pipelines:
      metrics:
        receivers: [intelxpu]
        processors: [intelxpustatus]
        exporters: [intelxpuinfo, prometheus]
```

In my lab I hardcode the hostname because `sonda-core` is the GPU node.

In a larger cluster I would use GPU node labels, for example labels from Node Feature Discovery, instead of binding the monitor DaemonSet to a specific node name.

With these values enabled, the chart now creates the pieces I used to maintain locally:

* `ServiceAccount`
* `ConfigMap`
* `DaemonSet`
* `Service`
* `ResourceClaimTemplate`
* `ServiceMonitor`

---

## 05 The metric name situation

My old local dashboard queried `xpum_*` metrics. That dashboard had to go because XPUMD 2.x exposes different metric names.

I switched Grafana provisioning to the tagged upstream 2.0 dashboard:

```text
https://raw.githubusercontent.com/intel/xpumanager/refs/tags/v2.0.0/xpumd/charts/xpumd/json/dashboard.json
```

After switching the dashboard provisioning, the new panels came back like this:

[![XPUMD 2.0 Grafana dashboard](/images/post-09/new-xpumanager-dashboard.png)](/images/post-09/new-xpumanager-dashboard.png)

Examples of the new shape:

```promql
avg by (pci_bdf) (hw_gpu_utilization_ratio{node="$Node"})
```

```promql
hw_temperature_celsius{statistic="max", node="$Node", hw_sensor_location="gpu"}
```

```promql
hw_memory_usage_bytes{node="$Node"} / hw_memory_size_bytes{node="$Node"}
```

I like this direction. The names are less tied to XPUM internals and more aligned with the broader telemetry ecosystem.

The practical migration note is simple: the pods can be healthy while the dashboard is blank. Check the metric names before blaming Prometheus.

---

## 06 What this removes from my life

This is the full list of things I got to delete or stop caring about:

* my custom `ghcr.io/sonda-red/xpumanager` image
* the custom Dockerfile that rebuilt XPUM 1.x around Ubuntu, Python, Gunicorn, and Intel userspace packages
* the patched upstream DaemonSet source
* the separate XPU Manager Service
* the separate ServiceMonitor Kustomization
* the hand-written monitor `ResourceClaimTemplate`
* the old `xpum_*` dashboard
* the Renovate custom manager that tracked XPU Manager as a Git tag

That is the part that makes me happy.

This whole homelab project has a pattern: I build something that barely works, then slowly replace the weird bits as the upstream projects catch up or as I understand the problem better.

I do not regret the custom image. It got me telemetry when I needed telemetry.

But I am very glad it is not special anymore.

The best infrastructure change is often the one that removes your cleverness.

In this case, the final result is boring:

```text
Flux HelmRelease
  -> upstream xpumd chart 2.0.0
  -> upstream xpumd image v2.0.0
  -> chart-managed DRA monitor claim
  -> chart-managed ServiceMonitor
  -> upstream XPUMD 2 dashboard
```

---

## References

* [Intel XPU Manager](https://github.com/intel/xpumanager)
* [XPU Manager 2.0.0 release](https://github.com/intel/xpumanager/releases/tag/v2.0.0)
* [XPUM 1.x vs 2.x changes](https://github.com/intel/xpumanager/blob/v2.0.0/xpumd/docs/CHANGES.md)
* [XPUMD Helm chart](https://github.com/intel/xpumanager/tree/v2.0.0/xpumd/charts/xpumd)
* [Intel GPU DRA monitor deployment](https://github.com/intel/intel-resource-drivers-for-kubernetes/tree/main/doc/gpu#gpu-monitor-deployment)
* [Intel GPU DRA monitor pod example](https://github.com/intel/intel-resource-drivers-for-kubernetes/blob/main/deployments/gpu/examples/monitor-pod-inline.yaml)
* [intel/xpumanager#121: Create CI/CD to Regularly Update DockerHub](https://github.com/intel/xpumanager/issues/121)
