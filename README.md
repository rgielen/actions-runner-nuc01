# actions-runner-nuc01

The runner image for the self-hosted GitHub Actions runners on `nuc01`, the
single-node k3s cluster in [rgielen/k3s-nuc](https://github.com/rgielen/k3s-nuc)
(private). They run as [Actions Runner Controller](https://github.com/actions/actions-runner-controller)
scale sets, one ephemeral pod per job, under gVisor, without Docker and without
access to the cluster or the LAN.

```
ghcr.io/rgielen/actions-runner-nuc01:<runner version>          profile nuc01 (gVisor, no Docker)
ghcr.io/rgielen/actions-runner-nuc01-docker:<runner version>   profile nuc01-docker (Kata + dind)
```

Both come from the same `FROM` line as two targets of one [Dockerfile](Dockerfile),
so one runner bump moves both.

## What is in it

[`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/pkgs/container/actions-runner)
plus `gcc`, `libc6-dev`, `make` and `zstd`. The reasons are in the
[Dockerfile](Dockerfile). The user is numeric (`1001:1001`), because the pods run
with `runAsNonRoot`.

`sudo` is still in the base image and does not work: the pods run with
`allowPrivilegeEscalation: false`. A job that needs a package installs it
without root, or gets it into this image by pull request.

`actions-runner-nuc01-docker` adds Oracle GraalVM 25 in the tool cache
(`RUNNER_TOOL_CACHE=/opt/hostedtoolcache`), where `actions/setup-java` finds it
instead of downloading 380 MB per job over nuc01's home line. It is found without
any network call for an exact `java-version` (`'25.0.4'`); with a bare `'25'`,
setup-java v6 resolves against Oracle first (checked 2026-09-24 against v6.0.1).
The Docker daemon itself is not in the image: it runs as a `docker:dind` sidecar
of the runner pod, inside a Kata micro-VM. GraalVM's version and checksum are
moved by hand -- there is no Renovate datasource for it.

## How it moves

1. Renovate bumps the `FROM` line when a new runner release appears and merges it
   once the build is green (`renovate.json`).
2. The build on `main` pushes `:<runner version>` and signs the digest with
   cosign (keyless, bound to this repository's workflow).
3. Renovate in k3s-nuc sees the new tag and opens the pull request that moves
   the scale sets.

The window is 30 days: GitHub refuses jobs to runners more than 30 days behind
the current release, and ARC does not update them in place.

A monthly rebuild picks up Ubuntu security updates under the same tag, and
reaches k3s-nuc as a digest update.

## Verify

```sh
cosign verify ghcr.io/rgielen/actions-runner-nuc01@<digest> \
  --certificate-identity-regexp '^https://github.com/rgielen/actions-runner-nuc01/\.github/workflows/build\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
