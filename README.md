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
  };
}
```

## Home Manager Modules

### claude-code

Fork of the [official Claude Code HM module](https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix) with multi-profile support and structured agent definitions. Consumers must choose this **or** the upstream module — both use the `programs.claude-code` namespace.

**Added over upstream:**
- `configDir` — relocate the config directory (default `.claude`)
- `profiles` — multiple config directories for identity isolation (e.g., agent-deck profiles)
- Structured `agents` submodule with typed `description`, `proactive`, `tools`, `model`, `permissionMode`, `prompt` (generates YAML frontmatter automatically)
- `dangerouslySkipPermissions` — wraps the binary with `--dangerously-skip-permissions`

```nix
programs.claude-code = {
  enable = true;

  # Default profile (~/.claude/)
  settings.permissions.defaultMode = "bypassPermissions";

  agents.code-reviewer = {
    description = "Expert code review specialist";
    proactive = true;
    tools = [ "Read" "Grep" ];
    prompt = "You are an expert code reviewer.";
  };

  # Additional profiles — separate config dirs, separate identities
  profiles.business = {
    configDir = ".claude-business";
    settings.permissions.defaultMode = "default";
  };
};
```

All upstream options are preserved: `settings`, `commands`, `hooks`, `rules`, `skills`, `outputStyles`, `memory`, `mcpServers`, `enableMcpIntegration`, and all `*Dir` variants.

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

## CLI Packages

Thin [restish](https://rest.sh)-based wrappers with OpenAPI auto-discovery. Each reads credentials from environment variables.

| Package | Service | Required Env |
|---------|---------|-------------|
| `linkding-cli` | [Linkding](https://github.com/sissbruecker/linkding) bookmarks | `LINKDING_API_TOKEN`, `LINKDING_BASE_URL` |
| `pocket-id-cli` | [Pocket ID](https://pocket-id.org) OIDC provider | `POCKET_ID_API_KEY`, `POCKET_ID_BASE_URL` |
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
| pocket-id | Manage OIDC clients, users, groups, API keys |
| restish | Generic REST API client with OpenAPI auto-discovery |
| secretspec | Secret management patterns with 1Password |
| service-auth-setup | Provision OIDC auth for new services |
| lobster | Workflow automation with OpenClaw engine |
| recutils | Plain-text relational databases for agent state |
| evernote-convert | Migrate Evernote exports to Paperless-ngx |

## License

MIT
