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
  };
}
```

## Home Manager Modules

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
