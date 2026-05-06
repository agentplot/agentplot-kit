## Why

`mkClientTooling` currently knows two endpoint types: MCP (projected into Claude Code's `mcpServers` config) and CLI wrappers (a writeShellApplication pointed at a packaged binary). UXC ([holon-run/uxc](https://github.com/holon-run/uxc)) provides a unified CLI over MCP, OpenAPI, GraphQL, gRPC, and JSON-RPC — with 1Password-native secrets (`op://` references resolved at call time), daemon-backed session reuse, and a stable on-disk JSON config. Treating UXC as another projection target lets services expose any of those protocols with one declaration, agents gain a single consistent CLI contract, and secrets stop materializing in shell environments.

The first real driver is atomic: it exposes both MCP (currently works via direct Claude Code registration) and an OpenAPI 3.1 REST API (no projection target today). With UXC support, atomic declares its OpenAPI surface once and both Claude Code and a generated `atomic-openapi-cli` link consume it.

## What Changes

- Add an `openapi` capability to `mkClientTooling` — parallel to `mcp`, declaring an OpenAPI 3.1 endpoint with host, base path, and schema source
- Add an `op` secret mode alongside existing `prompted`/`generated`/`shared` — references a 1Password path (`op://Vault/Item/field`) that UXC resolves at call time
- Add an explicit per-endpoint `auth = { secret; type; }` block on `mcp` and `openapi` — each endpoint names which secret credentials it. Same secret can be reused across endpoints; multi-secret services bind each endpoint to its own credential explicitly
- Make `host`/`urlTemplate`/`schemaSource.url` accept either a string OR a function of clientSettings — symmetric so per-client domains plumb cleanly
- Add a `uxc.enabled` per-client consumer toggle — parallel to `claude-code.mcp.enabled`; opts the client into UXC projection
- Project MCP endpoints to UXC alongside OpenAPI — UXC v0.16+ fixed the `notifications/initialized` HTTP-transport bug (was D8 deferral). With `uxc.enabled` and an MCP capability, a service emits `<service>-mcp-cli` link shim and an UXC binding; claude-code's `mcpServers` entry can target `uxc` as the stdio command instead of hand-rolled `mcp-remote` wrappers
- Introduce `lib/mkUxcProjection.nix` — helper that converts a service's endpoints + credentials into UXC's on-disk JSON (`credentials.json` + `auth_bindings.json`) and link shim metadata
- Introduce `modules/home-manager/uxc.nix` — HM module that writes `~/.uxc/credentials.json` (mode `0600`), `~/.uxc/auth_bindings.json`, and link shim executables under `~/.local/bin/`
- Add a `nix run .#author-skill -- <serviceName> <protocol>` flake recipe that LLM-authors the wrapper skill at service-author time using a vendored `uxc-skill-creator` skill, validates the output via `scripts/validate.sh`, retries on failure, and writes a spec-hash sidecar for drift detection. Output is committed under `services/<svc>/skills/<protocol>/`
- Hard-gate at eval time: `mkClientTooling` evaluation fails if a service declares a UXC-projectable capability without a corresponding wrapper-skill directory. Cannot ship a UXC service with no agent guidance
- Leave existing `mcp`/`secret`/`cli` semantics untouched — additive; services can enable UXC, claude-code direct, or both consumers per client

## Capabilities

### New Capabilities
- `uxc-endpoints`: Declare OpenAPI and MCP endpoints (and later GraphQL/gRPC/JSON-RPC) that project into UXC's credentials/bindings/links JSON and link shim files; each endpoint binds an explicit `auth = { secret; type; }` block
- `op-secret-mode`: Reference a 1Password secret path on a credential; UXC resolves via `op` CLI at call time, secret never materializes on disk or in shell env
- `uxc-hm-module`: Home-Manager module that declaratively owns `~/.uxc/credentials.json`, `~/.uxc/auth_bindings.json`, and link shim executables
- `uxc-wrapper-skills`: LLM-authored wrapper skills at service-author time via `nix run .#author-skill`, vendored `uxc-skill-creator`, build-time validation via `scripts/validate.sh`, spec-hash drift detection, and an eval-time required-skill gate

### Modified Capabilities
None. All additions are additive to existing capabilities.

## Impact

- **lib/mkClientTooling.nix**: New `openapi` capability branch; new `op` mode in secret normalization; new `uxc.enabled` client option; new `uxc` projection path parallel to existing `claude-code` / `agent-deck` projections
- **lib/mkUxcProjection.nix** (new): Converts service endpoints + credentials to UXC's JSON shapes
- **modules/home-manager/uxc.nix** (new): HM module owning `~/.uxc/*.json` and link shims
- **Downstream services**: Services can opt into UXC projection by adding an `openapi` capability (or later `graphql`, etc.) and, if using 1Password, an `op`-mode secret. Existing MCP services continue to work unchanged.
- **No breaking changes**: Existing `mcp`, `secret`, `cli`, `skills`, `plugins` capabilities are unaffected. Services that don't add UXC declarations get no UXC projection.
- **UXC package**: Not provided by `agentplot-kit` in v1 — downstream flakes install UXC via homebrew, cargo, or (future) a nixpkgs package. The HM module writes config files but doesn't install the `uxc` binary.
