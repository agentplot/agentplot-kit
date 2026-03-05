---
name: pocket-id
description: Manage Pocket ID identity provider via the admin API. Use when creating or managing OIDC clients, users, user groups, API keys, custom claims, application config, audit logs, or signup tokens.
secrets:
  - POCKET_ID_API_KEY
env:
  - POCKET_ID_BASE_URL
---

# Pocket ID Admin API Skill

Manage the Pocket ID OIDC identity provider via its admin REST API using `pocket-id-cli`.

`pocket-id-cli` wraps restish with the bundled OpenAPI spec, so all endpoints are auto-discovered as typed CLI commands.

## Authentication

Authentication is handled via environment variables:
- `POCKET_ID_API_KEY` — Admin API key for authentication
- `POCKET_ID_BASE_URL` — Base URL of the Pocket ID instance

No manual setup is needed — just use the commands below.

## Discovering Available Operations

```bash
# List all operations
pocket-id-cli --help

# Help for a specific operation
pocket-id-cli <operation-id> --help
```

## Pagination

All list endpoints support pagination:

```bash
pocket-id-cli list-clients 'pagination[page]':1 'pagination[limit]':50
pocket-id-cli list-users 'sort[column]':"createdAt" 'sort[direction]':"desc"
```

Response format:
```json
{
  "data": [...],
  "pagination": { "page": 1, "limit": 20, "totalItems": 42, "totalPages": 3 }
}
```

## OIDC Clients

The primary use case — managing OIDC clients for service authentication.

### Idempotent Create Pattern

Always check if a client exists before creating:

```bash
# Search for existing client by name
pocket-id-cli list-clients search="my-service" -f 'body.data'

# If empty, create it
pocket-id-cli create-client \
  name:"my-service" \
  callbackURLs:["https://my-service.example.com/callback"] \
  pkceEnabled:true
```

### CRUD Operations

```bash
# List all OIDC clients
pocket-id-cli list-clients

# Search clients by name
pocket-id-cli list-clients search="paperless"

# Get a specific client
pocket-id-cli get-client <client-id>

# Create a client (minimal)
pocket-id-cli create-client \
  name:"my-service" \
  callbackURLs:["https://service.example.com/callback"]

# Create a client (full options)
pocket-id-cli create-client \
  name:"my-service" \
  callbackURLs:["https://service.example.com/callback"] \
  logoutCallbackURLs:["https://service.example.com/logout"] \
  pkceEnabled:true \
  isPublic:false \
  requiresReauthentication:false \
  isGroupRestricted:false

# Update a client
pocket-id-cli update-client <client-id> \
  name:"updated-name" \
  callbackURLs:["https://new-url.example.com/callback"]

# Delete a client
pocket-id-cli delete-client <client-id>

# Regenerate client secret (returns new secret, shown only once)
pocket-id-cli regenerate-client-secret <client-id>

# Get client metadata (public, no auth required)
pocket-id-cli get-client-meta <client-id>
```

### OIDC Client Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Client display name (required) |
| `callbackURLs` | string[] | Allowed redirect URIs (required) |
| `logoutCallbackURLs` | string[] | Post-logout redirect URIs |
| `isPublic` | bool | Public client (no secret) |
| `pkceEnabled` | bool | Require PKCE |
| `requiresReauthentication` | bool | Force re-auth each time |
| `launchURL` | string | Application launch URL |
| `isGroupRestricted` | bool | Restrict to specific user groups |

## Users

```bash
# List all users
pocket-id-cli list-users

# Search users
pocket-id-cli list-users search="chuck"

# Get a specific user
pocket-id-cli get-user <user-id>

# Create a user
pocket-id-cli create-user \
  username:"newuser" \
  email:"user@example.com" \
  firstName:"New" \
  lastName:"User" \
  isAdmin:false

# Update a user
pocket-id-cli update-user <user-id> \
  firstName:"Updated" \
  isAdmin:true

# Delete a user
pocket-id-cli delete-user <user-id>
```

## User Groups

```bash
# List all groups
pocket-id-cli list-groups

# Create a group
pocket-id-cli create-group \
  name:"developers" \
  friendlyName:"Developers"

# Update a group
pocket-id-cli update-group <group-id> \
  friendlyName:"Senior Developers"

# Delete a group
pocket-id-cli delete-group <group-id>
```

## API Keys

```bash
# List API keys for current user
pocket-id-cli list-api-keys

# Create an API key (token shown only once!)
pocket-id-cli create-api-key \
  name:"Agent Admin" \
  description:"Automated OIDC client management" \
  expiresAt:"2027-01-01T00:00:00Z"

# Revoke an API key
pocket-id-cli revoke-api-key <key-id>
```

## Custom Claims

```bash
# Set claims for a user (replaces all existing claims)
pocket-id-cli set-user-claims <user-id> \
  '[{"key":"role","value":"admin"},{"key":"department","value":"engineering"}]'

# Set claims for a group (replaces all existing claims)
pocket-id-cli set-group-claims <group-id> \
  '[{"key":"tier","value":"premium"}]'
```

## Application Configuration

```bash
# Get all configuration (admin only)
pocket-id-cli get-all-config

# Update configuration
pocket-id-cli update-config \
  appName:"My Pocket ID" \
  sessionDuration:"168h"
```

## Audit Logs

```bash
# List all audit logs (admin only)
pocket-id-cli list-all-audit-logs
```

## Output Formatting

Restish auto-detects output context:
- **Piped/scripted**: outputs raw JSON (agent-friendly)
- **Interactive terminal**: colorized human-readable output

Force specific formats:

```bash
# JSON output
pocket-id-cli list-clients -o json

# Filter specific fields
pocket-id-cli list-clients -f 'body.data.{id, name, callbackURLs}'

# Raw string (no quotes)
pocket-id-cli get-client <id> -f 'body.name' -r
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (2xx) |
| 1 | Unrecoverable error |
| 4 | Client error (4xx) |
| 5 | Server error (5xx) |
