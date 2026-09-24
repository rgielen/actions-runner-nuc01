# actions-runner-nuc01

Container images for self-hosted GitHub Actions runners, built on the upstream
[`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/pkgs/container/actions-runner)
image.

```
ghcr.io/rgielen/actions-runner-nuc01:<runner version>
ghcr.io/rgielen/actions-runner-nuc01-docker:<runner version>
```

Both are built from the same `FROM` line, as two targets of one
[Dockerfile](Dockerfile), so a runner bump moves both.

## What is in it

`actions-runner-nuc01` is the upstream image plus `gcc`, `libc6-dev`, `make` and
`zstd`: a C toolchain for cgo (`go test -race`), `make` for Makefile-driven
steps, and `zstd` so that `actions/cache` uses the same compression as on
GitHub-hosted runners. The user is numeric (`1001:1001`), so the image works
under `runAsNonRoot`.

`actions-runner-nuc01-docker` adds Oracle GraalVM 25 in the tool cache
(`RUNNER_TOOL_CACHE=/opt/hostedtoolcache`), where `actions/setup-java` finds it
instead of downloading it in every job. It is found without any network call for
an exact `java-version` (`'25.0.4'`); with a bare `'25'`, setup-java v6 resolves
against Oracle first. Like upstream, the image carries the Docker CLI and buildx
but no Docker daemon. GraalVM's version and checksum are moved by hand, since
there is no Renovate datasource for it.

## Tags and updates

The tag is the runner version from the `FROM` line. Renovate bumps that line
when a new runner release appears and merges it once the build is green. The
build on `main` checks the image, pushes `:<runner version>` and signs the
digest.

GitHub refuses jobs to runners more than 30 days behind the current release,
and ephemeral runners do not update themselves, so the tag has to be followed
within that window.

A monthly rebuild picks up Ubuntu security updates under the same tag. Pin tag
and digest to see it as a digest update.

## Verify

Images are signed keyless with cosign, bound to this repository's build
workflow:

```sh
cosign verify ghcr.io/rgielen/actions-runner-nuc01@<digest> \
  --certificate-identity-regexp '^https://github.com/rgielen/actions-runner-nuc01/\.github/workflows/build\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
