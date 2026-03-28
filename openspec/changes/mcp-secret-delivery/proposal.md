## Why

MCP servers that need secrets (API tokens, auth keys) currently have no general-purpose mechanism for receiving them at runtime. The CLI wrapper approach works for agentplot-managed CLI tools, but breaks down for:

- **Third-party stdio MCP servers** (GitHub MCP, Context7, Zoho) where the user doesn't control the binary — these need env vars like `GITHUB_TOKEN` set on the spawned process, but the MCP config `env` block bakes values into a static JSON file in the Nix store, which can't hold real secrets.
- **HTTP MCP servers with auth** — the correct field is `headers` with env var substitution (`${VAR_NAME}`), but mkClientTooling currently generates a non-standard `tokenFile` field that Claude Code doesn't understand. (Note: Claude Code has an upstream bug where `headers` is ignored for HTTP — Issue #7290 — but we should generate the correct config regardless.)
- **URL-embedded secrets** — some HTTP MCP servers require credentials in the URL itself (e.g., `https://user:token@host/mcp`), which mkClientTooling's `urlTemplate` can't express without leaking secrets into the Nix store.

The shell session environment is an underutilized path: if `GITHUB_TOKEN` is already set in the user's shell, stdio MCP servers inherit it from the Claude Code process. The HM module could set session env vars that read secrets at login time.

## What Changes

- Define supported secret delivery patterns for MCP servers across all transport types
- For **stdio** servers: support shell session env vars via `home.sessionVariables` or activation scripts that read from secret files at login, so MCP servers inherit secrets without needing a wrapper or Nix store leakage
- For **HTTP** servers: generate `headers` with `${VAR_NAME}` env var substitution instead of `tokenFile`; support URL templates that reference env vars for URL-embedded secrets
- Update mkClientTooling's `mcp` + `secret` interaction to produce the correct config per transport type

## Capabilities

### New Capabilities
- `mcp-session-env`: HM module config that sets shell session env vars from secret files at login, enabling third-party stdio MCP servers to receive secrets via environment inheritance
- `mcp-http-headers`: mkClientTooling generates correct `headers` field with env var substitution for HTTP MCP servers requiring auth

### Modified Capabilities
- `mkClientTooling.mcp`: Updated to generate transport-appropriate secret delivery (env inheritance for stdio, headers for HTTP) instead of non-standard `tokenFile`

## Impact

- `lib/mkClientTooling.nix` — MCP config generation updated for both transport types
- `modules/home-manager/` — session env var generation for MCP secrets
- Services declaring `mcp` + `secret` capabilities — config output changes (backwards compatible: `tokenFile` was already ignored by Claude Code)
- Consumers — may need to ensure secret-derived env vars are set in their shell sessions for third-party MCP servers
