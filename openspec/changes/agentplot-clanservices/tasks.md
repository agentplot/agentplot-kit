## 1. Repository Setup

- [x] 1.1 Create `agentplot/agentplot` GitHub repository with flake.nix skeleton (inputs: nixpkgs, microvm, agentplot-kit, agent-skills-nix, claude-plugins-nix, nix-agent-deck, nix-openclaw)
- [x] 1.2 Set up directory structure: `modules/`, `services/linkding/`, `services/linkding/packages/`, `services/linkding/skills/`, `services/microvm/`
- [x] 1.3 Add flake outputs: `clanModules.linkding`, `clanModules.microvm`, `nixosModules.agentplot`, `darwinModules.agentplot` (adapter modules pointing to same file)

## 2. HM Passthrough Adapter Module

- [x] 2.1 Create `modules/agentplot.nix` with `options.agentplot.user` (nullOr str, default null) and `options.agentplot.hmModules` (attrsOf deferredModule)
- [x] 2.2 Implement config block: when `agentplot.user` is non-null, import all `agentplot.hmModules` entries into `home-manager.users.${agentplot.user}`
- [ ] 2.3 Smoke test: verify two mock clanServices both writing to `agentplot.hmModules` compose without conflict

## 3. MicroVM Infrastructure ClanService

- [ ] 3.1 Move `clanServices/microvm/default.nix` from swancloud to `services/microvm/default.nix`
- [ ] 3.2 Move `modules/caddy-cloudflare.nix` from swancloud to `modules/caddy-cloudflare.nix`
- [ ] 3.3 Verify microvm clanService host/guest roles work from the new location (cloud-hypervisor, VirtioFS shares, TAP networking)

## 4. Linkding Server Role

- [x] 4.1 Move `clanServices/linkding/default.nix` from swancloud to `services/linkding/default.nix`, adapting to the new repo's structure
- [x] 4.2 Define `_class = "clan.service"`, `manifest`, and `roles.server` with interface options (domain, oidc.enable, oidc.issuerDomain)
- [x] 4.3 Implement server `perInstance` with OCI container, Caddy, PostgreSQL, clan vars generators for db password and OIDC secrets

## 5. Linkding Client Role — Interface

- [x] 5.1 Define `roles.client` with `options.clients` as `attrsOf clientSubmodule`
- [x] 5.2 Define clientSubmodule options with normalized names matching downstream modules: `name`, `base_url`, `default_tags`, `cli.enabled`, `claude-code.skill.enabled`, `claude-code.mcp.enabled`, `claude-code.profiles`, `agent-skills.enabled`, `agent-deck.mcp.enabled`, `openclaw.skill.enabled`, `claude-tools.enabled`
- [x] 5.3 Add per-client clan vars generators for API tokens (flexible: auto-generated when server supports it, prompted with type "hidden" when not)

## 6. Linkding Client Role — Delegation Implementation

- [x] 6.1 Move linkding-cli base package from agentplot-kit to `services/linkding/packages/linkding-cli/` (the generic restish wrapper, unchanged)
- [x] 6.2 Move linkding SKILL.md from agentplot-kit to `services/linkding/skills/SKILL.md` (template source)
- [x] 6.3 Implement per-client CLI wrapper: `writeShellApplication` that exports `LINKDING_API_TOKEN` (from clan vars path) and `LINKDING_BASE_URL` (from settings), then execs base linkding-cli. Binary name = client's `name`
- [x] 6.4 Implement per-client SKILL.md generation: `pkgs.writeText` substituting the client-specific CLI name into the skill template
- [x] 6.5 Implement programs.claude-code delegation: `skills.<client-name>` (generated SKILL.md path), `mcpServers.<client-name>`, and per-profile `profiles.<profile>.mcpServers.<client-name>` based on enable flags
- [x] 6.6 Implement programs.agent-skills delegation: register `path`-based source, select skill via `explicit` with `packages` (client CLI wrapper) and `transform` for CLI name substitution, enable `targets.claude`
- [x] 6.7 Implement programs.agent-deck delegation: add MCP entry to `mcps.<client-name>` (freeform attrs)
- [x] 6.8 Implement programs.openclaw delegation: append skill entry to `skills` list with mode and content
- [x] 6.9 Implement programs.claude-tools delegation: add to `skillsByClient` (attrsOf mode) or `claude-plugins.plugins`
- [x] 6.10 Wire all delegation output through `config.agentplot.hmModules.linkding-${clientName}` using deferredModule, capturing clan vars paths in perInstance closure

## 7. Integration and Migration

- [x] 7.1 Update agentplot-kit: remove linkding-cli package, linkding skill, and linkding entry from env-contract.nix; remove paperless-cli package and paperless skill (these move to agentplot with their future clanService); keep generic tooling only (HM modules, restish/secretspec/recutils/lobster/evernote-convert skills); update flake.nix outputs
- [ ] 7.2 Add agentplot as flake input to swancloud/clan-lol, update inventory to reference `input = "agentplot"` for linkding and microvm
- [ ] 7.3 Remove migrated clanServices (linkding, microvm) and caddy-cloudflare module from swancloud
- [ ] 7.4 Import `agentplot.nixosModules.agentplot` (or `darwinModules.agentplot`) in machine configs, set `agentplot.user = "chuck"`
- [ ] 7.5 Configure linkding client role in inventory with personal and business clients
- [ ] 7.6 Run `clan vars generate` to set API tokens for both clients
- [ ] 7.7 Test: verify all integrations — CLI wrappers, skills, MCP entries, agent-skills, agent-deck, openclaw, and claude-tools
