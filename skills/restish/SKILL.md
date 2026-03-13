---
name: restish
description: Use restish to interact with any REST API. Restish auto-discovers endpoints from OpenAPI specs and generates CLI commands with zero manual maintenance. Use when making API calls, registering new APIs, or querying REST services.
---

# Restish: REST API Client

Restish is a CLI for interacting with REST APIs. It reads OpenAPI specs and auto-generates typed commands for every endpoint. When an API adds new endpoints, they appear automatically.

## Pre-Configured APIs

Agent Plot provides self-contained CLI wrappers for managed services:

| CLI | Service | Auth |
|-----|---------|------|
| `linkding-cli` | Linkding bookmark manager | `$LINKDING_API_TOKEN` |
| `paperless-cli` | Paperless-ngx document manager | `$PAPERLESS_API_TOKEN` |

Use the service-specific skills (linkding, paperless) for detailed guidance. This skill covers restish itself.

## Discovering Operations

```bash
# List all operations for a registered API
restish <api-name> --help

# Help for a specific operation
restish <api-name> <operation-id> --help

# Refresh the cached OpenAPI spec
restish api sync <api-name>
```

## Registering a New API

### Interactive Setup

```bash
restish api configure <name> <base-url>
```

### Auth Methods

**Header-based** (most common):
```json
"profiles": { "default": { "headers": { "Authorization": "Bearer $TOKEN" } } }
```

**Per-request header**:
```bash
restish -H "Authorization:Bearer mytoken" https://api.example.com/endpoint
```

## CRUD Patterns

Restish auto-generates operation names from the OpenAPI spec's `operationId` values. Common patterns:

```bash
# List resources (auto-paginated via RFC 5988 link relations)
restish <api> list-<resources>

# Get a single resource by ID
restish <api> retrieve-<resource> <id>

# Create a resource (shorthand body syntax)
restish <api> create-<resource> field1:"value" field2:42 nested:{key:"val"}

# Partial update
restish <api> partial-update-<resource> <id> field:"new value"

# Full update
restish <api> update-<resource> <id> field1:"val1" field2:"val2"

# Delete
restish <api> destroy-<resource> <id>
```

### Body Input Formats

**Shorthand** (inline key:value):
```bash
restish api create-item name:"My Item" count:5 tags:["a","b"] meta:{key:"val"}
```

**JSON from stdin**:
```bash
echo '{"name":"My Item"}' | restish api create-item
```

**File upload** (multipart):
```bash
restish api upload-file file@/path/to/document.pdf title:"My Doc"
```

### Query Parameters

```bash
restish api list-items query="search term" page:2 ordering:"-created"
```

## Output Formatting

Restish auto-detects context:
- **Piped/scripted**: raw JSON body (agent-friendly)
- **Interactive**: colorized human-readable

Force a specific format:

```bash
# JSON output
restish api list-items -o json

# Filter to specific fields
restish api list-items -f 'body.results.{id, name}'

# Raw string output (no quotes)
restish api retrieve-item 42 -f 'body.name' -r

# Full response with headers
restish api list-items -o json -f ''
```

## Spec Caching

Restish caches the OpenAPI spec for 24 hours. To force a refresh:

```bash
restish api sync <api-name>
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (2xx) |
| 1 | Unrecoverable error |
| 3 | Redirect (3xx) |
| 4 | Client error (4xx) |
| 5 | Server error (5xx) |

## Generic HTTP Mode

For APIs without OpenAPI specs or one-off requests:

```bash
# Direct URL (no API registration needed)
restish https://api.example.com/items

# With method
restish post https://api.example.com/items name:"New Item"
restish put https://api.example.com/items/1 name:"Updated"
restish delete https://api.example.com/items/1

# With auth header
restish -H "Authorization:Bearer token" https://api.example.com/items
```
