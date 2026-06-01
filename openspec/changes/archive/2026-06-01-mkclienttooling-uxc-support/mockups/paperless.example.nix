# Mockup: paperless clanService client role with UXC support added.
#
# Goals demonstrated:
#   * existing `cli` capability (paperless-cli restish wrapper) coexists with new openapi
#     UXC projection — operators can migrate gradually
#   * per-client `base_url` plumbs into `openapi.host` via fn-of-clientSettings,
#     same shape as `mcp.urlTemplate` (host accepts string OR fn)
#   * op-mode secret cannot feed `cli.envVars` (no file path) — so a paperless
#     client that wants both the legacy CLI AND UXC needs TWO secret entries:
#         { name = "api-token";    mode = "op"; reference = "op://..."; }   # for UXC
#         { name = "api-token-fs"; mode = "prompted"; }                     # for paperless-cli
#     This is the documented trade-off (design.md §Risks). Eventually paperless-cli
#     deprecates in favor of `paperless-openapi-cli` and the prompted secret drops.
#   * paperless has no MCP endpoint today — this mockup shows openapi-only UXC.

{ mkClientTooling, enex2paperless ? null, ... }:
{
  _class = "clan.service";
  manifest.name = "paperless";

  # roles.server elided — unchanged

  roles.client =
    let
      tooling = mkClientTooling {
        serviceName = "paperless";
        capabilities = {
          # Hand-authored skills (service-level + evernote tooling).
          # The UXC wrapper skill at services/paperless/skills/openapi/ is
          # auto-discovered by mkClientTooling per D15 — not in this list.
          # Regenerate via `nix run .#author-skill -- paperless openapi`.
          skills = [
            ./skills/SKILL.md
            ./skills/evernote-convert
          ];
          extraPackages = builtins.filter (p: p != null) [ enex2paperless ];

          # ── Secrets ────────────────────────────────────────────────────────
          # Two secrets while paperless-cli (legacy restish wrapper) still ships.
          # When that wrapper is retired, drop `api-token-fs` and only `api-token`
          # (op mode) remains.
          secret = [
            {
              name = "api-token";
              mode = "op";
              reference = "op://Personal/Paperless/token";
            }
            {
              name = "api-token-fs";  # file-on-disk variant for legacy CLI
              mode = "prompted";
              description = client: "API token for legacy paperless-cli on '${client.name}'";
            }
          ];

          # ── Legacy CLI ─────────────────────────────────────────────────────
          # Reads `api-token-fs` (op secret has no file path; would fail eval if used).
          # Will be removed once paperless-openapi-cli is the canonical path.
          cli = {
            package = ./packages/paperless-cli;
            wrapperName = client: client.name;
            envVars = client: {
              PAPERLESS_API_TOKEN = "$(cat ${client.secretPaths.api-token-fs})";
              PAPERLESS_BASE_URL = client.base_url;
            };
          };

          # ── OpenAPI endpoint (UXC) ─────────────────────────────────────────
          openapi = {
            host = client: client.host;             # fn — derive from base_url, no scheme/path
            scheme = client: client.scheme;         # default https; allow http for self-hosted dev
            pathPrefix = "/api";
            schemaSource = {
              # Paperless serves /api/schema/?format=openapi at runtime — fetch via flake input
              # at build time, or use `type = "url"` if you want runtime fetches.
              type = "url";
              url = client: "${client.base_url}/api/schema/?format=openapi";
            };
            auth = {
              secret = "api-token";   # op-mode secret — UXC resolves via op:// at call time
              type = "bearer";
            };
          };
        };

        extraClientOptions = { lib, ... }: {
          base_url = lib.mkOption {
            type = lib.types.str;
            description = "Base URL of the Paperless-ngx instance (e.g., https://docs.swancloud.net)";
          };
          # Convenience derived options (mocked; mkClientTooling could derive these).
          # Or callers parse base_url themselves and set host/scheme directly.
          host = lib.mkOption {
            type = lib.types.str;
            description = "Hostname extracted from base_url (e.g., docs.swancloud.net)";
          };
          scheme = lib.mkOption {
            type = lib.types.enum [ "http" "https" ];
            default = "https";
          };
        };
      };
    in
    {
      description = "Paperless agent tooling (skills, legacy CLI, UXC OpenAPI projection)";
      inherit (tooling) interface perInstance;
    };

  # ── Inventory example ───────────────────────────────────────────────────────
  #
  # services.paperless.client.mac = {
  #   roles = [ "client" ];
  #   config.clients = {
  #     personal = {
  #       name = "paperless";
  #       base_url = "https://docs.swancloud.net";
  #       host = "docs.swancloud.net";
  #       scheme = "https";
  #       claude-code.skill.enabled = true;
  #       cli.enabled = true;       # legacy paperless-cli (uses api-token-fs)
  #       uxc.enabled = true;       # paperless-openapi-cli (uses op:// reference)
  #     };
  #   };
  # };
  #
  # Resulting artifacts (uxc.enabled side):
  #   ~/.uxc/credentials.json:
  #     "agentplot-paperless-personal-api-token": {
  #       auth_type: "bearer",
  #       secret_source: { kind: "op", reference: "op://Personal/Paperless/token" }
  #     }
  #   ~/.uxc/auth_bindings.json:
  #     [
  #       { id: "agentplot-paperless-personal-openapi", host: "docs.swancloud.net",
  #         scheme: "https", path_prefix: "/api",
  #         credential: "agentplot-paperless-personal-api-token", priority: 100 }
  #     ]
  #   ~/.local/bin/paperless-openapi-cli  → exec uxc 'docs.swancloud.net' --schema-url 'https://docs.swancloud.net/api/schema/?format=openapi' "$@"
  #
  # And the legacy CLI keeps shipping at ~/.local/bin/paperless until retired.
}
