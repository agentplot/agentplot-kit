## Purpose

Linkding clanService with server and client roles, named clients, secret management, and co-located packages. Defines the server role (microVM-based linkding deployment) and the client role (multi-client configuration with per-client secrets and integrations).

## Requirements

### Requirement: Linkding server role origin and dependencies
The linkding server role implementation SHALL be migrated from `swancloud/clanServices/linkding/default.nix`. It runs as a microVM guest using the microvm clanService (also migrated from `swancloud/clanServices/microvm/default.nix`). The microvm clanService provides host/guest role wiring: cloud-hypervisor, TAP networking, VirtioFS shares (`/nix/store`, `/var/lib/sops-nix`, `/etc/ssh`, `/var/log/journal`, `/persist`), and bridge connectivity.

The linkding server role depends on:
- **microvm clanService** (moved to agentplot alongside linkding) -- guest role for VM lifecycle
- **caddy-cloudflare module** (moved to agentplot as shared module) -- Cloudflare DNS-01 TLS
- **PostgreSQL on the host** (consumer-provided) -- database at `10.0.0.1:5432`
- **Network bridge on the host** (consumer-provided) -- `10.0.0.1/24` bridge with NAT
- **CoreDNS registration** (consumer-provided, optional) -- DNS for `*.swancloud.net`
- **Kanidm OIDC** (consumer-provided, optional) -- identity provider

The microvm clanService is generic infrastructure not specific to agents. It MAY move upstream of agentplot in the future, but lives in agentplot for now.

#### Scenario: Server deployment
- **WHEN** a machine is assigned the linkding server role and the microvm guest role with `settings.domain = "links.example.com"`
- **THEN** the machine SHALL run as a microVM guest with linkding on port 9090, Caddy with HTTPS on port 443, and PostgreSQL accessed at the host bridge IP

#### Scenario: OIDC enabled
- **WHEN** `settings.oidc.enable = true` and `settings.oidc.issuerDomain = "auth.example.com"`
- **THEN** the linkding container SHALL be configured with OIDC environment variables pointing to the Kanidm endpoints

### Requirement: Linkding client role with named clients
The linkding clanService SHALL define a client role with `options.clients` as `attrsOf clientSubmodule`. Each client submodule SHALL expose:
- `name` (str) -- CLI binary name and integration identifier
- `base_url` (str) -- linkding instance URL
- `default_tags` (listOf str, default []) -- default tags for bookmarks
- `cli.enabled` (bool) -- install per-client CLI wrapper script (bakes in URL + token)
- `claude-code.skill.enabled` (bool) -- install Claude agent skill
- `claude-code.mcp.enabled` (bool) -- configure Claude MCP server (default profile)
- `claude-code.profiles` (attrsOf submodule with `mcp.enabled`) -- per-profile MCP configuration
- `agent-skills.enabled` (bool) -- distribute skill via agent-skills module
- `agent-deck.mcp.enabled` (bool) -- add agent-deck MCP entry
- `openclaw.skill.enabled` (bool) -- add OpenClaw skill
- `claude-tools.enabled` (bool) -- install via claude-plugins marketplace

#### Scenario: Single client with all integrations
- **WHEN** a machine is assigned the client role with one client named "linkding" with all flags enabled
- **THEN** the machine SHALL have the linkding CLI installed, a Claude skill, an MCP server entry, an agent-deck MCP entry, and an OpenClaw skill

#### Scenario: Two clients on same machine (personal/business)
- **WHEN** a machine has clients `personal = { name = "linkding"; ... }` and `business = { name = "linkding-biz"; ... }`
- **THEN** the machine SHALL have two distinct CLI binaries, two distinct skill entries, two distinct MCP entries, and two distinct sets of environment variables

### Requirement: Flexible per-client secret management
Each named client SHALL have its own clan vars generator for the API token, named `agentplot-linkding-${clientName}-api-token`. The generator SHALL support two modes:
- **Auto-generated**: When the server can programmatically create tokens (e.g., via admin API), the generator script SHALL provision the token automatically using server credentials from a shared clan var.
- **Prompted**: When the server requires manual token creation, the generator SHALL use `prompts` with `type = "hidden"` to collect the token during `clan vars generate`.

The clanService SHALL declare which mode its server supports. The client role's secret path SHALL be identical regardless of generation mode.

#### Scenario: Prompted secret generation for two clients
- **WHEN** `clan vars generate` is run for a machine with personal and business clients and the service uses prompted mode
- **THEN** the operator SHALL be prompted for two separate API tokens, one for each client

#### Scenario: Auto-generated secret
- **WHEN** `clan vars generate` is run for a service that supports auto-generation
- **THEN** the generator script SHALL create the API token programmatically without operator input

#### Scenario: Secret path available to HM config regardless of mode
- **WHEN** the client role generates HM config for a client
- **THEN** the MCP server and CLI wrapper SHALL reference the clan vars secret file path for the corresponding client's API token
- **AND** the path format SHALL be identical whether the token was auto-generated or prompted

### Requirement: Co-located packages and skills
The linkding CLI package and SKILL.md SHALL be co-located within the clanService directory in the agentplot repository, not in a separate repository.

#### Scenario: Skill content accessible from perInstance
- **WHEN** the client role's perInstance generates HM config
- **THEN** it SHALL reference `./skills/SKILL.md` relative to the clanService definition and the path SHALL resolve correctly in the Nix store
