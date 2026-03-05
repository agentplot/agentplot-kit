---
name: evernote-convert
description: Migrate Evernote .enex exports to Paperless-ngx using enex2paperless CLI and Lobster workflow
---

# Evernote to Paperless Conversion

Batch conversion of Evernote .enex export files into Paperless-ngx documents. Uses `enex2paperless` CLI for parsing and upload, wrapped in a Lobster workflow for batch processing with approval and archive-on-success.

## Lobster Workflow (Primary Interface)

Use `lobster-run` (not bare `lobster`) for this workflow — it handles SecretSpec secret injection and service URL export automatically.

### Process all files in inbox

```bash
lobster-run run --file ~/.openclaw/workflows/enex-convert.yaml
```

### Process a specific number of files

```bash
lobster-run run --file ~/.openclaw/workflows/enex-convert.yaml --args-json '{"count": 5}'
```

### Workflow steps

1. **write-config** — Generates `config.yaml` in the project folder from `$PAPERLESS_URL` and `$PAPERLESS_API_TOKEN` environment variables
2. **discover** — Finds .enex files in inbox, applies count limit, outputs JSON inventory
3. **approve** — Shows files to process with sizes, requests user approval
4. **process** — For each file: copies to `processing/`, runs `enex2paperless`, moves to archive on success or `failed/` on error
5. **report** — JSON summary with success/failure counts

### Workflow args

| Arg | Default | Purpose |
|-----|---------|---------|
| `count` | `0` (all) | Max files to process |
| `inbox_dir` | `~/Documents/EvernoteConversion/inbox` | Source directory |
| `archive_dir` | `/Archives/Archived Areas/Old Evernote Data` | Completed .enex destination |
| `project_dir` | `~/Documents/EvernoteConversion` | Working directory |

## Project Folder Layout

```
~/Documents/EvernoteConversion/
├── inbox/          ← Drop .enex files here
├── processing/     ← Files being converted (lock/recovery)
├── failed/         ← Failed conversions for retry
└── config.yaml     ← Generated at workflow runtime
```

**Archive destination:** `/Archives/Archived Areas/Old Evernote Data/`

## Tagging Strategy

Every imported document receives:
- `evernote-import` — Fixed tag for filtering all imported docs
- `<filename>` — The .enex filename (without extension) as a tag, e.g., `MyNotebook`
- Original Evernote tags — Preserved from the .enex metadata

## enex2paperless CLI Reference

### Usage

```bash
enex2paperless <file.enex> [flags]
```

### Flags

| Flag | Short | Type | Default | Purpose |
|------|-------|------|---------|---------|
| `--concurrent` | `-c` | int | 1 | Concurrent upload workers |
| `--tags` | `-t` | string | — | Comma-separated tags for all docs |
| `--use-filename-tag` | `-T` | bool | false | Add .enex filename as tag |
| `--outputfolder` | `-o` | string | — | Save to folder instead of API upload |
| `--verbose` | `-v` | bool | false | Verbose logging |
| `--nocolor` | `-n` | bool | false | Disable colored output |

### config.yaml format

```yaml
PaperlessAPI: https://your-paperless-url
Token: your-api-token
FileTypes:
  - pdf
  - txt
  - jpeg
  - png
  - webp
  - gif
  - tiff
  - zip
```

Place `config.yaml` in the same directory as the .enex file (or use the workflow which generates it automatically).

### Limitations

- **Attachments only** — Notes without file attachments are silently skipped
- **One file per invocation** — Processes a single .enex file at a time
- **No resume** — If interrupted, the file must be reprocessed from scratch
- **HTTP timeout** — 100 second timeout per upload
