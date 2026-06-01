### Requirement: `programs.uxc` home-manager module owns UXC on-disk state

`agentplot-kit` SHALL provide a home-manager module at `modules/home-manager/uxc.nix` exposing `programs.uxc.*` options. When enabled, the module SHALL declaratively write `~/.uxc/credentials.json`, `~/.uxc/auth_bindings.json`, and link shim executables on the client's HM profile.

Module options:
- `programs.uxc.enable`: bool, default `false`
- `programs.uxc.credentials`: attrset of credential definitions, keyed by credential id
- `programs.uxc.bindings`: list of binding entries
- `programs.uxc.links`: attrset of link definitions, keyed by link name; each value has `host`, optional `schemaUrl`, optional `injectEnv` (attrset of env vars to set before invoking `uxc`)

#### Scenario: Module enabled with credentials, bindings, and links

- **WHEN** `programs.uxc.enable = true`, `programs.uxc.credentials` has one credential, `programs.uxc.bindings` has one binding, and `programs.uxc.links` has one link
- **THEN** HM activation SHALL write `~/.uxc/credentials.json`, `~/.uxc/auth_bindings.json`, and place the link shim on `$PATH`
- **AND** the JSON files SHALL parse and contain the declared content

### Requirement: Service-projected and consumer-declared entries merge on the same options

`programs.uxc.{credentials,bindings,links}` SHALL be the single population surface for both first-party service projections (written by `mkClientTooling`'s client role) and consumer-declared third-party endpoints (written directly by the downstream HM config). The module SHALL render the module-system-merged value of these options without distinguishing entry origin. The module SHALL NOT crawl services or any source other than its own options.

#### Scenario: First-party projection and third-party entry coexist in one credentials.json

- **WHEN** `mkClientTooling` sets `programs.uxc.links."atomic-openapi-cli"` and `programs.uxc.credentials."agentplot-atomic-personal-admin-token"` on a client, **AND** the consumer separately sets `programs.uxc.links.deepwiki = { host = "https://mcp.deepwiki.com/mcp"; }`
- **THEN** the rendered `~/.uxc/credentials.json` SHALL contain the atomic credential **AND** the HM profile SHALL include both the `atomic-openapi-cli` and `deepwiki` link shims
- **AND** neither entry SHALL overwrite the other

#### Scenario: Auth-less third-party link needs no credential or binding

- **WHEN** the consumer sets only `programs.uxc.links.deepwiki = { host = "https://mcp.deepwiki.com/mcp"; }` with no matching credential or binding
- **THEN** HM activation SHALL succeed and install the `deepwiki` shim
- **AND** `credentials.json`/`auth_bindings.json` SHALL NOT gain any deepwiki entry

### Requirement: Duplicate link names and credential ids fail at eval time

The module SHALL assert that every link name in `programs.uxc.links` and every credential id in `programs.uxc.credentials` is unique across the merged set. A collision (e.g., a consumer reusing a generated `agentplot-*` name) SHALL produce an evaluation error naming the conflicting key, NOT a silent last-wins overwrite.

#### Scenario: Consumer reuses a projected link name

- **WHEN** `mkClientTooling` projects a link named `atomic-openapi-cli` **AND** the consumer also declares `programs.uxc.links."atomic-openapi-cli"`
- **THEN** evaluation SHALL fail with an error naming `atomic-openapi-cli` as a duplicate UXC link
- **AND** no `~/.uxc` files SHALL be written

### Requirement: credentials.json is written with mode 0600

The module SHALL write `~/.uxc/credentials.json` with file mode `"0600"`. The file SHALL contain an envelope `{ "version": 1, "credentials": { ... } }` where the inner attrset is the value of `programs.uxc.credentials`.

#### Scenario: credentials file permissions

- **WHEN** `programs.uxc.enable = true` and `programs.uxc.credentials` is non-empty
- **THEN** after HM activation, `stat -f "%A" ~/.uxc/credentials.json` on macOS (or `stat -c "%a"` on Linux) SHALL report `600`
- **AND** the file SHALL parse as valid JSON with the declared envelope

### Requirement: auth_bindings.json is written with mode 0600

The module SHALL write `~/.uxc/auth_bindings.json` with file mode `"0600"`. The file SHALL contain an envelope `{ "version": 1, "bindings": [ ... ] }` where the list is the value of `programs.uxc.bindings`.

#### Scenario: bindings file shape

- **WHEN** `programs.uxc.bindings = [ { id = "foo"; host = "example.com"; ... } ]`
- **THEN** `~/.uxc/auth_bindings.json` SHALL contain `{"version":1,"bindings":[{"id":"foo","host":"example.com",...}]}` as valid JSON with mode `600`

### Requirement: Link shims are installed as executables on `$PATH`

For each entry in `programs.uxc.links`, the module SHALL install an executable of that name into the HM profile's `bin/` directory via `home.packages`. The executable SHALL be a POSIX shell script that exec's `uxc` with the appropriate arguments.

#### Scenario: Link shim for OpenAPI endpoint

- **WHEN** `programs.uxc.links = { "atomic-openapi-cli" = { host = "atomic.swancloud.net"; schemaUrl = "file:///nix/store/...-atomic-openapi.json/openapi.json"; }; }`
- **THEN** the HM profile SHALL include an executable `atomic-openapi-cli`
- **AND** running `atomic-openapi-cli --help` SHALL execute approximately `uxc 'atomic.swancloud.net' --schema-url 'file:///nix/store/...' --help`

#### Scenario: Link shim without schemaUrl

- **WHEN** a link has no `schemaUrl` set
- **THEN** the shim SHALL execute `uxc '<host>' "$@"` without a `--schema-url` argument

#### Scenario: Link shim with injectEnv

- **WHEN** a link has `injectEnv = { API_REGION = "us"; }`
- **THEN** the shim SHALL export `API_REGION=us` before invoking `uxc`

### Requirement: Module does NOT manage UXC binary installation

The module SHALL NOT install the `uxc` binary. Users SHALL provide `uxc` in their `$PATH` via homebrew, cargo, or a future nixpkgs package.

#### Scenario: Module enabled without uxc installed

- **WHEN** `programs.uxc.enable = true` but `uxc` is not on `$PATH`
- **THEN** HM activation SHALL succeed (the JSON files and shims are written regardless)
- **AND** invoking a link shim SHALL fail with a "command not found: uxc" error, NOT a Nix build failure

### Requirement: Module does NOT manage daemon or cache state

The module SHALL NOT write to `~/.uxc/daemon/` or `~/.uxc/cache/`. Those directories are runtime state managed by the `uxc` binary itself.

#### Scenario: Daemon cache untouched

- **WHEN** HM activation runs and `~/.uxc/cache/schemas/` already contains cached schema files
- **THEN** those files SHALL remain intact after activation
- **AND** only `credentials.json`, `auth_bindings.json`, and the link shims in `home.packages` SHALL be updated
