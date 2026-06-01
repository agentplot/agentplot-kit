# agentplot-kit

Nix flake providing CLI packages, Home Manager modules, environment contracts, and agent skills for self-hosted services.

## Quick Start

```nix
# flake.nix
{
  inputs.agentplot-kit.url = "github:agentplot/agentplot-kit";

  outputs = { agentplot-kit, ... }: {
    # Use packages
    # agentplot-kit.packages.${system}.linkding-cli

    # Use Home Manager modules
    # agentplot-kit.homeManagerModules.secretspec
    # agentplot-kit.homeManagerModules.claude-code
    # agentplot-kit.homeManagerModules.uxc
  };
}
```

## Home Manager Modules

### claude-code

Drop-in replacement for the [upstream Claude Code HM module](https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix) — all existing `programs.claude-code` config works unchanged. Disable the upstream module and import this one to gain multi-profile support, structured agent definitions, and more.

**Migration from upstream:**
```nix
{
  disabledModules = [ "programs/claude-code.nix" ];
  imports = [ inputs.agentplot-kit.homeManagerModules.claude-code ];
  # Existing programs.claude-code config works as-is
}
```

**Added over upstream:**
- `configDir` — relocate the config directory (default `.claude`)
- `profiles` — multiple config directories for identity isolation (e.g., agent-deck profiles)
- `agents` accepts both upstream format (strings/paths) and structured attrsets with typed `description`, `proactive`, `tools`, `model`, `permissionMode`, `prompt` (auto-generates YAML frontmatter)
- `dangerouslySkipPermissions` — wraps the binary with `--dangerously-skip-permissions`
- `channels` — generate ad-hoc `claude-<name>` launchers that start a profile with `--channels plugin:<spec>` (Claude Code channels research preview); the main `claude` binary stays untouched
- `rules`, `outputStyles`, `skills` — additional content options not yet in upstream

```nix
programs.claude-code = {
  enable = true;

  # Default profile (~/.claude/)
  settings.permissions.defaultMode = "bypassPermissions";

  # Structured agent (auto-generates frontmatter)
  agents.code-reviewer = {
    description = "Expert code review specialist";
    proactive = true;
    tools = [ "Read" "Grep" ];
    prompt = "You are an expert code reviewer.";
  };

  # Upstream-compatible agent (plain string with your own frontmatter)
  agents.simple = ''
    ---
    name: simple
    description: A simple agent
    ---

    You are a simple agent.
  '';

  # Additional profiles — separate config dirs, separate identities
  profiles.business = {
    configDir = ".claude-business";
    settings.permissions.defaultMode = "default";
  };

  # Ad-hoc channel launcher — `claude-discord` starts the business profile
  # with the Discord channel bridge; plain `claude` is unaffected.
  channels.discord = {
    plugin = "discord@claude-plugins-official";
    profile = "business";
  };
};
```

### secretspec

