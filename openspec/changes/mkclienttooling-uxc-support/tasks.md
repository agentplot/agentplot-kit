## 1. Secret Normalization — `op` mode

- [x] 1.1 Extend secret normalization in `lib/mkClientTooling.nix` to accept `mode = "op"` entries; validate that `reference` is present and starts with `op://`
- [x] 1.2 Build a parallel `opSecrets` attrset alongside `secretPaths` — keyed by secret name, values are the `op://` reference strings
- [x] 1.3 Document that `op` secrets have no entry in `secretPaths` and are not available to `cli.envVars` / `mcp.extraConfig` callbacks
- [x] 1.4 Skip `op` secrets when building the vars generator attrset (mirror the existing `shared` mode filter)

## 2. Endpoint `auth` Block (D9)

- [x] 2.1 Define a shared `authSubmodule` (lib): `{ secret : str; type : enum [ "bearer" "api_key" ]; }`
- [x] 2.2 Add `mcp.auth` and `openapi.auth` capability fields; require both when the endpoint is UXC-projectable
- [x] 2.3 Validate at eval time: every `auth.secret` resolves to an entry in the `secret` capability; raise a clear error otherwise
- [x] 2.4 Validate at eval time: a `auth.secret` referencing a non-`op`-mode secret fails for UXC projection (allowed for claude-code direct path only)
- [x] 2.5 Build `referencedSecrets` set from all endpoint `auth.secret` references; only project those into UXC credentials

## 3. OpenAPI Capability

- [x] 3.1 Add `openapi` capability branch: `{ host, pathPrefix?, scheme?, schemaSource, auth, linkName?, priority? }`
- [x] 3.2 Accept `host`/`scheme`/`pathPrefix` as string OR fn-of-clientSettings; resolve via a helper `resolveStringOrFn cs v`
- [x] 3.3 Resolve `schemaSource.type = "static"` to a Nix store path; build the `--schema-url file:///nix/store/...` string at eval time
- [x] 3.4 Resolve `schemaSource.type = "derivation"` using the provided derivation's `outPath`
- [x] 3.5 Resolve `schemaSource.type = "url"` to the URL verbatim; allow `url` itself to be string OR fn-of-clientSettings
- [x] 3.6 Default `scheme = "https"`, `pathPrefix = "/"`, `priority = 100`, `linkName = "${serviceName}-openapi-cli"`

## 4. MCP→UXC Projection (was deferred — D8 v1 scope)

- [x] 4.1 When `uxc.enabled` and `mcp` capability is declared, emit a UXC binding using `urlTemplate` parsed into `scheme + host + path_prefix`
- [x] 4.2 Emit `<serviceName>-mcp-cli` link shim that exec's `uxc <host>` for the MCP endpoint
- [x] 4.3 Optional: when a client has BOTH `uxc.enabled` AND `claude-code.mcp.enabled`, emit the claude-code `mcpServers.<name>` entry as a stdio command pointing at `uxc` (no file token needed); guard behind a `mcp.viaUxcInClaudeCode = true` opt-in to avoid silently changing existing wrappers
- [x] 4.4 Pin the minimum supported UXC version (`>= 0.16` once tagged with the MCP-init fix); document in HM module activation message

## 5. UXC Client Interface

- [x] 5.1 Add `uxc.enabled` option to `clientSubmodule` (guarded by any UXC-compatible capability being present — `openapi` or `mcp`)
- [x] 5.2 Add `uxc.linkName` option allowing per-client override of the default link name (per-protocol)
- [x] 5.3 Drop `uxc.credential` per-client override — credential selection is now driven by endpoint `auth` blocks (D9), not per-client toggles

## 6. UXC Projection Library

- [x] 6.1 Create `lib/mkUxcProjection.nix` exporting `mkUxcProjection { serviceName, clientName, clientSettings, endpoints, secrets, referencedSecrets }` → `{ credentials, bindings, links }` attrset
- [x] 6.2 Credential projection: for each `secretName` in `referencedSecrets`, emit `{ id = "agentplot-<service>-<client>-<secretName>"; auth_type = <auth.type>; secret_source = { kind = "op"; reference = secret.reference; }; }`
- [x] 6.3 Binding projection: one binding per endpoint with `id = agentplot-<service>-<client>-<protocol>`, resolved `scheme`/`host`/`path_prefix`, `credential = agentplot-<service>-<client>-<auth.secret>`, `priority`, `enabled = true`
- [x] 6.4 Link projection: one link per endpoint with `name = <linkName>`, resolved `host`, `schemaUrl` (OpenAPI only)
- [ ] 6.5 Export via `flake.nix` so downstream repos can call `agentplot-kit.lib.mkUxcProjection`

## 7. UXC Home-Manager Module

