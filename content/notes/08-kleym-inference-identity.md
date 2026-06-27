+++
authors = ["Kalin Daskalov"]
title = "Kleym: Intro to creating SPIFFE workload identity from inference intent"
date = "2026-06-05"
description = "A personal technical note on building Kleym, a Kubernetes operator that maps inference resources to deterministic SPIFFE identity registration."
categories = ["lab notes"]
tags = ["k8s", "spiffe", "spire", "kubernetes", "operators", "controllers", "inference", "llm-d", "homelab"]
+++

This note introduces Kleym, my experimental Kubernetes operator for turning inference intent into deterministic SPIFFE identity registration through SPIRE Controller Manager.

> Disclaimer: This is lab documentation, not production guidance. It explains why I built Kleym, what boundary it covers today, and what I still need to test.

---

## Table of Contents

- [00 Personal notes](#00-personal-notes)
- [01 What am I doing here?](#01-what-am-i-doing-here)
- [02 The problem I am testing](#02-the-problem-i-am-testing)
- [03 What Kleym does today](#03-what-kleym-does-today)
- [04 The two identity modes](#04-the-two-identity-modes)
- [05 Why not just write ClusterSPIFFEID YAML?](#05-why-not-just-write-clusterspiffeid-yaml)
- [06 Reaching some limitations](#06-reaching-some-limitations)
- [07 What is ahead](#07-what-is-ahead)

---

> Some personal notes follow below. If you want the technical part, skip to [01 What am I doing here?](#01-what-am-i-doing-here) or use the table of contents.

## 00 Personal notes

I started this project because I needed something tangible that connected my work direction to the personal AI-on-Kubernetes work I've been describing here for a while.

My career has been following the pattern of finding a niche, then a niche within the niche. Two very important milestones:

1. Kubernetes - I knew I wanted to focus on it. I quickly figured out the ecosystem is already too broad, so it's best to actually choose what aspects of it intrigue you the most.
2. [Cluster API](https://cluster-api.sigs.k8s.io/) - I knew I wanted to deal with Kubernetes problems in a Kubernetes-native way, extending the API and building controllers instead of just running pipelines or different kinds of scripts.

Professionally, I feel super lucky. I moved closer to controller work and got introduced to SPIFFE/SPIRE. Kleym became a way to study the operator author's side more deliberately: reconciliation, CRDs, status, and controller-runtime. I had already used Go for a few small CLI tools instead of scripts, plus a larger web scraper project some years ago, but controller work was the missing layer I wanted to understand.

At the same time, my homelab pulled me into inference infrastructure. I just didn't want this AI train to pass me by, and I wasn't going to stop at a local `ollama run`; I wanted to run model serving on Kubernetes and understand the lower layers. It's too interesting to pass up: models are not just files, GPUs are not just devices, and vLLM is not just another HTTP deployment.

The project I'm describing here became the overlap: small enough to learn controller mechanics and identity on my own time, under my rules, but connected enough to inference infrastructure that I don't have to choose which one to compromise.

### Time, doubt, and AI help

Figuring out what to work on when you have so little time between work and family is super hard. I spent two on-and-off months around November to December 2025 writing the first spec draft. Every choice feels wrong, the topic feels interesting only to you, and there is constant doubt about whether it's worth it.

Luckily, I've felt these feelings before, and I know I just need to start somewhere and deal with the fact that almost every aspect of this exercise has tradeoffs. If I told myself it would take me more than 6 months to have a minimal controller project with a narrow first boundary, I'd honestly just not start. It's disheartening projecting these thoughts into the future, but looking back, I'm super glad I started. I have this pet project, and nobody can take away what I've learned through it. It's more valuable than any tech reading list you could possibly give me.

Deciding to use AI as an assistant has cut the time spent making this by orders of magnitude, and it's an interesting challenge to learn how to manage surrendering versus keeping control over a concept and implementation. I've been using mostly OpenAI Codex as a helper, as well as various types, flavours, and configurations of local models.

### Giving it a name

First, I called it `Terence`. Get it? Trusted Inference? No? Anyway... as soon as it started to take shape and was no longer just a joke for me, I started moulding the repo more seriously into what I understand as a well-structured Kubernetes controller project. I renamed it to `Kleym`, created a drill logo to go with my story, used my Hugo blog experience to create a docs page to log the design and learning process, and turned [sonda.red](https://sonda.red) into a mix of notes, projects, and technical work coming from me.

You can explore the `Kleym` codebase at [github.com/sonda-red/kleym](https://github.com/sonda-red/kleym), and the docs are published at [kleym.sonda.red](https://kleym.sonda.red/). I'm creating releases, and the project is still settling as I document the design and test the boundaries.

## 01 What am I doing here?

Workload identity sits in the infrastructure/security part of the stack, and you've probably seen it mentioned in that context and/or maybe under the guise of `zero trust`. Very briefly, it's the idea that a running workload should be able to prove "this is who I am" without relying on a long-lived secret. [SPIFFE](https://spiffe.io/) is a standard way to name that workload with a SPIFFE ID, for example:

```text
spiffe://example.org/ns/llm-d/pool/qwen3
```

[SPIRE](https://spiffe.io/docs/latest/spire-about/spire-concepts/) is one implementation of SPIFFE. It can issue short-lived credentials, called SVIDs, to workloads after matching them through selectors such as namespace, service account, pod labels, and container name.

Kleym sits one step before that issuance path. It's a Kubernetes operator that watches inference-aware resources from the Gateway API Inference extension and registers the expected logical identity of the model-serving workload in SPIRE.

## 02 The problem I am testing

The earlier notes followed the stack from running a model locally, to containerizing it, to building it for Kubernetes.

The [Intel AI inference MVP](/notes/05-intel-homelab-3/) got the first stable layer working: Intel Arc GPUs, DRA, ModelKits, Harbor, vLLM, Open WebUI, and enough observability to keep the stack understandable.

The [llm-d note](/notes/06-intel-homelab-4/) changed the routing model. `InferencePool` became [an LLM-aware backend instead of a Service](/notes/06-intel-homelab-4/#042-inferencepool-an-llm-aware-backend-instead-of-a-service), because a model-serving pool is not just another group of interchangeable HTTP pods.

After that, the Gateway API / agentgateway work made the routing boundary explicit because [Ingress could not follow the shape of the inference stack](/notes/07-intel-homelab-5/#01-why-ingress-couldnt-follow).

Securing the flow was a natural next issue to tackle because it just didn't feel serious to run vLLM with `--api-key`. As with everything else in this inference homelab journey, the solution just wasn't there initially.

I now had resources that describe inference intent, but default SPIRE configuration just produced a normal workload identity based on pod labels and service accounts. I could fine-tune a [`ClusterSPIFFEID`](https://github.com/spiffe/spire-controller-manager/blob/main/docs/clusterspiffeid-crd.md) to be more specific, but I'm changing models, scaling, scheduling, and routing too often to write and maintain those by hand. An obvious automation solution was a controller.

### To get into a bit more detail

- [`InferencePool`](https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/) describes where a serving pool lives
- [`InferenceObjective`](https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferenceobjective/) can describe a more specific model-serving target
- the workload service account is still a required identity boundary
- SPIRE Controller Manager already has `ClusterSPIFFEID` as the registration API
- SPIFFE IDs should stay logical and stable even when pods, nodes, and devices change

The difference is easier to see in YAML.

A normal `Service` selects pods and exposes a port. It does not say that the selected pods form a model-serving pool:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: qwen3
  namespace: llm-d
spec:
  selector:
    app: qwen3
  ports:
    - port: 8000
      targetPort: 8000
```

An `InferencePool` still needs selectors, but the object is part of an inference-aware API. Trimmed to the field Kleym currently consumes, it can become the stable source of "these pods are the serving pool I mean":

```yaml
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: qwen3
  namespace: llm-d
spec:
  selector:
    matchLabels:
      app: qwen3
```

Kleym needed to get the same selectors from the resource that describes the serving pool, instead of copying those labels into a separate identity manifest by hand.

## 03 What Kleym does today

Kleym has two pieces today.

The in-cluster `kleym-operator` watches an [`InferenceIdentityBinding`](https://kleym.sonda.red/reference/api/) custom resource, resolves Gateway API Inference Extension resources such as `InferencePool` and `InferenceObjective`, and renders a SPIRE Controller Manager `ClusterSPIFFEID`.

I've also made a `kleym` CLI to inspect what the operator is doing on a live cluster. The status command summarizes the visible install, required CRDs, operator readiness, binding health, and findings.

```sh
kleym status

Kleym
  CLI: v0.7.4
  Operator: Available
    Deployment: kleym-system/kleym-operator
    Ready: 1/1
    Version: v0.7.4
  Config:
    trustDomain: sonda.red.intra
    clusterSPIFFEIDClass: kleym
  API:
    InferenceIdentityBinding: v1alpha1

Bindings
  Total: 1
  Conditions:
    Ready: 1
    Conflict: 0
    InvalidRef: 0
    UnsafeSelector: 0
    RenderFailure: 0

Dependencies
  GAIE: Available
    InferencePool: v1
    InferenceObjective: v1alpha2
  SPIRE: Available
    ClusterSPIFFEID: v1alpha1
```

The inspect command resolves one binding and shows the rendered identity, expected `ClusterSPIFFEID`, current conditions, Kubernetes-visible matched pods, and findings.

Shortened, an inspection is meant to answer questions like this:

```bash
kleym inspect binding qwen3 -n llm-d

Identity
  Mode: PoolOnly
  SPIFFE ID: spiffe://kleym.sonda.red/ns/llm-d/pool/qwen3

ClusterSPIFFEID
  Name: kleym-operator-llm-d-qwen3-...
  Selectors:
    k8s:ns:llm-d
    k8s:sa:qwen3
    k8s:pod-label:app:qwen3

Matched pods
  llm-d/qwen3-decode-0
  llm-d/qwen3-decode-1

Findings
  none
```

Detailed info on the [`InferenceIdentityBinding`](https://kleym.sonda.red/reference/api/) can be found in the docs, but overall:

- `poolRef` anchors the identity to an `InferencePool`
- `objectiveRef` optionally narrows the identity to an `InferenceObjective`
- `serviceAccountName` gives the service account boundary
- `mode` chooses `PoolOnly` or `PerObjective`
- `containerName` gives `PerObjective` an extra container boundary

The rendered SPIFFE IDs stay logical to that boundary:

```text
spiffe://<trust-domain>/ns/<namespace>/pool/<pool-name>
spiffe://<trust-domain>/ns/<namespace>/objective/<objective-name>
```

Under the hood, the operator does a few things to complement the identity registration:

- resolve the referenced inference resources
- derive selectors from the pool
- add namespace and service-account safety selectors
- add the container selector for `PerObjective`
- refuse unsafe selectors
- refuse overlapping per-objective identities
- remove stale managed output when the binding becomes invalid
- report the reason through status conditions

## 04 The two identity modes

The modes are where the inference-specific part becomes more concrete.

### PoolOnly: one logical model pool, multiple replicas

In the llm-d note I wrote about what changes when a model-serving workload scales beyond one pod. The replicas are still part of one logical model-serving pool, but routing and scheduling become more interesting because of GPU placement, request cost, and cache locality.

From an identity point of view, the first simple rule is:

> If two pods are serving the same logical model pool, they usually need the same workload identity.

For example:

```text
qwen3-decode-0  app=qwen3  serviceAccount=qwen3  -> spiffe://kleym.sonda.red/ns/llm-d/pool/qwen3
qwen3-decode-1  app=qwen3  serviceAccount=qwen3  -> spiffe://kleym.sonda.red/ns/llm-d/pool/qwen3
```

That is the `PoolOnly` case:

```yaml
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: qwen3
  namespace: llm-d
spec:
  selector:
    matchLabels:
      app: qwen3
---
apiVersion: kleym.sonda.red/v1alpha1
kind: InferenceIdentityBinding
metadata:
  name: qwen3
  namespace: llm-d
spec:
  poolRef:
    name: qwen3
  serviceAccountName: qwen3
  mode: PoolOnly
```

Expected selector shape:

```text
k8s:ns:llm-d
k8s:sa:qwen3
k8s:pod-label:app:qwen3
```

### PerObjective: one pool, separate model objectives

The second case is when the pod or serving pool boundary is too broad.

Imagine one pool where different containers, or different objective-level serving paths, should not share the same identity. A chat model and an embedding model might be deployed together for operational reasons, but downstream systems may need to tell them apart.

In that case, the identity needs one more boundary:

```text
pod: multi-model-0
  container: qwen3-chat   -> spiffe://kleym.sonda.red/ns/llm-d/objective/qwen3-chat
  container: bge-embed    -> spiffe://kleym.sonda.red/ns/llm-d/objective/bge-embed
```

That is the `PerObjective` case. Kleym requires `containerName` here because the pool selector alone would match the whole pod set:

```yaml
apiVersion: inference.networking.k8s.io/v1
kind: InferenceObjective
metadata:
  name: qwen3-chat
  namespace: llm-d
spec:
  poolRef:
    name: qwen3
---
apiVersion: kleym.sonda.red/v1alpha1
kind: InferenceIdentityBinding
metadata:
  name: qwen3-chat
  namespace: llm-d
spec:
  poolRef:
    name: qwen3
  objectiveRef:
    name: qwen3-chat
  serviceAccountName: qwen3
  mode: PerObjective
  containerName: qwen3-chat
```

Expected selector shape:

```text
k8s:ns:llm-d
k8s:sa:qwen3
k8s:pod-label:app:qwen3
k8s:container-name:qwen3-chat
```

If two `PerObjective` bindings resolve to the same pool selector and the same container name, Kleym treats that as a collision. Different logical objective identities would land on the same workload slice, so the operator refuses to create ambiguous registrations.

## 05 Why not just write ClusterSPIFFEID YAML?

For a simple setup, writing the `ClusterSPIFFEID` by hand is fine.

If there is one namespace, one model server, one service account, one stable label set, and one person reviewing the manifests, direct `ClusterSPIFFEID` YAML is often enough.

The direct version looks something like this:

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: qwen3
spec:
  spiffeIDTemplate: spiffe://kleym.sonda.red/ns/llm-d/pool/qwen3
  podSelector:
    matchLabels:
      app: qwen3
  workloadSelectorTemplates:
    - k8s:ns:llm-d
    - k8s:sa:qwen3
    - k8s:pod-label:app:qwen3
```

Kleym's value is not YAML generation. The value is that it makes the identity boundary explicit and repeatable:

- the binding namespace is always part of the selector set
- the service account is always part of the selector set
- pool-derived selectors come from the referenced inference resource
- `PerObjective` identities require a container boundary
- overlapping objective identities are treated as a collision instead of quietly producing ambiguous registrations
- status conditions make invalid references, unsafe selectors, render failures, and collisions visible

I am still testing whether this boundary deserves a standalone controller or should stay as a pattern documented in the lab.

## 06 Reaching some limitations

Currently, Kleym registers expected identity and stops. It does not prove that identity has been issued, consumed, or enforced.

When a binding reaches `Ready=True`:

```text
InferenceIdentityBinding is reconciled
ClusterSPIFFEID is rendered
SPIRE registration intent exists
```

It does not mean:

```text
SVID issued
workload consumed the SVID
gateway enforced mTLS
request authorization happened
model artifact was verified
runtime state was attested
```

All of that still belongs to the cluster administrator and the surrounding platform. SPIRE Server and Agent must be installed correctly. The workload, sidecar, proxy, gateway, or application must actually consume the SVID. Downstream policy still has to validate the SPIFFE ID and decide what it allows. Envoy SDS, mTLS, external authorization, OPA, JWT-SVID exchange, route policy, and audit are downstream integration work, not things Kleym currently manages.

That may sound like a small scope, but I think it is the right one for the project today. Identity registration is already useful if it is deterministic, inspectable, and tied to inference intent. It becomes dangerous if the project starts implying more than that.

The future runtime question is still interesting:

> Does the workload that Kleym manages identity-wise appear to be using the expected model artifact and compute placement?

Host and runtime signals can help with inspection and drift detection: process, cgroup, device placement, file path, DRA allocation, GPU usage, or what vLLM reports. Reaching this point has mostly taught me that complex systems have many edges, and that there are many ways to be wrong.

## 07 What is ahead

The roadmap is mostly about making the current boundary stronger before adding anything larger.

First, the identity compiler itself needs to become more stable, and the proper identity format still needs more exploration.

Second, the project should be easier to try and operate without becoming a platform installer. Better install paths, clearer configuration, observability examples, other demos, etc. Installing SPIRE, model servers, gateways, Envoy, OPA, or policy resources is already quite a bit of work by itself.

Third, runtime evidence can stay on the research side until the static contract is stable. The line I want to preserve is:

```text
Kleym core:
  compile expected logical identity

Future runtime evidence:
  inspect and classify runtime state through an attestor-style extension

SPIRE:
  remain the authority that issues identity
```

That keeps the current project honest while leaving room for the more interesting runtime work.

Maybe Kleym becomes useful to someone else. Maybe it mostly teaches me where this abstraction breaks. Both are better than waiting for the perfect project.

Back to the code.
