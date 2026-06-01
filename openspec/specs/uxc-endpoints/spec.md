### Requirement: Services declare OpenAPI endpoints via `openapi` capability

`mkClientTooling` SHALL accept an `openapi` capability on the `capabilities` attribute that declares an OpenAPI 3.1 endpoint consumable by UXC.

An `openapi` declaration MUST include:
- `host`: hostname as a string (e.g., `"atomic.swancloud.net"`) OR a function `clientSettings -> string`
- `schemaSource`: an attrset of type `{ type = "static" | "derivation" | "url"; ... }`
- `auth`: an attrset `{ secret = "<name-from-secret-capability>"; type = "bearer" | "api_key"; }`

An `openapi` declaration MAY include:
- `pathPrefix`: base path for the API as a string OR a function `clientSettings -> string` (default `"/"`)
- `scheme`: `"http"` or `"https"`, as a string OR function (default `"https"`)
- `linkName`: override for the default link shim name (default `"<serviceName>-openapi-cli"`)
- `priority`: binding priority (default `100`)

#### Scenario: OpenAPI capability with static schema source

- **WHEN** a service declares `capabilities.openapi = { host = "atomic.swancloud.net"; pathPrefix = "/api"; schemaSource = { type = "static"; path = ./openapi.json; }; }`
- **THEN** `mkClientTooling` SHALL produce a UXC projection that references the schema at a Nix store path
- **AND** the link shim SHALL invoke `uxc 'atomic.swancloud.net' --schema-url 'file:///nix/store/...-atomic-openapi.json/openapi.json' "$@"`

#### Scenario: OpenAPI capability with derivation schema source

- **WHEN** a service declares `schemaSource = { type = "derivation"; drv = <drv>; }`
- **THEN** the projection SHALL use `<drv>.outPath` as the schema file location
- **AND** the link shim SHALL reference `file://<drv-outpath>` in `--schema-url`

#### Scenario: OpenAPI capability with URL schema source

- **WHEN** a service declares `schemaSource = { type = "url"; url = "https://api.example.com/openapi.json"; }`
- **THEN** the link shim SHALL reference the URL verbatim in `--schema-url` (no local caching by agentplot-kit)

### Requirement: OpenAPI endpoint projects to a UXC binding

For each OpenAPI endpoint on a client with `uxc.enabled = true`, `mkClientTooling` SHALL emit a UXC binding entry that matches the endpoint's scheme, host, and path prefix.

#### Scenario: Binding for atomic OpenAPI

- **WHEN** a client `personal` has `uxc.enabled = true` and the service declares the OpenAPI endpoint above
- **THEN** `auth_bindings.json` SHALL contain an entry with `id = "agentplot-atomic-personal-openapi"`, `scheme = "https"`, `host = "atomic.swancloud.net"`, `path_prefix = "/api"`, `credential = "agentplot-atomic-personal-admin-token"`, `priority = 100`, `enabled = true`

### Requirement: OpenAPI endpoint projects to a UXC link shim

For each OpenAPI endpoint on a client with `uxc.enabled = true`, `mkClientTooling` SHALL emit a link shim on the client's HM profile at a path on `$PATH`.

#### Scenario: Default link shim name follows convention

- **WHEN** a service `atomic` has an OpenAPI capability with no `linkName` override
- **AND** a client has `uxc.enabled = true`
- **THEN** the HM profile SHALL include an executable named `atomic-openapi-cli` whose body reads approximately `exec uxc 'atomic.swancloud.net' --schema-url '<resolved>' "$@"`

#### Scenario: Link shim name override

- **WHEN** `openapi.linkName = "atomic-api"` is set
- **THEN** the executable SHALL be named `atomic-api` instead of `atomic-openapi-cli`

### Requirement: UXC projection is gated by per-client `uxc.enabled`

Even if a service declares UXC-compatible capabilities, UXC artifacts SHALL NOT be emitted for a client unless that client has `uxc.enabled = true`.

#### Scenario: Client opts out

- **WHEN** a service declares `openapi` capabilities and a client has `uxc.enabled = false` (default)
- **THEN** no credentials, bindings, or link shims SHALL be emitted for that client
- **AND** the client's other capabilities (skills, MCP, CLI) SHALL continue to project normally

