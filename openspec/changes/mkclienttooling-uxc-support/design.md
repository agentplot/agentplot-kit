## Context

`mkClientTooling` takes a `capabilities` declaration and produces a complete clanService client role. Today's capabilities:

- `skills`: file paths consumed by `programs.claude-code.skills`, `programs.agent-skills`, `programs.openclaw.skills`, `programs.agent-deck.skillSources`
- `mcp`: `{ type, urlTemplate, extraConfig? }` consumed by `programs.claude-code.mcpServers` and `programs.agent-deck.mcps`
- `cli`: `{ package, wrapperName?, envVars? }` wrapped as a `writeShellApplication` on the client's HM profile
- `secret`: list of `{ name, mode, ... }` with modes `prompted`, `generated`, `shared`; secrets delivered as files via clan vars
- `plugins`, `extraPackages`: miscellaneous

Per-client consumer toggles live under `clients.<name>.<consumer>.<feature>.enabled`: e.g., `clients.personal.claude-code.mcp.enabled = true`.

[UXC](https://github.com/holon-run/uxc) is a unified CLI over MCP + OpenAPI + GraphQL + gRPC + JSON-RPC. Its on-disk state:

- `~/.uxc/credentials.json`: credential definitions keyed by id, each with `auth_type` (`bearer` | `api_key`) and a `secret_source` of kind `literal` | `env` | `op`. Multi-field credentials add a `fields` attrset.
- `~/.uxc/auth_bindings.json`: endpoint→credential bindings ordered by `priority`, keyed on `scheme + host + path_prefix`
- Link shims: POSIX shell scripts on `$PATH` that exec `uxc <host> "$@"`, optionally with `--schema-url` for local OpenAPI specs

UXC's JSON files are pure declarations — no timestamps, IDs, hashes, or machine-specific state. `op://` references are resolved at call time by shelling out to the `op` CLI (which supports `OP_SERVICE_ACCOUNT_TOKEN` for headless contexts). This makes the files ideal for Nix-managed projection.

## Goals / Non-Goals

**Goals:**
- Let services declare OpenAPI endpoints in `mkClientTooling` and have them project into UXC's JSON + link shims
- Let services declare 1Password-backed credentials via an `op` secret mode that UXC resolves at call time
- Preserve backward compatibility: existing `mcp`, `secret`, `cli` capabilities unchanged; `claude-code.mcp.enabled` path continues working
- Keep UXC projection and Claude Code projection independent — services can target both, either, or neither
- Match UXC skill-creator naming convention (`<serviceName>-<protocol>-cli`) for link shims so wrapper skills can assume link names

**Non-Goals:**
- Replacing Claude Code's direct MCP registration (v1 keeps both paths — but a UXC-projected MCP can also be wired into claude-code's `mcpServers` as a `uxc` stdio command instead of `mcp-remote`)
- Implementing GraphQL/gRPC/JSON-RPC projections in v1 (deferred until there's a real service that uses them)
- Installing the `uxc` binary itself (out of scope for `agentplot-kit`; downstream flakes handle installation)
- Projecting non-`op` secret modes to UXC in v1 (UXC can read env vars but using `--secret-env` requires the token in process env, which defeats UXC's secret-hygiene benefit; add support if there's demand)
- Multi-field UXC credentials (e.g., api_key + signing_secret on one credential) — v1 maps one secret to one credential; multi-field can be added when a real service needs it

## Decisions

### D1: Protocol-specific capabilities instead of unified `endpoints` list

Add `openapi` as a peer to the existing `mcp` capability rather than introducing a unified `endpoints = [ ... ]` list.

```nix
capabilities = {
  mcp = {                                                            # existing, with new auth block
    type = "http";
    urlTemplate = client: "https://${client.domain}/mcp";
    auth = { secret = "admin-token"; type = "bearer"; };
  };
  openapi = {                                                        # new
    host = client: client.domain;                                    # fn-of-clientSettings (or string)
    pathPrefix = "/api";
    schemaSource = { type = "static"; path = ./openapi.json; };
    auth = { secret = "admin-token"; type = "bearer"; };
  };
};
```

**Rationale**: Each protocol has distinct required fields (MCP has `type`/`urlTemplate`; OpenAPI has `schemaSource`/`pathPrefix`; GraphQL has introspection URL; gRPC has reflection endpoint). A unified list would either duplicate all fields on every entry (ugly) or use an enum-typed union (Nix modules handle this poorly). Peer capabilities match how `mcp` already works, keep each protocol's shape tight, and let services opt into exactly the surfaces they expose.

**Alternative considered**: `endpoints = [{ protocol; ...}, ...]` with per-protocol fields as optional. Rejected — obscures required fields per protocol and complicates the projection logic.

### D2: New `op` secret mode references a 1Password path

Add `mode = "op"` to the secret capability. An `op` secret declares a `reference = "op://Vault/Item/field"` instead of building a vars generator.

```nix
secret = [
  { name = "atomic-token"; mode = "op"; reference = "op://Personal/Atomic/token"; }
];
```

`op` secrets:
- Create no clan vars generator
- Have no `secretPath` (no file on disk)
- Project to UXC credentials as `{ kind = "op"; reference = "op://..."; }`
- Are unavailable to `cli.envVars` and `mcp.extraConfig` callbacks (those expect `secretPaths.<name>` — a file path)

**Rationale**: UXC needs `op://` references to be written into `credentials.json` verbatim. Introducing the reference as a secret mode (vs. a separate top-level attribute) keeps all secret declarations in one list and lets the existing `secrets` normalization handle it. The tradeoff — `op` secrets can't flow to CLI envVars or MCP configs — is acceptable because those consumers already have better secret-delivery mechanisms (clan-managed files).

**Alternative considered**: A separate `opSecrets` capability. Rejected because it duplicates the secret-normalization plumbing.

### D3: OpenAPI spec distribution via `schemaSource` with three shapes

Services declare how UXC should locate the OpenAPI spec:

```nix
openapi.schemaSource = { type = "static"; path = ./openapi.json; };           # committed to repo
openapi.schemaSource = { type = "derivation"; drv = pkgs.fetchurl { ... }; }; # built from flake inputs
openapi.schemaSource = { type = "url"; url = "https://..."; };                # runtime fetch (requires --schema-url URL support)
```

The projection logic resolves each to a string usable in UXC's `--schema-url` flag:
- `static`: copies the file into the Nix store, link shim references `file:///nix/store/...-openapi.json`
- `derivation`: uses the derivation's out path directly
- `url`: link shim references the URL verbatim

**Rationale**: Atomic's OpenAPI spec is not served publicly (its `/api/openapi.json` returns 401). Different services will have different distribution strategies. An explicit typed `schemaSource` keeps the options clear without overfitting to one pattern.

**Alternative considered**: A single string path that the module interprets by prefix (`./`, `/nix/store/`, `https://`). Rejected — ambiguous and error-prone.

### D4: UXC link name convention `<serviceName>-<protocol>-cli`

Link shims are named `<serviceName>-<protocol>-cli` by default: `atomic-openapi-cli`, `atomic-mcp-cli`, `linkding-openapi-cli`. Overridable via `openapi.linkName` if needed.

**Rationale**: UXC's skill-creator rubric (upstream `skills/uxc-skill-creator/SKILL.md`) prescribes this pattern. Wrapper skills assume the link name. Matching the upstream convention keeps agentplot-kit services compatible with UXC's skill ecosystem without special-casing.

### D5: Per-client `uxc.enabled` consumer toggle

Mirrors existing `claude-code.mcp.enabled`:

```nix
clients.personal.uxc.enabled = true;
clients.personal.claude-code.mcp.enabled = true;  # coexists
```

When `uxc.enabled = true` on a client, the projection emits credentials, bindings, and link shims for that client's instance. When false, no UXC artifacts are written for that client even if the service declares endpoints.

**Rationale**: Matches the existing consumer-toggle pattern. Lets operators roll out UXC per-client without forcing an all-or-nothing migration.

### D6: Credential and binding keys namespaced by service + secret + protocol

Naming convention:
- Credential id: `agentplot-<serviceName>-<clientName>-<secretName>` — matches the vars-generator naming, supports multi-secret services
- Binding id: `agentplot-<serviceName>-<clientName>-<protocol>` — one binding per (service, client, protocol) tuple

```json
{ "credentials": {
    "agentplot-atomic-personal-admin-token": { "auth_type": "bearer", "secret_source": {...} }
  },
  "bindings": [
    { "id": "agentplot-atomic-personal-mcp",     "host": "...", "credential": "agentplot-atomic-personal-admin-token", ... },
    { "id": "agentplot-atomic-personal-openapi", "host": "...", "credential": "agentplot-atomic-personal-admin-token", ... }
  ]
}
```

**Rationale**: Keys must be unique across all (service, client, secret, protocol) tuples. Including `secretName` in the credential id lets a service declare two credentials (e.g., one `op`, one `prompted`-fs alongside) without collision. Including `protocol` in the binding id lets one credential bind to multiple endpoints (atomic's admin-token serves both MCP and OpenAPI). Prefix `agentplot-` makes it obvious which entries are Nix-managed (vs. hand-written by the user).

### D7: UXC HM module owns `~/.uxc/*.json` files declaratively

The new `modules/home-manager/uxc.nix` module collects credentials/bindings/links from all enabled services and writes:
- `~/.uxc/credentials.json` via `home.file` with `mode = "0600"`
- `~/.uxc/auth_bindings.json` via `home.file` with `mode = "0600"`
- Link shims via `home.packages` (a `pkgs.writeShellApplication` per link, installed into the HM profile's `bin/`)

UXC's daemon cache at `~/.uxc/cache/` and daemon socket files are runtime state — the module does not manage them.

**Rationale**: Declarative ownership is the whole point. Writing the files via `home.file` keeps them pure and prevents drift from imperative `uxc auth credential set` calls. Users who need one-off credentials outside Nix can use a separate credentials file via `UXC_HOME` override.

### D8: MCP-via-UXC included in v1 (upstream bug fixed)

UXC's streamable-HTTP MCP transport now sends `notifications/initialized` after `initialize` (fix landed in upstream UXC and verified against atomic's `rmcp` server). Therefore the `mcp` capability projects to UXC alongside `openapi`:

- When `uxc.enabled = true` on a client, an MCP capability emits a UXC binding (`scheme + host + path_prefix`) and a `<service>-mcp-cli` link shim.
- When `claude-code.mcp.enabled = true` on the same client, the `mcpServers.<name>` entry can be wired as a stdio command pointing at `uxc` instead of hand-rolled `mcp-remote` wrappers — no on-disk token needed because UXC resolves `op://` at call time.
- A client may enable both, either, or neither; the two projections are independent.

This is the resolution the original D8 deferral planned for. The trade-off (op-mode incompatibility with file-token claude-code MCP wrappers) only matters if a client opts out of UXC; in that case the service must declare a non-`op` secret to satisfy the claude-code direct path. Mockups (`mockups/atomic.example.nix`) show both projections coexisting on one client.

### D9: Endpoint-to-credential coupling is explicit via per-endpoint `auth` block

Each endpoint capability (`mcp`, `openapi`, …) declares its own `auth = { secret; type; }`:

```nix
mcp     = { ...; auth = { secret = "admin-token"; type = "bearer"; }; };
openapi = { ...; auth = { secret = "admin-token"; type = "bearer"; }; };
```

`auth.secret` is a string naming an entry in the service's `secret` capability. `auth.type` is `"bearer"` or `"api_key"` (UXC's two `auth_type` values).

Projection rules:
- Each *referenced* secret becomes a UXC credential; unreferenced secrets do not (they may exist purely for `cli.envVars` consumption).
- The credential's `secret_source` is determined by the secret's `mode`: `op` → `{ kind = "op"; reference = ...; }`. Non-`op` modes referenced by an `auth` block are an evaluation error in v1 (UXC doesn't have a clean projection for file-mode secrets without exporting them to env).
- Each endpoint's binding sets `credential = agentplot-<service>-<client>-<secretName>`.
- Two endpoints may reference the same secret → they share one credential, two bindings.

**Rationale**: The original loose coupling ("any `op`-mode secret implicitly becomes the credential and all endpoints inherit it") fell apart for services with multiple secrets, services where some endpoints use auth and others don't, and services whose claude-code MCP wrapper needed a file-mode secret in addition to the UXC `op` credential. Making the binding explicit at the endpoint declaration site keeps each endpoint's auth shape inspectable in one place and supports the multi-secret/multi-credential cases that real services hit. Cost is a few extra characters per endpoint; benefit is no more guessing about which secret feeds which surface.

**Alternative considered**: A top-level `credentials = { main = { secret; type; }; }` map plus `mcp.credential = "main"`. Rejected — adds a third name to track (secret name, credential name, endpoint name) when `auth.secret` directly is enough. Promote to a top-level map only if multi-field credentials become a real need.

### D10: `host` and `urlTemplate` accept string OR fn-of-clientSettings

For symmetry between `mcp.urlTemplate` (already a function) and `openapi.host` (originally proposed as a static string), both fields accept either form:

```nix
openapi.host = "atomic.swancloud.net";              # static — single-tenant service
openapi.host = client: client.domain;               # per-client domain
schemaSource = { type = "url"; url = client: "${client.base_url}/api/schema/?format=openapi"; };
```

The projection logic resolves functions against each client's settings before writing to UXC JSON. This matters for paperless and other services where a single service definition serves clients pointed at different deployments.

**Rationale**: Without this, services with per-client base URLs (paperless) would have to push the URL into a separate option and bypass `openapi.host`. The string-or-fn pattern matches `urlTemplate` and keeps the capability declarations parallel.

### D11: Wrapper skills are LLM-authored at service-author time, committed, and validated

UXC wrapper skills (`SKILL.md` + `agents/openai.yaml` + `references/usage-patterns.md` + `scripts/validate.sh`) carry substantial service-specific judgment — capability map, write/high-risk classification, auth-bootstrap specifics, real op IDs, provider-specific guardrails. Real examples (`github-openapi-skill/SKILL.md`, `qmd-mcp-skill/SKILL.md`) show 70–80% of the body is content that mechanical templating can't produce.

The right shape: **LLM does the hard work at service-author time, output is committed, downstream consumers get static validated artifacts.**

Pipeline:

```
contributor: nix run .#author-skill -- <serviceName> <protocol>
   ├─ extract { host, linkName, authType, schemaSource } from service def
   ├─ load vendored uxc-skill-creator skill
   ├─ spawn `claude --print` headless with capability ctx + spec content
   ├─ claude authors SKILL.md tree to services/<svc>/skills/<protocol>/
   ├─ run scripts/validate.sh (gates output structure)
   │     fail → re-prompt claude with errors, retry up to N=3
   ├─ pass → leave skill committable, write spec-hash sidecar
   └─ contributor reviews diff, refines if needed, commits
```

Phases and actors:

| Phase | Actor | Frequency | Behavior |
|-------|-------|-----------|----------|
| service-add | contributor invokes recipe | once per service or on spec bump | LLM authors; output committed |
| `nix flake check` | CI | every PR | runs each skill's `scripts/validate.sh`; gates merge |
| build / HM activation | end user | every rebuild | already-committed skill plumbed through existing `capabilities.skills` |
| runtime | end-user agent | every call | uses `<link> -h` + skill guidance |

**Why not at build/activation time** (considered and rejected):
- Nix purity: LLM is impure (network + non-deterministic). Fixed-output-derivation hashes would thrash on every regen.
- Credentials: end users don't have `ANTHROPIC_API_KEY`. Build/activation can't run claude on their machine.
- Cost: every consumer paying to regenerate the same artifact is wasteful when it's committable once.
- Review: Guardrails section benefits from contributor eyeball before shipping to others.

So the LLM runs at the **edge** of the lifecycle (service-author time), output is **committed** (becomes source of truth), downstream is **static** (build/activation/runtime are deterministic).

**Rationale**: This is the only architecture that satisfies all three constraints — the LLM does the substantive authoring (mechanical templating produces husks), the output is reliable (validate.sh + retry loop + CI gate), and consumers get a pure deterministic pipeline (no LLM at build or runtime).

### D12: Vendor `uxc-skill-creator` under `agentplot-kit/skills/`

The recipe loads the upstream `uxc-skill-creator` skill verbatim. Vendoring it into agentplot-kit means contributors don't need to manually install upstream's skill before invoking the recipe. The vendored copy is version-pinned via a flake input (or git submodule), and CI bumps it when upstream releases.

**Rationale**: One less prerequisite for contributors. Version pinning means recipe output is reproducible against a specific upstream skill version. Drift surfaces as a flake-input bump PR with diff visibility.

### D13: `apps.author-skill` flake recipe wraps the LLM invocation

Expose the recipe as a flake app: `nix run .#author-skill -- <serviceName> <protocol>`. The recipe:

1. Reads service capability declaration via `nix eval` to extract `{ host, linkName, authType, schemaSource }`
2. Resolves `schemaSource` to a local file or URL the LLM can read
3. Constructs the prompt: capability context + path to load vendored skill + output directory
4. Invokes `claude --print` headless (or equivalent SDK call) with `ANTHROPIC_API_KEY` from env
5. Captures output to `services/<svc>/skills/<protocol>/`
6. Runs `scripts/validate.sh` from the output
7. On failure: re-prompt with validation errors, retry up to 3×
8. On success: write `.source-spec-hash` sidecar, exit 0
9. On exhausted retries: leave artifacts in place, exit 1, dump errors

The recipe is a shell script wrapped as a `pkgs.writeShellApplication` exposed via `flake.apps.<system>.author-skill`. Dependencies (`claude`, `nix`, `jq`, `sha256sum`) are baked in via `runtimeInputs`.

**Rationale**: A flake recipe is the right granularity — invocable from any contributor's editor, deterministic in its dependencies (Nix manages them), reproducible in its inputs (capability declaration + vendored skill version + spec content).

### D14: Spec-hash sidecar for drift detection

Each committed skill ships `.source-spec-hash` recording the SHA-256 of the OpenAPI spec (or MCP help-output fixture) used at last regen. `nix flake check` includes a check that re-hashes the current spec and fails if it differs without a corresponding skill regen.

```
services/atomic/
  openapi.json
  skills/openapi/
    SKILL.md
    .source-spec-hash    ← matches sha256(openapi.json) at last regen
    ...
```

**Rationale**: The skill's content references real op IDs and shapes from the spec. When the spec changes, the skill MUST be re-authored — otherwise documented ops drift out of sync with the actual API. The hash sidecar makes drift visible in CI without requiring contributors to remember.

For URL-sourced specs: hash the fetched content at regen time; CI re-fetches and re-hashes (network dep in CI is acceptable; flag with a comment).

For MCP services with no formal spec: snapshot `uxc <host> -h` output as a fixture file (committed alongside the skill); hash that fixture.

### D15: `mkClientTooling` evaluation fails if a UXC-projecting service ships no wrapper skill

When `capabilities.uxc-projectable` (i.e., `mcp` or `openapi`) is declared, `mkClientTooling` requires the service to provide a wrapper-skill directory at a conventional location (e.g., `services/<svc>/skills/<protocol>/`) or via an explicit `endpoint.skill = ./path` capability field. Eval fails with a clear error pointing at the recipe:

```
error: service 'atomic' declares an `openapi` capability but ships no wrapper skill.
       Run: nix run .#author-skill -- atomic openapi
       Or set: capabilities.openapi.skill = ./skills/openapi
```

**Rationale**: Without this, a contributor could merge a service with UXC support but no skill — the link binary would land on user PATH with no agent guidance. Forcing the skill at eval time prevents that footgun. The escape hatch (`capabilities.openapi.skill = false`) is intentionally absent in v1 — the project stance is that every UXC-projected endpoint has a wrapper skill.

## Risks / Trade-offs

- **[Risk] UXC JSON schema changes** → UXC is pre-1.0 (v0.15 as of writing). The JSON shapes for credentials/bindings may change. **Mitigation**: pin UXC version in downstream flakes; monitor upstream CHANGELOG; add a version check in the HM module that warns if the installed `uxc --version` doesn't match the expected range.
- **[Risk] `op://` references fail at call time, not eval time** → A typo in the 1Password path fails the first `uxc` call, not the Nix build. **Mitigation**: Document this clearly; add a `uxc auth credential show <id>` probe to the skill-generated `scripts/validate.sh` so users can check references before first use.
- **[Risk] Static `schemaSource` specs go stale** → If a service's OpenAPI changes between commits, users running older versions see outdated tool definitions. **Mitigation**: Document the tradeoff; recommend `type = "url"` for services that serve specs publicly, `type = "derivation"` with a version pin for services that don't.
- **[Trade-off] `op` mode isn't usable with CLI envVars/MCP-direct extraConfig** → A service that wants both UXC-via-`op` AND a legacy CLI wrapper or claude-code direct MCP needs two secret declarations (one `op` for UXC, one `prompted`/`shared` for the file-mode consumer). **Mitigation**: This is acceptable and explicit in the secret list — see `mockups/paperless.example.nix` for the dual-secret pattern during migration. UXC-enabled services typically retire the file-mode secret once the legacy wrapper is removed. Per D9, only secrets referenced by an endpoint `auth` block project to UXC, so unused legacy secrets cause no UXC noise.
- **[Trade-off] Link shims are not atomic with credential/binding updates** → Home-Manager activation updates these independently, so a brief window exists where a shim points at a binding that hasn't been written yet. **Mitigation**: Activation runs top-down; bindings + credentials get written before link shims are placed in `$PATH`. Worst case: first `<name>-cli` call fails with a "binding not found" error; second call succeeds.
- **[Risk] LLM authoring is non-deterministic — same inputs produce different output across runs** → Two contributors regenerating the same skill might get diverging Guardrails sections. **Mitigation**: validate.sh enforces structural floor; PR review catches substantive drift; once committed, the artifact is static and shared. Non-determinism is contained at authoring; downstream consumers see the same skill.
- **[Risk] LLM cost at scale** → Authoring a 100-op API skill with retries can cost meaningful tokens. **Mitigation**: contributor-time only (not per-consumer); recipe uses prompt caching for the uxc-skill-creator skill body across retries; long specs can be summarized via op-list extraction before sending to the LLM.
- **[Risk] Spec drift undetected if contributors skip `nix flake check` locally** → Skill ships out of sync with the actual API. **Mitigation**: D14 spec-hash sidecar; CI runs the check on every PR; the bot comment states clearly which skills need regen.
- **[Trade-off] D15 hard-gate increases friction for new services** → A contributor adding a new UXC service must run the recipe before the build will pass. **Mitigation**: that's the point — projecting a UXC service without agent guidance is a footgun. Recipe is one command (`nix run .#author-skill -- ...`).
