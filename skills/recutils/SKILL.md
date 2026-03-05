---
name: recutils
description: Use GNU Recutils for plain-text relational databases with schema enforcement. Use when managing structured state in agent workspaces, creating queryable configuration files, or working with .rec files.
---

# Recutils: Plain-Text Databases

GNU Recutils provides human-readable, git-friendly relational databases as plain-text `.rec` files with schema enforcement, typed fields, foreign keys, and native CLI tools for query/insert/update/delete.

## Why Recutils

- Human-editable plain text with clean git diffs
- Schema enforcement (types, mandatory fields, unique constraints, enums)
- Native CLI tools — no parsing or scripting needed
- Foreign keys and joins between record types
- Works in any shell pipeline

## File Structure

A `.rec` file contains record descriptors (schema) followed by records:

```rec
# Record descriptor (schema)
%rec: Vendor
%mandatory: Name Email
%unique: Name
%type: Email email
%type: Phase enum Active Paused Archived
%type: Tags line
%allowed: Name Email Phase Tags Correspondent DocumentType

# Records
Name: Acme Corp
Email: billing@acme.com
Phase: Active
Tags: vendor-invoice
Correspondent: Acme Corp
DocumentType: Vendor Invoice

Name: Globex Inc
Email: invoices@globex.com
Phase: Active
Tags: vendor-invoice consulting
```

## Schema Descriptors

| Descriptor | Purpose | Example |
|------------|---------|---------|
| `%rec: Type` | Record type name | `%rec: Vendor` |
| `%mandatory: F1 F2` | Required fields | `%mandatory: Name Email` |
| `%unique: F1` | Unique constraint | `%unique: Name` |
| `%key: F1` | Primary key (unique + mandatory) | `%key: Id` |
| `%type: Field type` | Field type | `%type: Age int` |
| `%typedef: Name type` | Named type alias | `%typedef: Phase_t enum Active Paused` |
| `%allowed: F1 F2 F3` | Only these fields allowed | `%allowed: Name Email Phone` |
| `%prohibit: F1` | Disallowed fields | `%prohibit: Password` |
| `%singular: F1` | Field can appear only once per record | `%singular: Email` |
| `%sort: Field` | Default sort order | `%sort: Name` |
| `%size: N` | Exactly N records allowed | `%size: 1` (singleton) |
| `%auto: Field` | Auto-increment field | `%auto: Id` |
| `%constraint: expr` | Record-level constraint | `%constraint: #Age > 0` |
| `%confidential: F1` | Mark field as sensitive | `%confidential: APIKey` |

## Field Types

| Type | Syntax | Values |
|------|--------|--------|
| `int` | `%type: F int` | Integer |
| `real` | `%type: F real` | Float |
| `bool` | `%type: F bool` | `yes`, `no`, `true`, `false`, `0`, `1` |
| `line` | `%type: F line` | Single line string (no newlines) |
| `date` | `%type: F date` | ISO 8601 dates |
| `email` | `%type: F email` | Email addresses |
| `enum` | `%type: F enum A B C` | One of listed values |
| `range` | `%type: F range MIN MAX` | Integer in range |
| `size` | `%type: F size` | Size with units (10M, 2GiB) |
| `regexp /pat/` | `%type: F regexp /^INV-[0-9]+$/` | Matches regex |
| `rec OtherType` | `%type: F rec OtherType` | Foreign key |

## Querying with recsel

```bash
# List all records of a type
recsel -t Vendor vendors.rec

# Filter with expression
recsel -t Vendor -e 'Phase = "Active"' vendors.rec

# Multiple conditions
recsel -t Vendor -e 'Phase = "Active" && Tags ~ "consulting"' vendors.rec

# Project specific fields
recsel -t Vendor -p Name,Email vendors.rec

# Count matching records
recsel -t Vendor -e 'Phase = "Active"' -c vendors.rec

# First N records
recsel -t Vendor -n 5 vendors.rec

# Join on foreign key
recsel -t Invoice -j Vendor invoices.rec

# Group by field
recsel -t Invoice -G Vendor -p 'Vendor,Count(Amount)' invoices.rec
```

### Expression Operators

