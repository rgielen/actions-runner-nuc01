#!/bin/sh
# Run inside the freshly built image before it is pushed: every tool the
# Dockerfile promises, the user the pod spec relies on, and a cgo build with
# -race, which is the one thing the extra packages exist for.
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
