# mkUxcChecks — build derivations that gate committed UXC wrapper skills.
#
# Both checks scan `services/*/skills/*/` under `src`:
#   wrapper-skills — run each skill's scripts/validate.sh; fail on any non-zero.
#   spec-hash      — recompute sha256 of each skill's spec (openapi.json or
#                    fixtures/help-output.txt) and compare to .source-spec-hash.
#
# Reusable downstream: a repo that owns services calls this with its own `src`
# and wires the results into `checks.<system>`. With no services present the
# checks pass trivially (and say so — no silent cap).
#
# Note: url-sourced specs have no local file; offline they are skipped with a
# printed note (CI may re-fetch + re-hash with network enabled).
{ pkgs, src }:
let
  inherit (pkgs) runCommand ripgrep coreutils bash;
in
{
  wrapper-skills = runCommand "uxc-wrapper-skills-check"
    { nativeBuildInputs = [ ripgrep coreutils bash ]; }
    ''
      set -euo pipefail
      shopt -s nullglob
      cd ${src}
      count=0
      for v in services/*/skills/*/scripts/validate.sh; do
        echo "[uxc-checks] running $v"
        bash "$v"
        count=$((count + 1))
      done
      echo "[uxc-checks] validated $count wrapper skill(s)"
      touch $out
    '';

  spec-hash = runCommand "uxc-spec-hash-check"
    { nativeBuildInputs = [ coreutils ]; }
    ''
      set -euo pipefail
      shopt -s nullglob
      cd ${src}
      count=0
      skipped=0
      for h in services/*/skills/*/.source-spec-hash; do
        dir="$(dirname "$h")"
        proto="$(basename "$dir")"
        svc="$(basename "$(dirname "$(dirname "$dir")")")"
        spec=""
        if [ "$proto" = "openapi" ] && [ -f "services/$svc/openapi.json" ]; then
          spec="services/$svc/openapi.json"
        elif [ -f "$dir/fixtures/help-output.txt" ]; then
          spec="$dir/fixtures/help-output.txt"
        fi
        if [ -z "$spec" ]; then
          echo "[uxc-checks] $svc/$proto: no local spec (url-sourced?) — skipping offline hash check"
          skipped=$((skipped + 1))
          continue
        fi
        want="$(cat "$h")"
        got="$(sha256sum "$spec" | cut -d' ' -f1)"
        if [ "$want" != "$got" ]; then
          echo "[uxc-checks] spec hash mismatch for $svc/$proto" >&2
          echo "  expected $want but $spec hashes to $got" >&2
          echo "  re-run: nix run .#author-skill -- $svc $proto" >&2
          exit 1
        fi
        count=$((count + 1))
      done
      echo "[uxc-checks] verified $count spec hash(es); skipped $skipped url-sourced"
      touch $out
    '';
}