Declarative [secretspec](https://secretspec.dev) configuration. Installs the CLI and writes `config.toml` to the platform-appropriate path.

```nix
# In your Home Manager config:
programs.secretspec = {
  enable = true;
  settings.defaults = {
    profile = "my_vault";
    provider = "onepassword";
    providers = {
      my_vault = "onepassword://My-Vault";
      keyring = "keyring://";
    };
  };
};
```

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Install secretspec and write config |
| `package` | package | Override the secretspec package |
| `settings` | TOML attrset | Contents of `config.toml` |

Config path: `~/Library/Application Support/secretspec/config.toml` (macOS) or `~/.config/secretspec/config.toml` (Linux).

### uxc

Declaratively owns [UXC](https://github.com/holon-run/uxc)'s on-disk state. `programs.uxc.*` is the single merge surface for both first-party service projections (written by `mkClientTooling`) and consumer-declared third-party endpoints. When enabled it writes `~/.uxc/credentials.json` and `~/.uxc/auth_bindings.json` (mode `0600`) and installs one link-shim executable per `programs.uxc.links` entry. It does **not** install the `uxc` binary (provide it via homebrew / cargo / nixpkgs) and never touches `~/.uxc/cache` or daemon state. Minimum supported UXC: **≥ 0.16**.

```nix
programs.uxc = {
  enable = true;
  # Third-party endpoint with no auth — just a link shim.
  links.deepwiki = { host = "https://mcp.deepwiki.com/mcp"; };
  # Env-token endpoint — inject the ambient token at call time.
  links.context7 = {
    host = "command:${pkgs.nodejs}/bin/npx -y @upstash/context7-mcp@latest";
    injectEnv.CONTEXT7_API_KEY = "$CONTEXT7_API_KEY";
  };
};
```

Duplicate link names or credential ids across the merged set fail at eval time.

## UXC Projection

`mkClientTooling` projects a service's `mcp` and `openapi` endpoints into UXC's
credentials / bindings / link shims when a client sets `uxc.enabled = true`. Each
endpoint names its credential with an explicit `auth = { secret; type; }` block;
the referenced secret must be an `op`-mode secret (resolved by the `op` CLI at call
time, never written to disk).

```nix
roles.client.inherit (mkClientTooling {
  serviceName = "atomic";
  capabilities = {
    secret = [
      { name = "admin-token"; mode = "op"; reference = "op://Personal/Atomic/token"; }
    ];
    mcp = {
      type = "http";
      urlTemplate = client: "https://${client.domain}/mcp";
      auth = { secret = "admin-token"; type = "bearer"; };
      skill = ./skills/mcp;        # wrapper skill (D15 gate)
    };
    openapi = {
      host = client: client.domain;          # string OR fn-of-clientSettings
      pathPrefix = "/api";
      schemaSource = { type = "static"; path = ./openapi.json; };
      auth = { secret = "admin-token"; type = "bearer"; };
      skill = ./skills/openapi;
    };
  };
  extraClientOptions = { lib, ... }: {
    domain = lib.mkOption { type = lib.types.str; description = "FQDN of the Atomic server"; };
  };
}) interface perInstance;
```

With `uxc.enabled = true` on the `personal` client this yields:

- `credentials.json`: one `agentplot-atomic-personal-admin-token` (`bearer`, `op://…`)
- `auth_bindings.json`: two bindings (`…-mcp` `/mcp`, `…-openapi` `/api`) sharing that credential
- link shims `atomic-mcp-cli` and `atomic-openapi-cli` on `$PATH`

A client may enable `uxc.enabled` and `claude-code.mcp.enabled` together; set
`mcp.viaUxcInClaudeCode = true` to make the claude-code `mcpServers` entry target
`uxc` as a stdio command instead of a file-token wrapper.

### 1Password prerequisite

`op`-mode secrets are resolved at call time by the `op` CLI. Each user needs either
`OP_SERVICE_ACCOUNT_TOKEN` exported in their shell (headless) or an interactive
`op signin`. A bad `op://` reference fails the first `uxc` call, not the Nix build —
probe with `uxc auth credential show <id>` before first use.

### Dual-secret migration pattern

`op` secrets have no file path, so they cannot feed `cli.envVars` or a claude-code
file-token MCP wrapper. A service migrating a legacy CLI alongside UXC declares two
secrets — one `op` for UXC, one `prompted`/`shared` for the file consumer — and drops
the file secret once the legacy wrapper retires. See
`openspec/changes/mkclienttooling-uxc-support/mockups/paperless.example.nix`.

### Wrapper skills

Every UXC-projectable endpoint must ship a wrapper skill (`SKILL.md`,
`agents/openai.yaml`, `references/usage-patterns.md`, `scripts/validate.sh`), gated at
eval time (D15). Author one with `nix run .#author-skill -- <service> <protocol>`
(requires `ANTHROPIC_API_KEY`); the recipe LLM-authors the skill, runs
`scripts/validate.sh` with up to 3 retries, and writes a `.source-spec-hash` sidecar.
`nix flake check` runs each committed skill's `validate.sh` and verifies the spec hash.

For MCP services with no formal OpenAPI spec, capture a fixture instead and hash that:

```bash
uxc <host>/mcp -h > services/<svc>/skills/mcp/fixtures/help-output.txt
nix run .#author-skill -- <svc> mcp
```

## CLI Packages

Thin [restish](https://rest.sh)-based wrappers with OpenAPI auto-discovery. Each reads credentials from environment variables.

| Package | Service | Required Env |
|---------|---------|-------------|
| `linkding-cli` | [Linkding](https://github.com/sissbruecker/linkding) bookmarks | `LINKDING_API_TOKEN`, `LINKDING_BASE_URL` |
| `paperless-cli` | [Paperless-ngx](https://docs.paperless-ngx.com) documents | `PAPERLESS_API_TOKEN`, `PAPERLESS_BASE_URL` |

## Environment Contracts

`lib.envContract` declares what each service needs, separating secrets from public config:

```nix
agentplot-kit.lib.envContract.linkding
# => { secrets = [ "LINKDING_API_TOKEN" ]; env = [ "LINKDING_BASE_URL" ]; }
```

## Skills

Agent skills in `skills/` provide operational knowledge for AI coding agents (Claude Code, etc.):

| Skill | Purpose |
|-------|---------|
| linkding | Manage bookmarks, tags, bundles via REST API |
| paperless | Manage documents, mail rules, tags, workflows |
| restish | Generic REST API client with OpenAPI auto-discovery |
| secretspec | Secret management patterns with 1Password |
| lobster | Workflow automation with OpenClaw engine |
| recutils | Plain-text relational databases for agent state |
| evernote-convert | Migrate Evernote exports to Paperless-ngx |

## License

MIT
