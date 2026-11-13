#!/bin/sh
# Run the same commands on the VM (ray run) and on the native binary (./raysolve) and
# compare their output, timings removed. Exit 1 on any difference.
set -u
cd "$(dirname "$0")/.."
[ -x ./raysolve ] || { echo "build first: make build" >&2; exit 2; }
I="--index fixtures/ecosystem"
strip() { sed -E 's/[0-9]+\.[0-9]+ ms//g; s/"micros":[0-9]+//g'; }
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
run_case() {
  # stdout and stderr compared one after the other: when piped, the native binary
  # buffers stdout while the VM writes each line at once, so a merged stream interleaves
  # differently
  vm=$( { ray run . "$@" 2>"$tmp/err"; echo "exit $?"; } | strip; strip < "$tmp/err")
  nat=$( { ./raysolve "$@" 2>"$tmp/err"; echo "exit $?"; } | strip; strip < "$tmp/err")
  if [ "$vm" = "$nat" ]; then
    echo "same  $*"
  else
    echo "DIFF  $*"
    printf '%s\n' "$vm" > "$tmp/vm"; printf '%s\n' "$nat" > "$tmp/nat"
    diff "$tmp/vm" "$tmp/nat" | head -20
    fail=1
  fi
}
for p in app conflict deep pre missing; do
  run_case resolve fixtures/projects/$p.toml $I --tree
done
run_case resolve fixtures/projects/app.toml --json --index fixtures/ecosystem.json
run_case resolve fixtures/projects/conflict.toml --yanked $I --index fixtures/ecosystem.json
run_case why net fixtures/projects/app.toml $I
run_case why yaml fixtures/projects/app.toml $I
run_case outdated fixtures/projects/app.toml $I
run_case outdated fixtures/projects/deep.toml $I
run_case bench --packages 200 --rounds 1
run_case resolve nope.toml $I
run_case frobnicate
exit $fail