#### Scenario: Client opts in

- **WHEN** a client has `uxc.enabled = true` and the service declares at least one UXC-compatible capability
- **THEN** the client's HM module SHALL receive `programs.uxc.credentials`, `programs.uxc.bindings`, and `programs.uxc.links` entries
- **AND** those entries SHALL be merged with any entries from other services on the same client

### Requirement: UXC and Claude Code MCP can coexist per client

A client SHALL be able to enable both `uxc.enabled = true` AND `claude-code.mcp.enabled = true` simultaneously for services that declare both `mcp` and other UXC-compatible capabilities.

#### Scenario: Atomic client with both consumers

- **WHEN** a client declares `uxc.enabled = true` AND `claude-code.mcp.enabled = true`
- **AND** the service declares both an `mcp` and an `openapi` capability
- **THEN** Claude Code SHALL receive the MCP server registration (via `programs.claude-code.mcpServers`)
- **AND** UXC SHALL receive the MCP and OpenAPI credentials/bindings/links (via `programs.uxc.*`)
- **AND** neither projection SHALL interfere with the other

### Requirement: MCP endpoints project to UXC bindings and link shims

For each `mcp` capability on a client with `uxc.enabled = true`, `mkClientTooling` SHALL emit a UXC binding (using the `mcp.urlTemplate`'s scheme/host/path) and a `<serviceName>-mcp-cli` link shim.

#### Scenario: MCP projection alongside OpenAPI

- **WHEN** a service declares `mcp = { type = "http"; urlTemplate = c: "https://${c.domain}/mcp"; auth = { secret = "admin-token"; type = "bearer"; }; }` and a client has `uxc.enabled = true` with `domain = "atomic.swancloud.net"`
- **THEN** `auth_bindings.json` SHALL contain a binding with `id = "agentplot-atomic-personal-mcp"`, `scheme = "https"`, `host = "atomic.swancloud.net"`, `path_prefix = "/mcp"`, `credential = "agentplot-atomic-personal-admin-token"`
- **AND** the HM profile SHALL include an executable named `atomic-mcp-cli`

### Requirement: Endpoint `auth` block names a credential

Each UXC-projectable endpoint (`mcp`, `openapi`) SHALL declare `auth = { secret; type; }`. The `secret` field SHALL match the `name` of an entry in the service's `secret` capability. The `type` field SHALL be `"bearer"` or `"api_key"`.

#### Scenario: Two endpoints sharing a credential

- **WHEN** a service declares one `op`-mode secret named `"admin-token"`, an `mcp` endpoint with `auth.secret = "admin-token"`, and an `openapi` endpoint with `auth.secret = "admin-token"`
- **THEN** `credentials.json` SHALL contain exactly one credential with id `"agentplot-<service>-<client>-admin-token"`
- **AND** `auth_bindings.json` SHALL contain two bindings, both with `credential = "agentplot-<service>-<client>-admin-token"`

#### Scenario: Endpoint references unknown secret

- **WHEN** an endpoint declares `auth.secret = "missing"` but the `secret` capability has no entry named `"missing"`
- **THEN** evaluation SHALL fail with a clear error citing the endpoint and the missing secret name

#### Scenario: Endpoint references non-`op` secret

- **WHEN** an endpoint's `auth.secret` references a secret with `mode != "op"`
- **THEN** evaluation SHALL fail with a clear error indicating that UXC projection requires `op`-mode secrets in v1

### Requirement: `host` / `urlTemplate` accept a function of clientSettings

`openapi.host`, `openapi.scheme`, `openapi.pathPrefix`, and `mcp.urlTemplate` SHALL accept either a string OR a function taking the client's settings attrset and returning a string. The projection SHALL evaluate the function with the per-client settings before writing UXC artifacts.

#### Scenario: Per-client host

- **WHEN** a service declares `openapi.host = client: client.domain` and a client has `domain = "atomic.swancloud.net"`
- **THEN** the emitted binding SHALL have `host = "atomic.swancloud.net"`
