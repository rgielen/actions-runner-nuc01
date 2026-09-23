# The runner image for the ARC scale sets on nuc01 (rgielen/k3s-nuc, issue #107).
#
# Upstream's image carries the runner, git, curl, jq and unzip, and nothing that
# compiles. The jobs moved onto nuc01 need four things more:
#
#   gcc, libc6-dev  go test -race needs cgo, and cgo needs a C compiler and the
#                   libc headers. Without them -race fails with "cgo: C compiler
#                   "gcc" not found", not with a test failure.
#   make            the hosted image has it, and Makefile-driven steps assume it.
#   zstd            actions/cache compresses with zstd when it finds the binary
#                   and falls back to gzip when it does not. The compression
#                   method is part of the cache version, so a gzip cache and a
#                   zstd cache under the same key never match: without zstd the
#                   two runner kinds would miss each other's caches both ways.
#
# Nothing else goes in here. Every tool added to this file is present in every
# job of every repository the scale sets serve, for as long as it stays; a
# language runtime belongs in the workflow's setup-* step, which pins it there.
#
# The tag of the FROM line is the runner version, and it is the version the
# image is published under. GitHub refuses jobs to runners more than 30 days
# behind the current release, and ARC registers runners with self-update off,
# so this line has to move within that window. Renovate moves it (renovate.json)
# and automerges the bump once the build below is green.
FROM ghcr.io/actions/actions-runner:2.337.0@sha256:e5496277be5d09bc968b3d64911b74e219ac4a3f2edce956a3ecf9271bea1ef4

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev make zstd \
    && rm -rf /var/lib/apt/lists/*

# Numeric on purpose. Upstream ends with `USER runner`, and a pod with
# runAsNonRoot refuses a non-numeric user because the kubelet cannot prove it is
# not root ("image has non-numeric user (runner), cannot verify user is
# non-root"). 1001:1001 is what `runner` resolves to in the base image.
USER 1001:1001
