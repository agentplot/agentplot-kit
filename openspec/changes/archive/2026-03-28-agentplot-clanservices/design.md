## Context

Today, agent tooling for services like linkding is spread across two repositories and requires manual wiring:

- **swancloud** has the linkding clanService (server infrastructure in a microVM)
- **agentplot-kit** has the linkding CLI, skill, env-contract, and Home Manager modules

Consumers must independently configure each piece. There's no declarative way to say "give this machine linkding with CLI + skill + MCP + agent-deck integration" and have it wired automatically.

Five existing Home Manager modules handle the downstream targets:
1. **programs.claude-code** (agentplot-kit) — skills, MCP servers, agents, profiles with configDir isolation
2. **programs.agent-skills** (Kyure-A/agent-skills-nix) — skill discovery, bundling, and deployment to 8+ agent platforms
3. **programs.agent-deck** (codecorral/nix-agent-deck) — config.toml generation with freeform `mcps` and `tools` sections
4. **programs.openclaw** (openclaw/nix-openclaw) — skills (inline/symlink/copy modes), plugins, instances, schema-typed config
5. **programs.claude-tools** (mreimbold/claude-plugins-nix) — marketplace plugin and skill installation via activation scripts

Clan's `perInstance` returns both `nixosModule` and `darwinModule`. Client tooling is Home Manager-shaped. The existing openclaw clanService solves this by hardcoding `home-manager.users.chuck` / `home-manager.users.openclaw` in separate module outputs, creating platform-specific code paths.

## Goals / Non-Goals

**Goals:**
- Create `agentplot/agentplot` repository with clanServices that co-locate server infrastructure, client tooling, packages, and skills
- Design a reusable HM passthrough pattern that any agentplot clanService can use — no hardcoded usernames, works on NixOS and nix-darwin
- Implement linkding as the first clanService with server role (from swancloud) and client role (new)
- Support multi-client configuration: one server, multiple named client configs on the same machine (personal/business partitioning)
- Client role delegates to all 5 downstream HM modules based on per-client enable flags
- Secrets managed through clan vars/sops (auto-generated where possible, prompted where not)

**Non-Goals:**
- Modifying clan-core — this is a pattern built on top of existing Clan capabilities
- Modifying any of the 5 downstream HM modules — we write into their existing interfaces
- Migrating all services at once — linkding is the proof-of-concept; others follow the pattern

## Decisions

### 1. HM Modules Passthrough via NixOS Option Namespace

**Decision**: clanService client roles accumulate Home Manager modules into `config.agentplot.hmModules.<key>` (type: `attrsOf deferredModule`). A separate adapter module reads `agentplot.user` and wires all accumulated HM modules into `home-manager.users.${agentplot.user}`. The adapter module is exported as both `nixosModules.agentplot` and `darwinModules.agentplot` (same file) for discoverability.

**Rationale**: This decouples the clanService from the username and platform. The clanService just produces HM modules; the consumer decides which user receives them. Multiple clanServices compose naturally — each adds to `agentplot.hmModules` and they all merge at the user level. Single-user (`agentplot.user`) is sufficient — don't over-engineer with multi-user support.

**Important implementation detail**: The deferred HM modules capture NixOS-level values (like clan vars secret paths) via closure in the perInstance block. Secret paths must be interpolated into strings *before* entering the deferredModule — the deferred module's `config` arg refers to HM config, not NixOS config. The existing swancloud patterns (resolving paths in `let` blocks) are the correct approach.

**Alternative considered**: Direct `home-manager.users.X` in perInstance (current openclaw approach). Rejected because it hardcodes the username and doesn't compose across services.

**Alternative considered**: Standalone HM modules outside Clan (Option C from exploration). Rejected because the user wants client config in Clan inventory with clan vars/sops for secrets.

**Dependency**: Requires HM NixOS/nix-darwin integration module (not standalone HM). `home-manager.users` must exist at the NixOS/darwin config level.

### 2. Named Clients Within a Single Client Role

**Decision**: The client role interface has `options.clients = attrsOf clientSubmodule` where each client has a `name`, `base_url`, and enable flags for each downstream integration. One Clan instance, one server, one client role entry per machine, multiple named client configs.

**Rationale**: Avoids the combinatorial explosion of multiple Clan instances for personal/business partitioning. The `clients` attrset maps naturally to `lib.mapAttrsToList` in the perInstance implementation, generating distinct CLI names, env vars, skills, and MCP entries per client.

**Alternative considered**: Multiple Clan instances (one per client config). Rejected because it requires either multiple servers or server-less client instances, and the per-machine key uniqueness constraint makes it awkward.

### 3. Repository Structure: Service-Centric Layout

**Decision**: Each clanService in agentplot is a self-contained directory:

```
agentplot/
  modules/
    agentplot.nix                # adapter module (agentplot.user + agentplot.hmModules)
    caddy-cloudflare.nix         # shared TLS module (moved from swancloud)
  services/
    microvm/
      default.nix                # microVM host/guest clanService (moved from swancloud)
    linkding/
      default.nix                # clanService definition (_class = "clan.service")
      skills/
        SKILL.md                 # skill content (moved from agentplot-kit)
      packages/
        linkding-cli/
          default.nix            # CLI wrapper (moved from agentplot-kit)
          openapi.json           # bundled OpenAPI spec
```

Note: `services/<name>/` maps to `clanModules.<name>` in flake outputs. This mapping is explicit in flake.nix. The microvm clanService is generic infrastructure — it may move upstream of agentplot later.

**Rationale**: Co-locating the skill, package, and service definition makes the service self-contained. When the perInstance generates HM config, it can reference `./skills/SKILL.md` directly.

### 4. Delegation Strategy Per Downstream Module

