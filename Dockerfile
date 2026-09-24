# The runner images for the ARC scale sets on nuc01 (rgielen/k3s-nuc, issue #107).
# Two images from one FROM line, built as two targets of this file:
#
#   base    ghcr.io/rgielen/actions-runner-nuc01          profile nuc01 (gVisor, no Docker)
#   docker  ghcr.io/rgielen/actions-runner-nuc01-docker   profile nuc01-docker (Kata + dind)
#
# One FROM line for both on purpose: one Renovate bump rebuilds both, so neither can fall
# behind GitHub's 30-day runner version clock on its own.
#
# The tag of the FROM line is the runner version, and it is the version both images are
# published under. GitHub refuses jobs to runners more than 30 days behind the current
# release, and ARC registers runners with self-update off, so this line has to move
# within that window. Renovate moves it (renovate.json) and automerges the bump once the
# build is green.
FROM ghcr.io/actions/actions-runner:2.337.0@sha256:e5496277be5d09bc968b3d64911b74e219ac4a3f2edce956a3ecf9271bea1ef4 AS base

# Upstream's image carries the runner, git, curl, jq, unzip and the Docker CLI with
# buildx, and nothing that compiles. The jobs moved onto nuc01 need four things more:
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
# Nothing else goes into this stage. Every tool added here is present in every job of
# every repository the scale sets serve, for as long as it stays; a language runtime
# belongs in the workflow's setup-* step, which pins it there. The one exception is the
# docker stage below, and why it is one is written there.
USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev make zstd \
    && rm -rf /var/lib/apt/lists/*

# Numeric on purpose. Upstream ends with `USER runner`, and a pod with
# runAsNonRoot refuses a non-numeric user because the kubelet cannot prove it is
# not root ("image has non-numeric user (runner), cannot verify user is
# non-root"). 1001:1001 is what `runner` resolves to in the base image.
USER 1001:1001


FROM base AS docker

# GraalVM for the Docker profile, pre-installed in the tool cache.
#
# WHY A RUNTIME IN THE IMAGE, against the rule above. The profile's main job is the
# backend's `verify`, which runs actions/setup-java with GraalVM 25 in every job. On a
# hosted runner that JDK comes out of the Actions cache at 100+ MB/s; on nuc01 every job
# would pull 380 MB over the home line (11.6 MB/s). The Docker profile serves a handful
# of Java jobs and nothing else, so here the trade goes the other way. Decided with O7
# in rgielen/k3s-nuc#107; design record: docs/actions-runner/docker-profile.adoc there.
#
# WHERE, and why not under the work directory. The runner puts its tool cache in
# _work/_tool unless RUNNER_TOOL_CACHE says otherwise, and in the scale set _work is an
# emptyDir that hides whatever the image had there. /opt/hostedtoolcache is where
# GitHub's own images keep it. Owned by 1001, so other setup-* actions can still add
# tools in a job.
#
# THE DIRECTORY NAME IS WHAT setup-java LOOKS FOR, and it is derived, not typed:
# Java_GraalVM_jdk/<version>/x64 plus an empty x64.complete. setup-java names a GraalVM
# installation after JAVA_RUNTIME_VERSION in the JDK's `release` file ("25.0.4+7-LTS-
# jvmci-b01" -> "25.0.4+7"), and the tool cache writes the "+" as "-". Read back, the
# directory is found for an exact `java-version: '25.0.4'`. For a bare '25', setup-java
# v6 asks Oracle first and uses the tool cache only once its resolution cache maps the
# download to this version (graalvm/installer.ts, requiresRemoteResolution) -- the
# design record has the details.
#
# No Renovate datasource exists for Oracle GraalVM (setup-java's own comment: no
# endpoint to list releases). Version and checksum are moved by hand, and Oracle's
# `.sha256` beside the archive is what the checksum below was checked against
# (2026-09-24). Oracle GraalVM is under the GFTC, which permits redistributing the
# unmodified program free of charge -- which a public image is.
ARG GRAALVM_VERSION=25.0.4
ARG GRAALVM_SHA256=76007c309f821aaf435bce63162ea0395587fc77350801c81643fe7feea37276

USER root

ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache

RUN set -eu; \
    major="${GRAALVM_VERSION%%.*}"; \
    curl -fsSL -o /tmp/graalvm.tar.gz \
      "https://download.oracle.com/graalvm/${major}/archive/graalvm-jdk-${GRAALVM_VERSION}_linux-x64_bin.tar.gz"; \
    echo "${GRAALVM_SHA256}  /tmp/graalvm.tar.gz" | sha256sum -c -; \
    mkdir /tmp/graalvm; \
    tar -xzf /tmp/graalvm.tar.gz -C /tmp/graalvm --strip-components=1; \
    rm /tmp/graalvm.tar.gz; \
    runtime=$(sed -n 's/^JAVA_RUNTIME_VERSION="\([0-9.]*+[0-9.]*\).*"$/\1/p' /tmp/graalvm/release); \
    [ -n "$runtime" ] || { echo "no JAVA_RUNTIME_VERSION in the release file" >&2; exit 1; }; \
    dir="${RUNNER_TOOL_CACHE}/Java_GraalVM_jdk/$(echo "$runtime" | tr '+' '-')"; \
    mkdir -p "$dir"; \
    mv /tmp/graalvm "$dir/x64"; \
    touch "$dir/x64.complete"; \
    chown -R 1001:1001 "$RUNNER_TOOL_CACHE"

USER 1001:1001
