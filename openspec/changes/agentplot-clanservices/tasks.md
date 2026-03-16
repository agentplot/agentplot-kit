## 1. Repository Setup

- [ ] 1.1 Create `agentplot/agentplot` GitHub repository with flake.nix skeleton (inputs: nixpkgs, agentplot-kit, agent-skills-nix, claude-plugins-nix, nix-agent-deck, nix-openclaw)
- [ ] 1.2 Set up directory structure: `modules/`, `services/linkding/`, `services/linkding/packages/`, `services/linkding/skills/`
- [ ] 1.3 Add flake outputs: `clanModules.linkding`, `nixosModules.agentplot`, `darwinModules.agentplot` (both pointing to same module file)

## 2. HM Passthrough Adapter Module

- [ ] 2.1 Create `modules/agentplot.nix` with `options.agentplot.user` (nullOr str, default null) and `options.agentplot.hmModules` (attrsOf deferredModule)
- [ ] 2.2 Implement config block: when `agentplot.user` is non-null, import all `agentplot.hmModules` entries into `home-manager.users.${agentplot.user}`
- [ ] 2.3 Smoke test: verify two mock clanServices both writing to `agentplot.hmModules` compose without conflict

## 3. Linkding Server Role

- [ ] 3.1 Move `clanServices/linkding/default.nix` from swancloud to `services/linkding/default.nix`, adapting to the new repo's structure
- [ ] 3.2 Define `_class = "clan.service"`, `manifest`, and `roles.server` with interface options (domain, oidc.enable, oidc.issuerDomain)
- [ ] 3.3 Implement server `perInstance` with OCI container, Caddy, PostgreSQL, clan vars generators for db password and OIDC secrets

## 4. Linkding Client Role — Interface

- [ ] 4.1 Define `roles.client` with `options.clients` as `attrsOf clientSubmodule`
- [ ] 4.2 Define clientSubmodule options with normalized names matching downstream modules: `name`, `base_url`, `default_tags`, `cli.enabled`, `claude-code.skill.enabled`, `claude-code.mcp.enabled`, `claude-code.profiles`, `agent-skills.enabled`, `agent-deck.mcp.enabled`, `openclaw.skill.enabled`, `claude-tools.enabled`
- [ ] 4.3 Add per-client clan vars generators for API tokens (`agentplot-linkding-${clientName}-api-token` with prompt type "hidden")

## 5. Phase 1 — CLI + Claude Code Delegation

- [ ] 5.1 Move linkding-cli base package from agentplot-kit to `services/linkding/packages/linkding-cli/` (the generic restish wrapper, unchanged)
- [ ] 5.2 Move linkding SKILL.md from agentplot-kit to `services/linkding/skills/SKILL.md` (template source)
- [ ] 5.3 Implement per-client CLI wrapper: `writeShellApplication` that exports `LINKDING_API_TOKEN` (from clan vars path) and `LINKDING_BASE_URL` (from settings), then execs base linkding-cli. Binary name = client's `name`
- [ ] 5.4 Implement per-client SKILL.md generation: `pkgs.writeText` substituting the client-specific CLI name into the skill template
- [ ] 5.5 Implement programs.claude-code delegation: `skills.<client-name>` (generated SKILL.md path), `mcpServers.<client-name>`, and per-profile `profiles.<profile>.mcpServers.<client-name>` based on enable flags
- [ ] 5.6 Wire all Phase 1 delegation output through `config.agentplot.hmModules.linkding-${clientName}` using deferredModule, capturing clan vars paths in perInstance closure

## 6. Phase 2 — Remaining Downstream Modules

- [ ] 6.1 Implement programs.agent-skills delegation: register `path`-based source, select skill via `explicit` with `packages` (client CLI wrapper) and `transform` for CLI name substitution, enable `targets.claude`
- [ ] 6.2 Implement programs.agent-deck delegation: add MCP entry to `mcps.<client-name>` (freeform attrs)
- [ ] 6.3 Implement programs.openclaw delegation: append skill entry to `skills` list with mode and content
- [ ] 6.4 Implement programs.claude-tools delegation: add to `skillsByClient` (attrsOf mode) or `claude-plugins.plugins`

## 7. Integration and Migration

- [ ] 7.1 Update agentplot-kit: remove linkding-cli package, linkding skill, and linkding entry from env-contract.nix; remove paperless-cli package and paperless skill (these move to agentplot with their future clanService); keep generic tooling only (HM modules, restish/secretspec/recutils/lobster/evernote-convert skills); update flake.nix outputs
- [ ] 7.2 Add agentplot as flake input to swancloud/clan-lol, update inventory to reference `input = "agentplot"` for linkding
- [ ] 7.3 Import `agentplot.nixosModules.agentplot` (or `darwinModules.agentplot`) in machine configs, set `agentplot.user = "chuck"`
- [ ] 7.4 Configure linkding client role in inventory with personal and business clients
- [ ] 7.5 Run `clan vars generate` to set API tokens for both clients
- [ ] 7.6 Test: verify CLI wrappers, skills, and MCP entries are present after build (Phase 1)
- [ ] 7.7 Test: verify agent-skills, agent-deck, openclaw, and claude-tools integrations (Phase 2)
