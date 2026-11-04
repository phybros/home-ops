# 💾 Home Ops

## ✨ Features

A Kubernetes cluster deployed with [Talos Linux](https://github.com/siderolabs/talos) and an opinionated implementation of [Flux](https://github.com/fluxcd/flux2) using [GitHub](https://github.com/) as the Git provider, [sops](https://github.com/getsops/sops) to manage secrets and [cloudflared](https://github.com/cloudflare/cloudflared) to access applications external to your local network.

- **Included components:** [flux](https://github.com/fluxcd/flux2), [cilium](https://github.com/cilium/cilium), [cert-manager](https://github.com/cert-manager/cert-manager), [spegel](https://github.com/spegel-org/spegel), [reloader](https://github.com/stakater/Reloader), [external-dns](https://github.com/kubernetes-sigs/external-dns) and [cloudflared](https://github.com/cloudflare/cloudflared).

I also use:

- `rook-ceph` for distributed storage
- `volsync` to keep everything backed up
- `kube-prometheus-stack` to gather metrics from around the cluster
- `grafana` to visualize all the metrics from prometheus

**Other features include:**

- Dev env managed w/ [mise](https://mise.jdx.dev/)
- Workflow automation w/ [GitHub Actions](https://github.com/features/actions)
- Dependency automation w/ [Renovate](https://www.mend.io/renovate)
- Flux `HelmRelease` and `Kustomization` diffs w/ [flux-local](https://github.com/allenporter/flux-local)

## External DNS updates

The chart URL and version in `kubernetes/apps/network/cloudflare-dns/app/helmrelease.yaml`
are shared by Flux and bootstrap. Bootstrap installs the CRDs bundled with that chart;
Flux updates them on chart upgrades using `install.crds: CreateReplace` and
`upgrade.crds: CreateReplace`. Merge Renovate updates to the chart's `OCIRepository`
tag to update external-dns and its bundled CRDs together. There is no separate
external-dns CRD release URL to update in the bootstrap script.

## 🤝 Thanks

Thanks to all the people who donate their time to the [Home Operations](https://discord.gg/home-operations) Discord community. A lot of inspiration for my cluster comes from the people that have shared their clusters using the [k8s-at-home](https://github.com/topics/k8s-at-home) GitHub topic. Be sure to check out the awesome [Kubesearch](http://kubesearch.dev) tool for ideas on how to deploy applications or get ideas on what you can deploy.

