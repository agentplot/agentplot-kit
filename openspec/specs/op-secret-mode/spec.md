### Requirement: `op` secret mode references a 1Password path

`mkClientTooling` SHALL accept `mode = "op"` as a fourth secret mode (alongside `prompted`, `generated`, `shared`). An `op`-mode secret references a 1Password item path that UXC resolves at call time by shelling out to the `op` CLI.

An `op`-mode secret declaration MUST include:
- `name`: identifier (used as key in `opSecrets`)
- `mode`: `"op"`
- `reference`: a string matching `op://<Vault>/<Item>/<field>`

An `op`-mode secret declaration MUST NOT include `generator` or `file` (those are `shared`-mode fields).

#### Scenario: op-mode secret declaration

- **WHEN** a service declares `secret = [ { name = "atomic-token"; mode = "op"; reference = "op://Personal/Atomic/token"; } ]`
- **THEN** `mkClientTooling` SHALL accept the declaration without error
- **AND** no clan vars generator SHALL be created for this secret
- **AND** `opSecrets."atomic-token"` SHALL equal `"op://Personal/Atomic/token"`

### Requirement: `op` secrets have no `secretPath` entry

`op`-mode secrets SHALL NOT appear in the `secretPaths` attrset passed to `cli.envVars` and `mcp.extraConfig` callbacks, because they have no corresponding file path on the filesystem.

#### Scenario: op secret absent from secretPaths

- **WHEN** a client declares one `op`-mode secret named `"atomic-token"` and one `prompted`-mode secret named `"legacy-key"`
- **THEN** `secretPaths` SHALL contain only `"legacy-key"` (with its file path)
- **AND** `secretPaths` SHALL NOT contain `"atomic-token"`
- **AND** `opSecrets` SHALL contain only `"atomic-token"` (with its reference string)

### Requirement: `op` secret projects to UXC credential when referenced by an endpoint `auth` block

When a client has `uxc.enabled = true` and the service has at least one `op`-mode secret referenced by an endpoint's `auth.secret`, `mkClientTooling` SHALL project that secret into a UXC credential entry. `op` secrets that are NOT referenced by any endpoint SHALL NOT produce a credential (they exist only as declarations, e.g., for future use).

#### Scenario: Op secret referenced by endpoint becomes a bearer credential

- **WHEN** a client `personal` of service `atomic` has `uxc.enabled = true`, one `op`-mode secret named `"admin-token"` with reference `"op://Personal/Atomic/token"`, and an `openapi` capability with `auth = { secret = "admin-token"; type = "bearer"; }`
- **THEN** the emitted credential SHALL have `id = "agentplot-atomic-personal-admin-token"`, `auth_type = "bearer"`, and `secret_source = { kind = "op"; reference = "op://Personal/Atomic/token"; }`

#### Scenario: Op secret unreferenced by endpoint produces no credential

- **WHEN** a client has `uxc.enabled = true` and one `op`-mode secret named `"unused"` with no endpoint `auth.secret = "unused"` reference anywhere
- **THEN** `credentials.json` SHALL NOT contain an `agentplot-<service>-<client>-unused` entry

### Requirement: `op` mode secrets do not create vars generators

Vars generators SHALL be created only for `prompted` and `generated` secrets. `op` and `shared` modes SHALL be excluded.

#### Scenario: op secret absent from vars generator attrset

- **WHEN** a client has one `op`-mode secret and one `generated`-mode secret
- **THEN** only the `generated` secret SHALL have a corresponding `clan.core.vars.generators.*` entry
- **AND** the `op` secret SHALL NOT produce a vars generator

### Requirement: `op` reference format validation

`mkClientTooling` SHALL reject `op`-mode secret declarations where `reference` does not start with `op://` or is missing.

#### Scenario: missing reference

- **WHEN** a service declares `secret = [ { name = "foo"; mode = "op"; } ]`
- **THEN** evaluation SHALL fail with a clear error message indicating the missing `reference` field

#### Scenario: malformed reference

- **WHEN** a service declares `secret = [ { name = "foo"; mode = "op"; reference = "Personal/Atomic/token"; } ]` (missing `op://` prefix)
- **THEN** evaluation SHALL fail with a clear error message indicating the `op://` prefix requirement
