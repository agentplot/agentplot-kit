---
name: paperless
description: Manage Paperless-ngx documents, mail rules, tags, correspondents, and workflows via the REST API. Use when creating or modifying mail rules, querying documents, managing tags/correspondents/document types, or automating document workflows.
secrets:
  - PAPERLESS_API_TOKEN
env:
  - PAPERLESS_BASE_URL
---

# Paperless-ngx API Skill

Manage the Paperless-ngx instance via its REST API using `paperless-cli`.

`paperless-cli` wraps restish and fetches the OpenAPI spec directly from the Paperless instance, so all endpoints are auto-discovered as typed CLI commands.

## Authentication

Authentication is handled via environment variables:
- `PAPERLESS_API_TOKEN` — API token for authentication
- `PAPERLESS_BASE_URL` — Base URL of the Paperless-ngx instance

No manual setup is needed — just use the commands below.

## Command Naming Convention

Restish generates commands from the OpenAPI spec using `noun-verb` format:

```
paperless-cli <resource>-<action> [positional-args] [--flag value] [body-key:value]
```

- **GET query/filter params** use `--flag value` syntax (e.g., `--page-size 5`, `--query "invoice"`)
- **POST/PATCH body params** use `key:value` syntax (e.g., `name:"Acme Corp"`, `tags:[1,3]`)
- **Positional args** (like IDs) go directly after the command (e.g., `documents-retrieve 42`)

When in doubt, run `paperless-cli <command> --help` to see exact syntax.

## Discovering Available Operations

```bash
# List all operations
paperless-cli --help

# Help for a specific operation
paperless-cli <operation-id> --help
```

## Common Operations

### Documents

```bash
# List documents (auto-paginated)
paperless-cli documents-list

# List with page size limit
paperless-cli documents-list --page-size 5

# Search documents by content
paperless-cli documents-list --query "invoice 2024"

# Search documents (simple text search)
paperless-cli documents-list --search "invoice"

# Filter by correspondent
paperless-cli documents-list --correspondent--id 5

# Filter by document type
paperless-cli documents-list --document-type--id 3

# Get a specific document
paperless-cli documents-retrieve 42

# Get document suggestions (AI-generated metadata)
paperless-cli documents-suggestions-retrieve 42

# Upload a document
paperless-cli documents-post-document-create document@/path/to/file.pdf title:"Invoice Jan 2024"

# Update document metadata
paperless-cli documents-partial-update 42 title:"Updated Title" correspondent:5 document_type:3

# Bulk edit documents (set tags, correspondent, etc.)
paperless-cli bulk-edit documents:[1,2,3] method:"set_tags" parameters:{tags:[5,8]}

# Download original document
paperless-cli documents-download-retrieve 42 -o original.pdf

# Get document metadata (checksums, archive info)
paperless-cli documents-metadata-retrieve 42

# View document history
paperless-cli documents-history-list 42
```

### Mail Rules

```bash
# List all mail rules
paperless-cli mail-rules-list

# Get a specific mail rule
paperless-cli mail-rules-retrieve 1

# Create a mail rule
paperless-cli mail-rules-create \
  name:"Vendor Invoices" \
  account:1 \
  folder:"INBOX" \
  filter_from:"billing@vendor.com" \
  filter_subject:"invoice" \
  maximum_age:30 \
  action:3 \
  assign_title_from:1 \
  assign_correspondent_from:2 \
  assign_document_type:5 \
  assign_tags:[1,3] \
  consumption_scope:1 \
  attachment_type:1 \
  order:0

# Update a mail rule
paperless-cli mail-rules-partial-update 1 \
  filter_from:"newemail@vendor.com" \
  enabled:true

# Delete a mail rule
paperless-cli mail-rules-destroy 1
```

#### Mail Rule Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Rule display name (required) |
| `account` | int | Mail account ID (required) |
| `enabled` | bool | Whether rule is active (default: true) |
| `folder` | string | IMAP folder (default: "INBOX") |
| `filter_from` | string | Filter by sender address |
| `filter_to` | string | Filter by recipient |
| `filter_subject` | string | Filter by subject |
| `filter_body` | string | Filter by body content |
| `filter_attachment_filename_include` | string | Include attachments matching pattern |
| `filter_attachment_filename_exclude` | string | Exclude attachments matching pattern |
| `maximum_age` | int | Max email age in days (default: 30) |
| `action` | int | 1=Delete, 2=Move, 3=Mark read, 4=Flag, 5=Tag |
| `action_parameter` | string | Required for Move (folder) and Tag (tag name) actions |
| `assign_title_from` | int | 1=Subject, 2=Filename, 3=None |
| `assign_correspondent_from` | int | 1=None, 2=Address, 3=Name, 4=Specific |
| `assign_correspondent` | int | Correspondent ID (when assign_correspondent_from=4) |
| `assign_document_type` | int | Document type ID |
| `assign_tags` | list[int] | Tag IDs to assign |
| `attachment_type` | int | 1=Attachments only, 2=All files including inline |
| `consumption_scope` | int | 1=Attachments, 2=Full .eml, 3=Both |
| `order` | int | Processing order (lower = first) |

### Mail Accounts

```bash
# List mail accounts
paperless-cli mail-accounts-list

# Get a specific mail account
paperless-cli mail-accounts-retrieve 1
```

### Correspondents

```bash
# List correspondents
paperless-cli correspondents-list

# Create a correspondent
paperless-cli correspondents-create name:"Acme Corp"

# Update a correspondent
paperless-cli correspondents-partial-update 5 name:"Acme Corporation"

# Delete a correspondent
paperless-cli correspondents-destroy 5
```

### Tags

```bash
# List tags
paperless-cli tags-list

# Create a tag
paperless-cli tags-create name:"vendor-invoice" color:"#ff0000"

# Update a tag
paperless-cli tags-partial-update 3 name:"invoice"

# Delete a tag
paperless-cli tags-destroy 3
```

### Document Types

```bash
# List document types
paperless-cli document-types-list

# Create a document type
paperless-cli document-types-create name:"Vendor Invoice"
```

### Storage Paths

```bash
# List storage paths
paperless-cli storage-paths-list

# Create a storage path
paperless-cli storage-paths-create name:"Invoices" path:"invoices/{correspondent}/{created_year}"
```

### Saved Views

```bash
# List saved views
paperless-cli saved-views-list
```

### Custom Fields

```bash
# List custom fields
paperless-cli custom-fields-list
```

### Workflows

```bash
# List workflows
paperless-cli workflows-list

# List workflow triggers
paperless-cli workflow-triggers-list

# List workflow actions
paperless-cli workflow-actions-list
```

### System

```bash
# System statistics
paperless-cli statistics-retrieve

# System status
paperless-cli status-retrieve

# List background tasks
paperless-cli tasks-list

# Search with autocomplete
paperless-cli search-autocomplete-list --term "invoice"

# Global search
paperless-cli search-retrieve --query "vendor invoice 2024"

# Trash management
paperless-cli trash-list
```

## Output Formatting

Restish auto-detects output context:
- **Piped/scripted**: outputs raw JSON (agent-friendly)
- **Interactive terminal**: colorized human-readable output

Force specific formats:

```bash
# JSON output
paperless-cli documents-list -o json

# Filter specific fields
paperless-cli documents-list -f 'body.results.{id, title, correspondent}'

# Raw string (no quotes)
paperless-cli documents-retrieve 42 -f 'body.title' -r
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (2xx) |
| 1 | Unrecoverable error |
| 4 | Client error (4xx) |
| 5 | Server error (5xx) |
