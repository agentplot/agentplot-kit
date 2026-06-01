# Contributor runbook: adding UXC support to a service

This runbook walks a contributor through adding (or refreshing) UXC support for a
clanService in the agentplot-kit ecosystem.

## Prerequisites

- agentplot-kit checkout
- `nix` (flake-enabled)
- `claude` CLI on PATH (or pulled in by the recipe)
- `ANTHROPIC_API_KEY` in environment

## 1. Declare the capability

Edit `services/<svc>/default.nix`. Add an `openapi` and/or `mcp` capability with
an explicit `auth` block:

```nix
capabilities = {
  secret = [
    { name = "admin-token"; mode = "op"; reference = "op://Personal/Foo/token"; }
  ];

  openapi = {
    host = client: client.domain;
    pathPrefix = "/api";
    schemaSource = { type = "static"; path = ./openapi.json; };
    auth = { secret = "admin-token"; type = "bearer"; };
  };
};
```

If using a static schema source, commit the OpenAPI JSON alongside (e.g.,
`services/<svc>/openapi.json`).

For MCP-only services with no formal spec, capture the help output as a fixture:

```bash
uxc <host>/mcp -h > services/<svc>/skills/mcp/fixtures/help-output.txt
```

## 2. Run the wrapper-skill recipe

```bash
nix run .#author-skill -- <serviceName> openapi
# and / or
nix run .#author-skill -- <serviceName> mcp
```

The recipe:
1. Extracts capability context via `nix eval`
2. Spawns `claude --print` headless with the vendored `uxc-skill-creator` skill
3. Authors `services/<svc>/skills/<protocol>/{SKILL.md, agents/openai.yaml, references/usage-patterns.md, scripts/validate.sh}`
4. Runs `scripts/validate.sh`; retries claude up to 3× on validation failure
5. Writes `.source-spec-hash` sidecar (SHA-256 of the spec / fixture)

Expected wall time: 30s–2min depending on op count.

## 3. Review the diff

LLM authoring is non-deterministic. Review the diff for:

- **Authentication section** — does the bootstrap path match how this service actually delivers credentials?
- **Capability map** — are the operation groupings sensible? Do high-risk ops appear in the right bucket?
- **Guardrails** — service-specific cautions present? Generic boilerplate isn't enough.
- **References** — usage-patterns.md has real example payloads, not placeholder text?

If the LLM missed something substantive, refine in-place (the file is committable as-is) or re-run the recipe with a more targeted prompt.

## 4. Commit

```bash
git add services/<svc>/skills/<protocol>/
git add services/<svc>/openapi.json    # if static spec changed
git commit -m "feat(<svc>): UXC <protocol> wrapper skill"
```

## 5. CI gates

`nix flake check` enforces:

- Every UXC-projected service ships a wrapper-skill directory (D15 eval-time check)
- `scripts/validate.sh` passes for every committed skill (D11 build-time gate)
- `.source-spec-hash` matches current spec content (D14 drift detection)

PR fails if any of these gate. Spec change without skill regen → CI tells you which skill needs the recipe re-run.

## Refreshing on spec change

When the upstream service's API changes, update the spec source (commit a new `openapi.json` or bump the URL fetch) and re-run the recipe. The spec-hash sidecar makes drift visible — CI fails until the skill is re-authored.

```bash
# update the spec
curl -fsSL https://<service>/openapi.json > services/<svc>/openapi.json

# regen the wrapper skill
nix run .#author-skill -- <svc> openapi

# review + commit
git add services/<svc>/openapi.json services/<svc>/skills/openapi/
git commit -m "chore(<svc>): refresh openapi spec + wrapper skill"
```

## Per-client linkName overrides

If an inventory needs a per-client link name (e.g., `paperless-personal-openapi-cli`
for the personal client and `paperless-work-openapi-cli` for work):

```nix
clients.personal = {
  uxc.enabled = true;
  uxc.openapi.linkName = "paperless-personal-openapi-cli";
};
```

`mkSkillContent`'s substitution table (extended in task 10.10) rewrites the canonical
`paperless-openapi-cli` references in the committed skill to the per-client name
during projection. The committed skill stays canonical; per-client names are derived.

## Bootstrap for the FIRST UXC service ever

The recipe needs `claude` and `uxc` available. For the very first service, install
them once on your dev machine:

```bash
brew install holon-run/tap/uxc      # or cargo install uxc, or nixpkgs
brew install anthropic/claude/claude  # or via npm: npm install -g @anthropic-ai/claude-code
```

Subsequent runs of the recipe just re-use the installed binaries.

## Troubleshooting

- **Recipe exits "validation failed after 3 attempts"** → inspect `services/<svc>/skills/<protocol>/SKILL.md` and `scripts/validate.sh` output. Re-run with verbose: `nix run .#author-skill -- --verbose <svc> <protocol>`.
- **`nix flake check` fails on spec-hash mismatch** → re-run the recipe to regenerate the skill against the current spec.
- **`mkClientTooling` eval error "no wrapper skill found for openapi"** → run the recipe; commit the resulting directory.
- **LLM authored a skill that references operations the spec doesn't have** → spec was probably truncated or stale. Refresh the spec, re-run.