- [x] 7.1 Create `modules/home-manager/uxc.nix` with options: `programs.uxc.enable`, `programs.uxc.credentials` (attrset), `programs.uxc.bindings` (list), `programs.uxc.links` (attrset of `{ host, schemaUrl?, injectEnv? }`)
- [x] 7.2 Implement `home.file.".uxc/credentials.json"` with `mode = "0600"` rendered via `pkgs.formats.json.generate`
- [x] 7.3 Implement `home.file.".uxc/auth_bindings.json"` with `mode = "0600"` rendered from bindings option
- [x] 7.4 Implement link shim generation: for each link, create a `pkgs.writeShellApplication` with the UXC-conventional shim body and install into `home.packages`
- [ ] 7.5 Register in `flake.nix` as a home-manager module export

## 8. mkClientTooling Wiring

- [x] 8.1 In `perInstance`, when `uxc.enabled` is true for a client, build the projection via `mkUxcProjection` and merge it into a new `programs.uxc.*` attribute on the client's HM module
- [x] 8.2 Ensure multiple services targeting the same client merge their UXC projections (via `lib.mkMerge`) rather than overwriting
- [x] 8.3 Emit credentials/bindings for a client only when `uxc.enabled = true` AND the service has at least one endpoint with a resolvable `auth.secret`

## 9. Documentation

- [x] 9.1 Update `lib/mkClientTooling.nix` header comment to document the new capabilities including `auth` blocks
- [ ] 9.2 Add `README.md` section on UXC projection with the atomic-example snippet from `mockups/atomic.example.nix`
- [ ] 9.3 Document the `op` service account prerequisite (users need `OP_SERVICE_ACCOUNT_TOKEN` in their shell env or an interactive `op signin`)
- [ ] 9.4 Document the dual-secret pattern for migrations (legacy CLI + UXC) — link to `mockups/paperless.example.nix`

## 10. Wrapper-Skill Pipeline (D11–D15)

- [ ] 10.1 Vendor upstream `uxc-skill-creator` at `skills/uxc-skill-creator/` (initial copy from holon-run/uxc); record source ref in a `VERSION` or sidecar file
- [ ] 10.2 Add a flake input or git-submodule pin for the upstream skill so version bumps surface as PR diffs
- [ ] 10.3 Implement `apps.<system>.author-skill` as a `pkgs.writeShellApplication`; wrap claude headless invocation with capability extraction (`nix eval` for host/linkName/authType/schemaSource) and output-dir resolution (`services/<svc>/skills/<protocol>/`)
- [ ] 10.4 Recipe retry loop: capture validate.sh output on failure, re-prompt claude with errors as additional context, max 3 attempts
- [ ] 10.5 Recipe writes `.source-spec-hash` sidecar after success — SHA-256 of spec content (file or fetched URL)
- [ ] 10.6 Recipe early-exits with clear error if `ANTHROPIC_API_KEY` is unset
- [ ] 10.7 Add `nix flake check` derivation that iterates over committed wrapper skills, runs each `scripts/validate.sh`, fails on any non-zero exit
- [ ] 10.8 Add `nix flake check` derivation that recomputes `sha256(spec)` for each service, compares against `.source-spec-hash` sidecar, fails on mismatch
- [x] 10.9 Add eval-time required-skill check in `mkClientTooling`: when `mcp` or `openapi` capability declared, look up `services/<svc>/skills/<protocol>/` (or explicit `endpoint.skill = ./path`); fail with an error message pointing at the recipe if missing
- [x] 10.10 Extend `mkSkillContent` substitution table to rewrite `${serviceName}-openapi-cli` and `${serviceName}-mcp-cli` to resolved per-client `linkName`; cover both SKILL.md body and frontmatter `name:` field
- [ ] 10.11 Document MCP fixture pattern: services without OpenAPI spec ship `skills/mcp/fixtures/help-output.txt` (captured `uxc <host> -h` output) and the spec-hash check hashes that fixture
- [ ] 10.12 Verify recipe end-to-end against atomic: `nix run .#author-skill -- atomic openapi` produces a passing skill against `services/atomic/openapi.json`

## 11. Verification

- [ ] 10.1 Add a test that a service declaring only `openapi` (no `mcp`) evaluates correctly with `uxc.enabled = true` and a client with `uxc.enabled = false`
- [ ] 10.2 Add a test that a service with both `mcp` and `openapi` referencing the same `auth.secret` produces ONE credential and TWO bindings
- [ ] 10.3 Add a test that an `auth.secret` referencing a missing secret name fails eval with a clear error
- [ ] 10.4 Add a test that an `auth.secret` referencing a non-`op` secret fails UXC projection
- [ ] 10.5 Add a test that `mkUxcProjection` produces valid JSON matching UXC v0.16+ schema (snapshot test against a known-good output)
- [ ] 10.6 Confirm existing services (linkding, atomic, subcog) continue to evaluate unchanged when they don't add UXC declarations
- [ ] 10.7 Manual end-to-end: apply on mac-studio with atomic's MCP+OpenAPI capability enabled; confirm `atomic-openapi-cli -h` and `atomic-mcp-cli` work; confirm `~/.uxc/credentials.json` matches expected shape; confirm `uxc auth credential show agentplot-atomic-personal-admin-token` resolves the `op://` reference
