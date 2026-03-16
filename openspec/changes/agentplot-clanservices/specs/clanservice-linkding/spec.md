## ADDED Requirements

### Requirement: Linkding server role
The linkding clanService SHALL define a server role that deploys linkding as an OCI container with Caddy reverse proxy, PostgreSQL database, and clan vars-managed secrets. The server role interface SHALL expose `domain` (str, required), `oidc.enable` (bool, default false), and `oidc.issuerDomain` (str, default "").

#### Scenario: Server deployment
- **WHEN** a machine is assigned the server role with `settings.domain = "links.example.com"`
- **THEN** the machine SHALL run linkding on port 9090, Caddy with HTTPS on port 443, and PostgreSQL with a generated database password

#### Scenario: OIDC enabled
- **WHEN** `settings.oidc.enable = true` and `settings.oidc.issuerDomain = "auth.example.com"`
- **THEN** the linkding container SHALL be configured with OIDC environment variables pointing to the Kanidm endpoints

### Requirement: Linkding client role with named clients
The linkding clanService SHALL define a client role with `options.clients` as `attrsOf clientSubmodule`. Each client submodule SHALL expose:
- `name` (str) — CLI binary name and integration identifier
- `base_url` (str) — linkding instance URL
- `default_tags` (listOf str, default []) — default tags for bookmarks
- `cli.enabled` (bool) — install per-client CLI wrapper script (bakes in URL + token)
- `claude-code.skill.enabled` (bool) — install Claude agent skill
- `claude-code.mcp.enabled` (bool) — configure Claude MCP server (default profile)
- `claude-code.profiles` (attrsOf submodule with `mcp.enabled`) — per-profile MCP configuration
- `agent-skills.enabled` (bool) — distribute skill via agent-skills module (Phase 2)
- `agent-deck.mcp.enabled` (bool) — add agent-deck MCP entry (Phase 2)
- `openclaw.skill.enabled` (bool) — add OpenClaw skill (Phase 2)
- `claude-tools.enabled` (bool) — install via claude-plugins marketplace (Phase 2)

#### Scenario: Single client with all integrations
- **WHEN** a machine is assigned the client role with one client named "linkding" with all flags enabled
- **THEN** the machine SHALL have the linkding CLI installed, a Claude skill, an MCP server entry, an agent-deck MCP entry, and an OpenClaw skill

#### Scenario: Two clients on same machine (personal/business)
- **WHEN** a machine has clients `personal = { name = "linkding"; ... }` and `business = { name = "linkding-biz"; ... }`
- **THEN** the machine SHALL have two distinct CLI binaries, two distinct skill entries, two distinct MCP entries, and two distinct sets of environment variables

### Requirement: Per-client secret management
Each named client SHALL have its own clan vars generator for the API token, named `agentplot-linkding-${clientName}-api-token`. The generator SHALL use a prompt (type "hidden") to collect the token during `clan vars generate`.

#### Scenario: Secret generation for two clients
- **WHEN** `clan vars generate` is run for a machine with personal and business clients
- **THEN** the operator SHALL be prompted for two separate API tokens, one for each client

#### Scenario: Secret path available to HM config
- **WHEN** the client role generates HM config for a client
- **THEN** the MCP server and CLI wrapper SHALL reference the clan vars secret file path for the corresponding client's API token

### Requirement: Co-located packages and skills
The linkding CLI package and SKILL.md SHALL be co-located within the clanService directory in the agentplot repository, not in a separate repository.

#### Scenario: Skill content accessible from perInstance
- **WHEN** the client role's perInstance generates HM config
- **THEN** it SHALL reference `./skills/SKILL.md` relative to the clanService definition and the path SHALL resolve correctly in the Nix store
