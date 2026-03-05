---
name: lobster
description: Use Lobster for workflow automation. Use when creating, running, or organizing Lobster workflow YAML files, or when deciding where workflows should live.
---

# Lobster: Workflow Automation

Lobster is the OpenClaw workflow engine for automating multi-step pipelines.

## Workflow Locations

| Location | Managed By | Purpose |
|----------|-----------|---------|
| `~/.openclaw/workflows/` | mac-nix (Nix) | Shared infrastructure workflows |
| `~/.openclaw/workspace-<agent>/workflows/` | Agent (git) | Agent-specific domain workflows |

### Which Location?

- **Shared** (`~/.openclaw/workflows/`): Infrastructure utilities used by multiple agents or the system itself. Deployed declaratively by Nix. Changes require a mac-nix rebuild.
- **Agent-specific** (`workspace-<agent>/workflows/`): Domain logic owned by a single agent. Agents can iterate without mac-nix changes. Lives in the agent's git repo.

**Rule of thumb**: If it's about *how the system works*, it's shared. If it's about *what an agent does*, it's agent-specific.

### Examples

| Workflow | Location | Reason |
|----------|----------|--------|
| `sync-paperless-mail-rules.yaml` | Agent workspace | Syncs vendor config to Paperless — domain logic |
| `workspace-git-sync.yaml` | Shared | Infrastructure: keeps agent workspaces backed up |
| `invoice-check.yaml` | Agent workspace | Agent's invoice processing — domain logic |

## Running Workflows

```bash
# Run a shared workflow by absolute path
lobster run --file ~/.openclaw/workflows/workspace-git-sync.yaml

# Run an agent workflow from the workspace directory
cd ~/.openclaw/workspace-jared
lobster run --file workflows/invoice-check.yaml

# Run with variables
lobster run --file workflows/sync-rules.yaml --var vendor="Acme Corp"
```

## Creating Workflows

Workflow files are YAML. Minimal example:

```yaml
name: example-workflow
description: Brief description of what this does

steps:
  - name: fetch-data
    action: exec
    command: recsel -t Vendor -e 'Phase = "Active"' invoices.rec

  - name: process
    action: exec
    command: restish paperless list-mail-rules -o json
```

## Conventions

- Use kebab-case for workflow filenames: `sync-paperless-mail-rules.yaml`
- Include `name` and `description` fields at the top
- Keep workflows focused — one pipeline per file
- Agent workflows should be committed to the agent's git repo
- Shared workflows are deployed by Nix via `home.file` entries in openclaw.nix
