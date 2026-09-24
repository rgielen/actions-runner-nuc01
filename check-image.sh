#!/bin/sh
# Run inside the freshly built image before it is pushed: every tool the
# Dockerfile promises, the user the pod spec relies on, and a cgo build with
# -race, which is the one thing the extra packages exist for. With
# CHECK_TARGET=docker also the Docker profile's additions.
set -eu

echo "== user"
id
[ "$(id -u)" = 1001 ] || { echo "expected uid 1001, got $(id -u)" >&2; exit 1; }
[ "$(id -g)" = 1001 ] || { echo "expected gid 1001, got $(id -g)" >&2; exit 1; }

echo "== tools"
for tool in gcc make zstd git jq curl; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
  printf '%-5s %s\n' "$tool" "$(command -v "$tool")"
done
gcc --version | head -1
zstd --version

echo "== runner"
cd /home/runner
# The base image sets ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT, which buries the one
# line of output under sixty lines of trace.
version=$(env -u ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT ./config.sh --version)
echo "$version"
if [ -n "${EXPECTED_RUNNER_VERSION:-}" ] && [ "$version" != "$EXPECTED_RUNNER_VERSION" ]; then
  echo "runner reports $version, the FROM line says $EXPECTED_RUNNER_VERSION" >&2
  exit 1
fi

echo "== cgo"
work=$(mktemp -d)
cat > "$work/main.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("cgo toolchain ok"); return 0; }
EOF
gcc -o "$work/main" "$work/main.c"
"$work/main"
rm -rf "$work"

[ "${CHECK_TARGET:-base}" = docker ] || exit 0

echo "== docker profile: CLI"
# The daemon runs in the pod's dind sidecar; the image only needs the client and
# buildx, both from upstream.
docker --version
docker buildx version

echo "== docker profile: GraalVM in the tool cache"
[ "${RUNNER_TOOL_CACHE:-}" = /opt/hostedtoolcache ] \
  || { echo "RUNNER_TOOL_CACHE is '${RUNNER_TOOL_CACHE:-}', expected /opt/hostedtoolcache" >&2; exit 1; }
# Exactly one version, with its .complete marker -- the two things setup-java's
# tool cache lookup needs (Java_GraalVM_jdk/<version>/x64 and x64.complete).
set -- "$RUNNER_TOOL_CACHE"/Java_GraalVM_jdk/*/x64.complete
[ "$#" = 1 ] && [ -f "$1" ] || { echo "expected exactly one Java_GraalVM_jdk/*/x64.complete, found: $*" >&2; exit 1; }
jdk="${1%.complete}"
echo "$jdk"
if [ -n "${EXPECTED_GRAALVM_DIR:-}" ] && [ "$(basename "$(dirname "$jdk")")" != "$EXPECTED_GRAALVM_DIR" ]; then
  echo "tool cache directory is $(basename "$(dirname "$jdk")"), expected $EXPECTED_GRAALVM_DIR" >&2
  exit 1
fi
"$jdk/bin/java" -version
# Writable by the runner user, so other setup-* actions can add their tools.
touch "$RUNNER_TOOL_CACHE/.writable" && rm "$RUNNER_TOOL_CACHE/.writable"