| Operator | Meaning | Example |
|----------|---------|---------|
| `=` | Equals | `Name = "Acme"` |
| `!=` | Not equals | `Phase != "Archived"` |
| `<` `>` `<=` `>=` | Comparison | `Amount > 1000` |
| `~` | Regex match | `Email ~ "acme"` |
| `&&` | AND | `Phase = "Active" && Amount > 0` |
| `\|\|` | OR | `Phase = "Active" \|\| Phase = "Paused"` |
| `!` | NOT | `!Phase = "Archived"` |
| `#Field` | Field exists/count | `#Tags > 1` (multi-valued) |
| `&` | String concat | `Name & " Corp"` |

### Aggregate Functions

Use with `-G` (group by): `Count()`, `Sum()`, `Avg()`, `Min()`, `Max()`

## Inserting with recins

```bash
# Insert a record
recins -t Vendor \
  -f Name -v "New Corp" \
  -f Email -v "billing@new.com" \
  -f Phase -v "Active" \
  vendors.rec

# Insert with auto-increment
recins -t Invoice \
  -f Vendor -v "Acme Corp" \
  -f Amount -v "1500" \
  invoices.rec
```

## Updating with recset

```bash
# Update matching records: set a field value
recset -t Vendor -e 'Name = "Acme Corp"' \
  -f Phase -s "Paused" \
  vendors.rec

# Add a value to a multi-valued field
recset -t Vendor -e 'Name = "Acme Corp"' \
  -f Tags -a "premium" \
  vendors.rec

# Delete a field from matching records
recset -t Vendor -e 'Name = "Acme Corp"' \
  -f OldField -d \
  vendors.rec

# Rename a field
recset -t Vendor -e 'Name = "Old Name"' \
  -f Name -S "New Name" \
  vendors.rec
```

## Deleting with recdel

```bash
# Delete matching records
recdel -t Vendor -e 'Phase = "Archived"' vendors.rec

# Comment out instead of deleting (preserves in file)
recdel -t Vendor -e 'Phase = "Archived"' -c vendors.rec

# Delete by record number (0-indexed)
recdel -t Vendor -n 0 vendors.rec
```

## Validating with recfix

```bash
# Validate schema and data integrity
recfix --check vendors.rec

# Sort records by %sort field
recfix --sort vendors.rec

# Auto-fill %auto fields
recfix --auto vendors.rec
```

## Foreign Keys and Joins

```rec
%rec: Vendor
%key: Name
%type: Phase enum Active Paused Archived

Name: Acme Corp
Phase: Active

%rec: Invoice
%mandatory: Vendor Amount
%type: Vendor rec Vendor
%type: Amount int

Vendor: Acme Corp
Amount: 1500
```

```bash
# Join Invoice with Vendor data (adds Vendor_ prefixed fields)
recsel -t Invoice -j Vendor invoices.rec
# Output includes: Vendor_Phase, etc.
```

## LoomOS Conventions

### File Location

Rec files live in agent workspaces: `~/.openclaw/workspace-<agent>/`

| File | Purpose |
|------|---------|
| `invoices.rec` | Vendor and invoice tracking |
| `state.rec` | General agent operational state |
| `schedule.rec` | Cron/scheduling metadata |

### State Machine Pattern

Use enum fields for workflow phases:

```rec
%rec: Vendor
%type: Phase enum Active Paused Archived
%type: InvoicePhase enum Pending Received Processed Paid

Name: Acme Corp
Phase: Active
InvoicePhase: Pending
```

```bash
# Advance state
recset -t Vendor -e 'Name = "Acme Corp"' -f InvoicePhase -s "Received" invoices.rec

# Find vendors needing attention
recsel -t Vendor -e 'Phase = "Active" && InvoicePhase = "Pending"' invoices.rec
```

### Multi-Valued Fields

Fields can appear multiple times on a record for list semantics:

```rec
Name: Acme Corp
Tags: vendor-invoice
Tags: premium
Tags: monthly
```

```bash
# Count tags
recsel -t Vendor -e '#Tags > 2' vendors.rec

# Check if tag exists
recsel -t Vendor -e 'Tags = "premium"' vendors.rec
```

## Format Output with recfmt

```bash
# Custom output format
recfmt -f '{{Name}} <{{Email}}> [{{Phase}}]\n' vendors.rec
```

## CSV Conversion

```bash
# Rec to CSV
rec2csv -t Vendor vendors.rec > vendors.csv

# CSV to Rec
csv2rec -t Vendor < vendors.csv > vendors.rec
```
