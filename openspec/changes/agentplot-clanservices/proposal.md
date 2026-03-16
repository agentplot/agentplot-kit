## Why

agentplot-kit currently provides agent tooling (CLIs, skills, HM modules) as standalone flake outputs, while infrastructure (clanServices) lives separately in swancloud. There's no unified way to declare "I want linkding with CLI, skill, MCP, and agent-deck integration on this machine" — consumers must wire each piece independently. We need a new `agentplot` repository that defines clanServices where the **server role** deploys infrastructure and the **client role** declaratively installs all agent tooling by delegating to existing Home Manager modules.

The key challenge: Clan's `perInstance` returns a `nixosModule`, but client tooling is Home Manager-shaped and shouldn't hardcode a username. We solve this with an **HM config passthrough pattern** — the clanService accumulates HM config into a NixOS option namespace (`agentplot.hmModules`), and a small adapter module wires it into `home-manager.users.${agentplot.user}`.

## What Changes

- **New repository**: `agentplot/agentplot` on GitHub — houses clanServices optimized for agent consumption
- **New NixOS/darwin adapter module**: `agentplot.user` + `agentplot.hmModules` — the bridge between Clan's nixosModule output and Home Manager
- **New clanService**: `linkding` with server role (moved from swancloud) and client role (new)
- **Client role with named clients**: A single client role supporting `clients = { personal = { ... }; business = { ... }; }` for multi-instance partitioning on one machine
- **HM delegation**: Client role generates config for 5 downstream HM modules:
  - `programs.claude-code` (agentplot-kit) — skills, MCP servers, agents per profile
  - `programs.agent-skills` (Kyure-A/agent-skills-nix) — skill distribution to multiple agent platforms
  - `programs.agent-deck` (codecorral/nix-agent-deck) — MCP and tool entries in config.toml
  - `programs.openclaw` (openclaw/nix-openclaw) — skills and plugin config
  - `programs.claude-tools` (mreimbold/claude-plugins-nix) — marketplace plugin installation
- **Packages and skills relocated**: linkding-cli and linkding skill move from agentplot-kit into agentplot, co-located with the clanService

## Capabilities

### New Capabilities
- `agentplot-hm-passthrough`: The NixOS/darwin adapter module pattern — `agentplot.user`, `agentplot.hmModules` namespace, and the wiring that connects Clan perInstance output to Home Manager without hardcoding usernames
- `clanservice-linkding`: The linkding clanService with server role (infrastructure) and client role (multi-client agent tooling delegation)
- `client-role-delegation`: The pattern by which a clanService client role generates configuration for downstream HM modules (claude-code, agent-skills, agent-deck, openclaw, claude-tools)

### Modified Capabilities
<!-- None — this is a new repository with new capabilities -->

## Impact

- **New repository**: `agentplot/agentplot` created on GitHub under the agentplot org
- **swancloud**: linkding clanService server role migrated out; swancloud inventory updated to reference `agentplot` input
- **agentplot-kit**: linkding-cli package and linkding skill removed (moved to agentplot); env-contract updated; generic tooling (restish, secretspec, recutils, lobster skills; claude-code and secretspec HM modules) remains
- **Flake inputs**: Consumers need `agentplot` as a flake input; agentplot itself needs `agentplot-kit`, `agent-skills-nix`, `claude-plugins-nix`, `nix-agent-deck`, `nix-openclaw` as inputs
- **Secrets**: Server role uses clan vars/sops for infrastructure secrets; client role uses clan vars for API tokens (prompted during `clan vars generate`)
- **Downstream HM modules**: No changes required — agentplot writes into their existing option interfaces
