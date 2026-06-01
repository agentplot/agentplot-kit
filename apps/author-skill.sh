# author-skill — LLM-author a UXC wrapper skill at service-author time.
#
# Usage: nix run .#author-skill -- [--verbose] [--spec PATH] [--host HOST]
#                                   [--link-name NAME] [--auth-type bearer|api_key]
#                                   <serviceName> <protocol>
#
# Expects (injected by the flake wrapper):
#   UXC_SKILL_CREATOR_DIR — store path of the vendored uxc-skill-creator skill
#
# Behavior (D11/D13/D14):
#   1. Resolve the spec/fixture content for <serviceName> <protocol>.
#   2. Spawn `claude --print` with the vendored uxc-skill-creator skill + the
#      capability context, authoring the four required files into
#      services/<serviceName>/skills/<protocol>/.
#   3. Run scripts/validate.sh; on failure, re-prompt with the errors, up to 3x.
#   4. On success, write a .source-spec-hash sidecar (sha256 of spec content).
#   Requires ANTHROPIC_API_KEY; exits early with a clear message if unset.

VERBOSE=0
SPEC=""
HOST=""
LINK_NAME=""
AUTH_TYPE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=1; shift ;;
    --spec) SPEC="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --link-name) LINK_NAME="$2"; shift 2 ;;
    --auth-type) AUTH_TYPE="$2"; shift 2 ;;
    --) shift; while [[ $# -gt 0 ]]; do POSITIONAL+=("$1"); shift; done ;;
    -*) echo "author-skill: unknown flag: $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -ne 2 ]]; then
  echo "usage: nix run .#author-skill -- [opts] <serviceName> <protocol>" >&2
  exit 2
fi

SERVICE="${POSITIONAL[0]}"
PROTOCOL="${POSITIONAL[1]}"

case "$PROTOCOL" in
  openapi|mcp) ;;
  *) echo "author-skill: protocol must be 'openapi' or 'mcp', got '$PROTOCOL'" >&2; exit 2 ;;
esac

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "author-skill: ANTHROPIC_API_KEY is not set." >&2
  echo "  Export an Anthropic API key before running this recipe, e.g.:" >&2
  echo "    export ANTHROPIC_API_KEY=sk-ant-..." >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "author-skill: 'claude' CLI not found on PATH." >&2
  echo "  Install it (npm i -g @anthropic-ai/claude-code) or add it to PATH." >&2
  exit 1
fi

OUT="services/${SERVICE}/skills/${PROTOCOL}"
SERVICE_DIR="services/${SERVICE}"

# Resolve spec / fixture content.
if [[ -z "$SPEC" ]]; then
  if [[ "$PROTOCOL" == "openapi" && -f "${SERVICE_DIR}/openapi.json" ]]; then
    SPEC="${SERVICE_DIR}/openapi.json"
  elif [[ "$PROTOCOL" == "mcp" && -f "${OUT}/fixtures/help-output.txt" ]]; then
    SPEC="${OUT}/fixtures/help-output.txt"
  else
    echo "author-skill: no spec found for ${SERVICE}/${PROTOCOL}." >&2
    if [[ "$PROTOCOL" == "openapi" ]]; then
      echo "  Commit ${SERVICE_DIR}/openapi.json or pass --spec PATH." >&2
    else
      echo "  Capture: uxc <host>/mcp -h > ${OUT}/fixtures/help-output.txt, or pass --spec PATH." >&2
    fi
    exit 1
  fi
fi

if [[ ! -f "$SPEC" ]]; then
  echo "author-skill: spec file '$SPEC' does not exist." >&2
  exit 1
fi

[[ -n "$LINK_NAME" ]] || LINK_NAME="${SERVICE}-${PROTOCOL}-cli"
[[ -n "$AUTH_TYPE" ]] || AUTH_TYPE="bearer"

mkdir -p "$OUT"

log() { if [[ "$VERBOSE" == "1" ]]; then echo "author-skill: $*" >&2; fi; }

build_prompt() {
  local extra="${1:-}"
  cat <<PROMPT
You are authoring a UXC wrapper skill. Use the uxc-skill-creator skill vendored at:
  ${UXC_SKILL_CREATOR_DIR}
Read its SKILL.md and references/ before writing.

Author a wrapper skill for:
  service:    ${SERVICE}
  protocol:   ${PROTOCOL}
  host:       ${HOST:-<derive from spec>}
  link name:  ${LINK_NAME}
  auth type:  ${AUTH_TYPE}

Write these four files into the directory ${OUT}/ (relative to the repo root),
following the uxc-skill-creator output contract and templates:
  ${OUT}/SKILL.md
  ${OUT}/agents/openai.yaml
  ${OUT}/references/usage-patterns.md
  ${OUT}/scripts/validate.sh

The fixed link command name MUST be '${LINK_NAME}'. The SKILL.md must be
link-first and help-first. scripts/validate.sh must enforce the hard rules and
exit non-zero on any violation.

The spec / fixture content is in the file: ${SPEC}
Ground all operation names and payload examples in that content.
${extra}
PROMPT
}

attempt=1
max_attempts=3
errors=""
while [[ $attempt -le $max_attempts ]]; do
  log "attempt ${attempt}/${max_attempts}"
  extra=""
  if [[ -n "$errors" ]]; then
    extra="A previous attempt failed validation with the following errors. Fix them:
${errors}"
  fi
  prompt="$(build_prompt "$extra")"

  if ! claude --print --permission-mode acceptEdits "$prompt"; then
    echo "author-skill: claude invocation failed on attempt ${attempt}" >&2
  fi

  if [[ -x "${OUT}/scripts/validate.sh" ]]; then
    if errors="$(bash "${OUT}/scripts/validate.sh" 2>&1)"; then
      log "validation passed"
      spec_hash="$(sha256sum "$SPEC" | cut -d' ' -f1)"
      printf '%s\n' "$spec_hash" > "${OUT}/.source-spec-hash"
      echo "author-skill: wrote ${OUT} (spec sha256=${spec_hash})"
      exit 0
    fi
    echo "author-skill: validation failed on attempt ${attempt}:" >&2
    echo "$errors" >&2
  else
    errors="scripts/validate.sh was not created or is not executable"
    echo "author-skill: ${errors}" >&2
  fi
  attempt=$((attempt + 1))
done

echo "author-skill: validation failed after ${max_attempts} attempts." >&2
echo "  Inspect ${OUT}/ and re-run (optionally with --verbose)." >&2
exit 1
