### Requirement: Shared secret mode references existing vars generator
mkClientTooling SHALL support a `shared` secret mode that resolves to the file path of an existing vars generator created by the server role, without creating a new vars generator.

A shared secret declaration MUST include:
- `name`: identifier for this secret (used as key in `secretPaths`)
- `mode`: `"shared"`
- `generator`: name of the existing vars generator to reference
- `file`: file name within that generator

#### Scenario: Shared secret resolves to server generator path
- **WHEN** a client declares `secret = { name = "db-password"; mode = "shared"; generator = "subcog-db-password"; file = "password"; }`
- **THEN** `secretPaths."db-password"` SHALL equal `config.clan.core.vars.generators."subcog-db-password".files."password".path`
- **AND** no new vars generator SHALL be created for this secret

#### Scenario: Shared secret path flows to CLI envVars
- **WHEN** a client has a shared secret named `"db-password"` and `cli.envVars` references `settings.secretPaths."db-password"`
- **THEN** the CLI wrapper SHALL export an environment variable whose value is the resolved shared generator file path

#### Scenario: Shared secret path flows to MCP via extraConfig
- **WHEN** a client has a shared secret named `"jwt-token"` and `mcp.extraConfig` returns `{ tokenFile = settings.secretPaths."jwt-token"; }`
- **THEN** the MCP config SHALL include `tokenFile` set to the resolved shared generator file path

### Requirement: Multiple secrets per client
mkClientTooling SHALL accept `capabilities.secret` as either a single attrset or a list of secret attrsets. Each secret in the list SHALL produce a named entry in `secretPaths`.

#### Scenario: Single secret
- **WHEN** `secret = { name = "api-key"; mode = "prompted"; }`
- **THEN** `secretPaths` SHALL contain `{ "api-key" = <path>; }`

#### Scenario: Multiple secrets as list
- **WHEN** `secret = [ { name = "db-password"; mode = "shared"; generator = "gen-db"; file = "password"; } { name = "jwt-token"; mode = "shared"; generator = "gen-jwt"; file = "token"; } ]`
- **THEN** `secretPaths` SHALL contain both `"db-password"` and `"jwt-token"` keys with their respective paths

#### Scenario: Mixed modes in secret list
- **WHEN** a client declares a list with one `prompted` secret and one `shared` secret
- **THEN** the `prompted` secret SHALL create a vars generator as before
- **AND** the `shared` secret SHALL reference an existing generator without creating a new one
- **AND** both paths SHALL be available in `secretPaths`

### Requirement: Generic MCP secret injection via extraConfig
mkClientTooling SHALL support an `mcp.extraConfig` callback that receives `clientSettings` (including `secretPaths`) and returns an attrset merged into the MCP config. This replaces the hardcoded `mcp.tokenFile` field for injecting secrets into MCP configs.

#### Scenario: extraConfig injects multiple secrets into MCP config
- **WHEN** `mcp.extraConfig = settings: { tokenFile = settings.secretPaths."jwt-token"; passwordFile = settings.secretPaths."db-password"; }`
- **THEN** the MCP config SHALL include both `tokenFile` and `passwordFile` with their respective resolved paths

#### Scenario: extraConfig is optional
- **WHEN** `mcp` does not declare `extraConfig`
- **THEN** the MCP config SHALL contain only `url` and `type` as before

#### Scenario: Legacy mcp.tokenFile backward compatibility
- **WHEN** an existing service declares `mcp.tokenFile` (old form) without `extraConfig`
- **THEN** mkClientTooling SHALL synthesize an `extraConfig` that maps `tokenFile` to the first secret's path
- **AND** the MCP config SHALL include `tokenFile` as before

### Requirement: Vars generators only created for non-shared secrets
mkClientTooling SHALL only register vars generators for secrets with `mode = "prompted"` or `mode = "generated"`. Secrets with `mode = "shared"` SHALL NOT create vars generators.

#### Scenario: Shared secrets excluded from vars generator registration
- **WHEN** a client has two secrets: one `prompted` and one `shared`
- **THEN** `clan.core.vars.generators` SHALL contain a generator for the prompted secret
- **AND** `clan.core.vars.generators` SHALL NOT contain a generator for the shared secret

### Requirement: Backward-compatible secret normalization
mkClientTooling SHALL accept `capabilities.secret` in both the legacy single-attrset form and the new list form, normalizing internally to a list.

#### Scenario: Legacy single attrset still works
- **WHEN** an existing service declares `secret = { name = "api-key"; mode = "prompted"; }`
- **THEN** the behavior SHALL be identical to the current implementation
- **AND** `secretPaths."api-key"` SHALL resolve to the generated vars file path

#### Scenario: Null secret still works
- **WHEN** `capabilities.secret` is `null` or not provided
- **THEN** `hasSecret` SHALL be false and no secret-related processing SHALL occur
