# Mockup: atomic clanService client role with UXC support.
#
# Goal demonstrated:
#   * one op-mode secret (admin-token) feeds BOTH mcp and openapi endpoints
#   * each endpoint declares its credential explicitly via `auth = { secret; type; }`
#   * `host` and `urlTemplate` are functions of clientSettings (per-client domain)
#   * MCP-via-UXC is no longer deferred (upstream bug fixed) — same admin-token
#     flows through UXC for both protocols, no separate file-mode secret needed
#   * claude-code.mcp.enabled and uxc.enabled are independent per-client toggles
#   * Wrapper skills are LLM-authored once per service via the `author-skill` recipe,
#     committed under services/atomic/skills/{openapi,mcp}/, validated at build time
#
# Required committed paths (regenerate via `nix run .#author-skill -- atomic openapi`):
#   services/atomic/openapi.json                     ← static OpenAPI spec
#   services/atomic/skills/openapi/SKILL.md          ← LLM-authored, ~80% atomic-specific
#   services/atomic/skills/openapi/agents/openai.yaml
#   services/atomic/skills/openapi/references/usage-patterns.md
#   services/atomic/skills/openapi/scripts/validate.sh
#   services/atomic/skills/openapi/.source-spec-hash ← sha256(openapi.json) at last regen
#
#   services/atomic/skills/mcp/SKILL.md              ← separately authored
#   services/atomic/skills/mcp/fixtures/help-output.txt ← captured `uxc <host>/mcp -h`
#   services/atomic/skills/mcp/.source-spec-hash     ← sha256(fixtures/help-output.txt)
#   ...etc
#
# Compare to current services/atomic/default.nix where the MCP wrapper hand-rolls
# `mcp-remote` + `cat tokenFile` shimmery. With UXC the wrapper goes away.

{ mkClientTooling, ... }:
{
  _class = "clan.service";
  manifest.name = "atomic";

  # roles.server elided — unchanged from existing default.nix

  roles.client =
    let
      tooling = mkClientTooling {
        serviceName = "atomic";
        capabilities = {
          # ── Hand-authored service-level skill ──────────────────────────────
          # Wraps higher-level guidance (when to use atomic vs other tools, tagging
          # conventions, etc.). Wrapper skills for the protocols are auto-discovered
          # at services/atomic/skills/{openapi,mcp}/ by mkClientTooling — they don't
          # appear in this list, they're picked up by D15.
          skills = [
            ./skills/SKILL.md  # service-level usage guidance
          ];

          # ── Secrets ────────────────────────────────────────────────────────
          # Single op-mode secret. Resolved by `op` CLI at every uxc call.
          # Never written to disk, never exported to env by Nix.
          secret = [
            {
              name = "admin-token";
              mode = "op";
              reference = "op://Personal/Atomic/token";
            }
          ];

          # ── MCP endpoint ───────────────────────────────────────────────────
          # Projects to UXC binding (when uxc.enabled) AND/OR to claude-code
          # mcpServers (when claude-code.mcp.enabled). Auth block names the
          # secret — projection writes a UXC credential bound to this endpoint.
          mcp = {
            type = "http";
            urlTemplate = client: "https://${client.domain}/mcp";
            auth = {
              secret = "admin-token";
              type = "bearer";
            };
          };

          # ── OpenAPI endpoint ───────────────────────────────────────────────
          # Schema source committed to the repo (atomic does not serve openapi.json
          # publicly — /api/openapi.json returns 401). Same admin-token credential
          # via the same `auth.secret` reference.
          openapi = {
            host = client: client.domain;            # fn of clientSettings — symmetric with urlTemplate
            pathPrefix = "/api";
            schemaSource = {
              type = "static";
              path = ./openapi.json;                  # would live at services/atomic/openapi.json
            };
            auth = {
              secret = "admin-token";
              type = "bearer";
            };
            # linkName defaults to "atomic-openapi-cli"
          };
        };

        extraClientOptions = { lib, ... }: {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "FQDN of the Atomic server (e.g., atomic.swancloud.net)";
          };
          # claude-code.mcp.enabled and uxc.enabled are auto-added by mkClientTooling
          # because mcp + openapi capabilities are present.
        };
      };
    in
    {
      description = "Atomic agent tooling (MCP + OpenAPI via UXC, optional claude-code direct MCP)";
      inherit (tooling) interface perInstance;
    };

  # ── Inventory example ───────────────────────────────────────────────────────
  # Per-client toggles drive which projections fire.
  #
  # services.atomic.client.mac = {
  #   roles = [ "client" ];
  #   config.clients = {
  #     personal = {
  #       domain = "atomic.swancloud.net";
  #       uxc.enabled = true;             # → atomic-mcp-cli + atomic-openapi-cli on PATH
  #       claude-code.mcp.enabled = true; # → ALSO direct claude-code mcpServers entry
  #                                       #   (uses uxc as stdio command, no file token)
  #     };
  #   };
  # };
  #
  # Resulting on-disk artifacts (per client):
  #   ~/.uxc/credentials.json:
  #     "agentplot-atomic-personal-admin-token": {
  #       auth_type: "bearer",
  #       secret_source: { kind: "op", reference: "op://Personal/Atomic/token" }
  #     }
  #   ~/.uxc/auth_bindings.json:
  #     [
  #       { id: "agentplot-atomic-personal-mcp",     host: atomic.swancloud.net, path_prefix: "/mcp",
  #         credential: "agentplot-atomic-personal-admin-token", priority: 100, enabled: true },
  #       { id: "agentplot-atomic-personal-openapi", host: atomic.swancloud.net, path_prefix: "/api",
  #         credential: "agentplot-atomic-personal-admin-token", priority: 100, enabled: true }
  #     ]
  #   ~/.local/bin/atomic-mcp-cli      → exec uxc 'atomic.swancloud.net' "$@"
  #   ~/.local/bin/atomic-openapi-cli  → exec uxc 'atomic.swancloud.net' --schema-url 'file://...' "$@"
  #
  # claude-code mcpServers entry (when claude-code.mcp.enabled):
  #   {
  #     "atomic": {
  #       "command": "uxc",
  #       "args": ["mcp", "atomic.swancloud.net"]
  #     }
  #   }
}
