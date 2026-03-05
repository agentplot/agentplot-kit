---
name: linkding
description: Manage linkding bookmarks, tags, bundles, and assets via the REST API. Use when creating, searching, archiving, or organizing bookmarks, managing tags, working with bookmark bundles, or uploading assets.
secrets:
  - LINKDING_API_TOKEN
env:
  - LINKDING_BASE_URL
---

# Linkding API Skill

Manage the linkding bookmark manager via its REST API using `linkding-cli`.

`linkding-cli` wraps restish with the bundled OpenAPI spec, so all endpoints are auto-discovered as typed CLI commands. New API features work immediately without skill updates.

## Authentication

Authentication is handled via environment variables:
- `LINKDING_API_TOKEN` — API token for authentication
- `LINKDING_BASE_URL` — Base URL of the linkding instance

No manual setup is needed — just use the commands below.

## Discovering Available Operations

```bash
# List all operations
linkding-cli --help

# Help for a specific operation
linkding-cli <operation-id> --help
```

## Restish Syntax Rules

- **GET query parameters** use `--flag value` syntax (flags are kebab-case, auto-generated from the OpenAPI spec):
  `linkding-cli list-bookmarks --q "search" --limit 5`
- **POST/PUT/PATCH body parameters** use `key:value` syntax:
  `linkding-cli create-bookmark url:"https://example.com" tag_names:["dev"]`

Do NOT use `key:value` for GET query params — restish treats those as body args and will error with "accepts 0 arg(s)".

## Common Operations

### Bookmarks

```bash
# List bookmarks (paginated, default 100)
linkding-cli list-bookmarks

# Search bookmarks by content
linkding-cli list-bookmarks --q "kubernetes tutorial"

# Filter by modification date (ISO 8601)
linkding-cli list-bookmarks --modified-since "2024-01-01T00:00:00Z"

# Filter by added date
linkding-cli list-bookmarks --added-since "2024-06-01T00:00:00Z"

# Filter by bundle
linkding-cli list-bookmarks --bundle 1

# Get a specific bookmark
linkding-cli retrieve-bookmark 42

# Create a bookmark (title/description auto-scraped)
linkding-cli create-bookmark url:"https://example.com" tag_names:["dev","reference"]

# Create a bookmark with explicit metadata (skip scraping)
linkding-cli create-bookmark \
  url:"https://example.com" \
  title:"Example Site" \
  description:"A useful reference" \
  notes:"Found via HN" \
  tag_names:["dev","reference"] \
  disable_scraping:true

# Update a bookmark (partial — only change specified fields)
linkding-cli partial-update-bookmark 42 title:"Updated Title" tag_names:["new-tag"]

# Update a bookmark (full — replaces all fields)
linkding-cli update-bookmark 42 url:"https://example.com" title:"Full Update"

# Delete a bookmark
linkding-cli delete-bookmark 42

# Check a URL before bookmarking (get metadata + existing bookmark if saved)
linkding-cli check-bookmark --url "https://example.com"
```

### Archived Bookmarks

```bash
# List archived bookmarks
linkding-cli list-archived-bookmarks

# Search archived bookmarks
linkding-cli list-archived-bookmarks --q "old project"

# Archive a bookmark
linkding-cli archive-bookmark 42

# Unarchive a bookmark
linkding-cli unarchive-bookmark 42
```

### Tags

```bash
# List all tags
linkding-cli list-tags

# Get a specific tag
linkding-cli retrieve-tag 5

# Create a tag
linkding-cli create-tag name:"project-alpha"
```

### Bundles

Bundles are saved searches / smart collections of bookmarks filtered by tags and search terms.

```bash
# List all bundles
linkding-cli list-bundles

# Get a specific bundle
linkding-cli retrieve-bundle 1

# Create a bundle (filter by tags and search)
linkding-cli create-bundle \
  name:"Dev Resources" \
  search:"tutorial" \
  any_tags:"dev javascript" \
  excluded_tags:"archived"

# Update a bundle
linkding-cli partial-update-bundle 1 name:"Updated Bundle"

# Delete a bundle
linkding-cli delete-bundle 1
```

#### Bundle Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Bundle display name (required) |
| `search` | string | Free-text search filter |
| `any_tags` | string | Space-separated tag names (OR match) |
| `all_tags` | string | Space-separated tag names (AND match) |
| `excluded_tags` | string | Space-separated tag names to exclude |
| `order` | int | Display order (lower = first) |

### Bookmark Assets

Assets are files attached to bookmarks (HTML snapshots, uploaded files).

```bash
# List assets for a bookmark
linkding-cli list-assets 42

# Get asset details
linkding-cli retrieve-asset 42 1

# Download an asset file
linkding-cli download-asset 42 1 -o snapshot.html

# Upload a file to a bookmark
linkding-cli upload-asset 42 file@/path/to/file.pdf

# Delete an asset
linkding-cli delete-asset 42 1
```

### User Profile

```bash
# Get user profile settings
linkding-cli get-user-profile
```

## Output Formatting

Restish auto-detects output context:
- **Piped/scripted**: outputs raw JSON (agent-friendly)
- **Interactive terminal**: colorized human-readable output

Force specific formats:

```bash
# JSON output
linkding-cli list-bookmarks -o json

# Filter specific fields
linkding-cli list-bookmarks -f 'body.results.{id, url, title, tag_names}'

# Raw string (no quotes)
linkding-cli retrieve-bookmark 42 -f 'body.title' -r
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (2xx) |
| 1 | Unrecoverable error |
| 4 | Client error (4xx) |
| 5 | Server error (5xx) |

## Bookmark Search Patterns

```bash
# Find bookmarks with specific tags
linkding-cli list-bookmarks --q "#dev" -f 'body.results.{id, url, title}'

# Find recent bookmarks
linkding-cli list-bookmarks --added-since "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)" -f 'body.results.{id, url, title}'

# Check if a URL is already bookmarked
linkding-cli check-bookmark --url "https://example.com" -f 'body.bookmark'
```
