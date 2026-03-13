---
name: secretspec
description: Manage 1Password secrets for Docker services using SecretSpec. Use when setting up a new service, adding secrets, or verifying secret configuration.
---

# SecretSpec: Service Secret Management

Manage secrets for Docker Compose services using 1Password and SecretSpec.

## Vault Architecture

| Vault | Purpose | Used By |
|-------|---------|---------|
| **LoomOS-Services** | All Docker Compose service secrets | Docker services (linkding, paperless, etc.) |
| **Agent-Secrets** | MCP server keys and AI API keys | Claude Code, Vibe Kanban, OpenClaw agents |
| **Employee** | SA tokens only (bootstrap for headless auth) | User account only |

**Rule**: Docker service secrets always go in **LoomOS-Services**. Agent/MCP secrets go in **Agent-Secrets**. Never mix them.

### Two-Token Architecture

| Token | Vault Access | Used By |
|-------|-------------|---------|
| **SA: LoomOS Services** | LoomOS-Services (R) | Docker services via `mkDockerService` |
| **SA: LoomOS** | LoomOS-Services (R/W) + Agent-Secrets (R/W) | Vibe Kanban, OpenClaw |

Both SA tokens are stored in the **Employee** vault and cached in the macOS Data Protection
Keychain via SecretSpec's `keyring://` provider. A dedicated `secretspec.toml` at
`~/.config/secretspec/sa-tokens/` declares `OP_SA_AGENT_READWRITE` and `OP_SA_SERVICES_READONLY`.
At service start, the token is retrieved via `secretspec get --provider keyring --profile default`,
then `secretspec run` uses `OP_SERVICE_ACCOUNT_TOKEN` headlessly.

## Item Naming Convention

Items in the LoomOS-Services vault use `{service-name} - {secret-name}` format:
- `linkding - Superuser`
- `paperless - PostgreSQL`

The ` - ` separator avoids conflicts with the `op://vault/item/[section/]field` URI format.

## Workflow: Setting Up Secrets for a New Service

### Step 1: Create secretspec.toml

In the service directory (e.g., `services/myservice/`), create `secretspec.toml`:

```toml
[project]
name = "myservice"
revision = "1.0"

[profiles.default]
DB_PASSWORD = { description = "Database password (generate in 1Password)", required = true }
API_KEY = { description = "External API key (known value)", required = true }
```

### Step 2: Generate Passwords in 1Password

For secrets that need **generated** passwords (database passwords, cookie secrets, encryption keys):

```bash
op item create --vault="LoomOS-Services" \
  --title="myservice - DB Password" \
  --category=password \
  --generate-password='letters,digits,symbols,32'
```

**Important**: Generate passwords BEFORE running `secretspec check`. 1Password's generator produces high-quality random values.

### Step 3: Set Known-Value Secrets

For secrets with known values (API keys from external services):

```bash
secretspec set API_KEY "the-known-value"
```

Or create directly in 1Password:

```bash
op item create --vault="LoomOS-Services" \
  --title="myservice - External API Key" \
  --category=password \
  'credential=the-known-value'
```

### Step 4: Verify All Secrets

```bash
cd services/myservice/
secretspec check
```

All secrets should show as present. Fix any missing ones before proceeding.

### Step 5: Test

Docker services are managed by launchd via `mkDockerService.nix`. The service start script
retrieves the read-only SA token from SecretSpec's keyring and sets
`OP_SERVICE_ACCOUNT_TOKEN`, then runs `secretspec run -- docker compose up`
headlessly. To test manually:

```bash
# Set the read-only service account token (from SecretSpec keyring)
export OP_SERVICE_ACCOUNT_TOKEN="$(cd ~/.config/secretspec/sa-tokens && secretspec get --provider keyring --profile default OP_SA_SERVICES_READONLY)"
secretspec run --profile default -- docker compose up
```

## Adding Secrets to Agent Environments

Agent environment secrets (MCP servers, API keys, coordinator tokens) are managed through `toolDefs` in `modules/home/dev/mcp-servers.nix`. Each entry declares secrets and tags that control which consumer environments receive them.

### The toolDefs Entry Format

To inject a secret into agent/coordinator environments without running an MCP server, add a coordinator-only entry:

```nix
# In toolDefs attrset in modules/home/dev/mcp-servers.nix
my-api = {
  package = null;   # No binary to install
  mcp = null;       # No MCP server process
  env = { };        # No extra env vars
  secrets = {
    MY_API_KEY = "Description of this API key";
  };
  tags = [ "claude" "dev" ];  # See tag selection table below
};
```

For MCP servers that also need secrets, use the same pattern but with `mcp` and optionally `package` set.

### Tag Selection Guide

Tags determine which consumer environments receive the secret. A secret matches a consumer if **any** of its tags appears in the consumer's tag set.

| I need this secret in... | Add tag(s) | Flows to secretspec.toml |
|---|---|---|
| Claude Code / Claude Desktop (interactive) | `"claude"` | `~/.config/secretspec/mcp/` |
| Vibe Kanban spawned agents | `"agent"` | `~/.config/secretspec/agent-mcp/` |
| Vibe Kanban coordinator process | `"dev"` | `~/.config/secretspec/vibe-kanban/` |
| OpenClaw coordinator process | `"loomos"` | `~/.config/secretspec/openclaw/` |
| All interactive + agent MCP environments | `"claude"` | both `mcp/` and `agent-mcp/` |
| Interactive + Vibe Kanban coordinator | `"claude"`, `"dev"` | `mcp/`, `agent-mcp/`, and `vibe-kanban/` |

**Note**: The `agent-mcp` consumer collects secrets with either `"claude"` or `"agent"` tags. So adding `"claude"` gives you both interactive and agent MCP coverage.

### Verifying Tag Assignment

After adding or modifying a `toolDefs` entry, run:

```bash
secretspec-status
```

This prints a table showing every secret and which consumer environments it flows into. Verify your new secret appears with checkmarks in the expected columns.

## Adding Restish API Credentials

For services accessed via restish (e.g., Paperless, Linkding), use the coordinator-only pattern with `mcp = null`. The secret is an API token used by restish for REST API calls.

```nix
# Example: adding a restish API credential
my-service-api = {
  package = null;
  mcp = null;
  env = { };
  secrets = {
    MY_SERVICE_API_TOKEN = "API token for restish my-service commands";
  };
  # "claude" for interactive restish use, plus any coordinator tags needed
  tags = [ "claude" ];
};
```

The corresponding restish API registration (in `modules/home/loomos/tools.nix`) uses the env var in its auth header. See the **restish** skill for `apis.json` configuration details.

**Typical tag choices for restish credentials:**
- `["claude"]` — Interactive restish use only (human from terminal)
- `["claude", "dev"]` — Interactive + Vibe Kanban coordinator (agents can also use restish)
- `["claude", "loomos"]` — Interactive + OpenClaw coordinator

## Quick Reference

| Task | Command |
|------|---------|
| Check all secrets populated | `secretspec check` |
| Check all services at once | `secretspec-check-all` |
| View secret-to-environment mapping | `secretspec-status` |
| Set a known-value secret | `secretspec set SECRET_NAME value` |
| Generate password in 1Password | `op item create --vault=LoomOS-Services --title="svc - Name" --category=password --generate-password` |
| List items in LoomOS-Services vault | `op item list --vault=LoomOS-Services` |
| Read a specific secret | `op read "op://LoomOS-Services/svc - Name/credential"` |