All five downstream modules are implemented together — each enable flag independently controls its delegation, so there's no reason to phase.

**programs.claude-code**: Use `skills.<client-name>` for skill content (path to SKILL.md), `mcpServers.<client-name>` for MCP entries, and `profiles.<profile-name>.mcpServers.<client-name>` for profile-specific MCP. Skills and MCP servers are `attrsOf` so multiple clanServices compose via module merging.

**programs.agent-skills**: Register agentplot as a `sources` entry using `path`-based sources (not `input`, to avoid `extraSpecialArgs` complexity). Use `skills.explicit.<client-name>` to select the specific skill with `rename` for multi-client disambiguation. The `packages` option on explicit skills allows associating the client-specific CLI package, and the `transform` function can modify the SKILL.md at installation time to reference the correct package path. Enable the `targets.claude` target (and other targets as configured).

**programs.agent-deck**: Add entries to `mcps.<client-name>` (freeform `attrsOf (attrsOf anything)`). Multiple clanServices can each add their own MCP entries without conflict.

**programs.openclaw**: Append to `skills` list with `mode = "inline"` or `mode = "symlink"` pointing to the co-located SKILL.md. Skills are list-typed, so multiple modules concatenate naturally.

**programs.claude-tools**: Prefer `skillsByClient` (the advanced mode using `attrsOf`) over `globalSkills` (list-typed) for better module merging. Use `claude-plugins.plugins` for marketplace plugins.

### 5. Flexible Secret Management

**Decision**: The client role uses `clan.core.vars.generators` for API tokens, supporting two modes per service:

- **Auto-generated**: When the server can programmatically create API tokens (e.g., via admin API after deployment), the vars generator runs a script that provisions the token automatically. The generator script can use the server's admin credentials (themselves a shared clan var) to create and retrieve the token.
- **Prompted**: When the server requires manual token creation (e.g., logging into a web UI), the vars generator uses `prompts` with `type = "hidden"` to collect the token during `clan vars generate`.

Each clanService declares which mode its server supports. The client role's vars generator dispatches accordingly. Both modes store the result identically via sops, so the client-side HM config doesn't need to know which mode was used.

**Rationale**: Some services (like linkding) have admin APIs that can create tokens programmatically. Others require manual UI interaction. The design should support both without changing the client role interface.

**Per-client secret naming**: `agentplot-linkding-${clientName}-api-token` — each named client gets its own secret, regardless of generation mode.

### 6. Per-Client CLI Wrapper Scripts

**Decision**: Each named client gets its own wrapper script that bakes in the base URL and authentication. The wrapper reads the API token from the clan vars secret file path and sets `LINKDING_API_TOKEN` and `LINKDING_BASE_URL` before delegating to the underlying linkding-cli. The binary name is overridden per client (e.g., `linkding` vs `linkding-biz`).

**Rationale**: Each wrapper is self-contained — it knows its own URL and secret path. No env var namespacing needed; the wrapper handles it. This is simpler than parameterizing env var names in the generic CLI package.

**Implementation**: `pkgs.writeShellApplication` per client, wrapping the base `linkding-cli` with `export LINKDING_API_TOKEN=$(cat ${tokenPath})` and `export LINKDING_BASE_URL=${settings.base_url}` before exec.

## Risks / Trade-offs

**[Risk] `deferredModule` type may not merge cleanly across multiple clanService instances** → Mitigation: Add a composition smoke test early — two clanServices both writing to `agentplot.hmModules` and verifying merge. Fallback: use `lib.types.raw` or `lib.types.attrs` if deferredModule causes evaluation issues.

**[Risk] SKILL.md hardcodes CLI name** → Mitigation: The `programs.agent-skills` `transform` function and `packages` option modify the SKILL.md at installation time to reference the correct per-client CLI package path. For `programs.claude-code` skills, generate per-client SKILL.md via `pkgs.writeText` with CLI name substitution.

**[Risk] `programs.claude-tools` lists don't merge well from multiple modules** → Mitigation: Prefer `skillsByClient` (the advanced `attrsOf` mode) over `globalSkills` (list).

**[Risk] `programs.openclaw.skills` is list-typed, not attrset** → Mitigation: Multiple modules appending to a list works in NixOS module system (lists concatenate). Verify no deduplication issues with same-named skills from different clanServices.

**[Risk] Breaking agentplot-kit consumers when removing linkding-cli** → Mitigation: Phase the migration — first add a re-export from agentplot-kit that points to agentplot, then remove after consumers have migrated. Or just remove and bump the version (agentplot-kit is early enough that a clean break is acceptable).

**[Risk] Breaking swancloud by moving the linkding server role** → Mitigation: Phase the migration — add agentplot as input to swancloud first, verify the server role works from the new location, then remove the old one.

**[Trade-off] One more flake input for consumers** → Acceptable because agentplot is the single entry point for all agent-optimized clanServices, replacing per-service wiring.

**[Trade-off] Consumer must set `agentplot.user` once** → Minimal cost for the benefit of decoupling. Could be eliminated if Clan upstream adds homeManagerModule support to perInstance.

## Resolved Questions

1. **Single-user is sufficient.** `agentplot.user` takes one string. If someone needs multi-user, they wire `agentplot.hmModules` directly.
2. **Profile-specific MCP maps to `programs.claude-code.profiles.<name>.mcpServers`.** This is the natural mapping — profiles have configDir isolation.
3. **Packages and skills move to agentplot.** All service-specific packages (linkding-cli, paperless-cli) and skills (linkding, paperless) move to agentplot, co-located with their clanService. agentplot-kit retains only generic, non-service-specific tooling: HM modules (claude-code, secretspec), generic skills (restish, secretspec, recutils, lobster, evernote-convert), and lib/env-contract.nix (which loses service entries as they migrate).
