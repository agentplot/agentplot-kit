## Purpose

Per-client delegation from clanService client roles to downstream Home Manager programs (claude-code, agent-skills, agent-deck, openclaw, claude-tools, and CLI wrappers). Defines how each integration flag maps to specific HM module options.

## Requirements

### Requirement: Delegation to programs.claude-code
When `claude-code.skill.enabled = true` for a client, the generated HM module SHALL set `programs.claude-code.skills.<client-name>` to a per-client SKILL.md generated via `pkgs.writeText` with the client's CLI name substituted. When `claude-code.mcp.enabled = true`, it SHALL set `programs.claude-code.mcpServers.<client-name>` with the linkding MCP server configuration including the base URL and API token file path. When `claude-code.profiles.<profile>.mcp.enabled = true`, it SHALL set `programs.claude-code.profiles.<profile>.mcpServers.<client-name>`.

#### Scenario: Skill installed to default Claude config
- **WHEN** client "linkding" has `claude-code.skill.enabled = true`
- **THEN** `programs.claude-code.skills.linkding` SHALL point to a generated SKILL.md referencing the `linkding` CLI name

#### Scenario: Skill with different CLI name
- **WHEN** client "linkding-biz" has `claude-code.skill.enabled = true` and `name = "linkding-biz"`
- **THEN** `programs.claude-code.skills.linkding-biz` SHALL point to a generated SKILL.md referencing the `linkding-biz` CLI name

#### Scenario: MCP added to specific Claude profile
- **WHEN** client "linkding-biz" has `claude-code.profiles.business.mcp.enabled = true`
- **THEN** `programs.claude-code.profiles.business.mcpServers.linkding-biz` SHALL contain the MCP server config with the business client's base URL and token path

### Requirement: Delegation to programs.agent-skills
When `agent-skills.enabled = true`, the generated HM module SHALL register the agentplot service as a `path`-based source in `programs.agent-skills.sources` and select the client's skill via `programs.agent-skills.skills.explicit.<client-name>`. The explicit skill entry SHALL use the `packages` option to associate the client-specific CLI package and the `transform` function to modify the SKILL.md with the correct CLI package path. It SHALL enable the `targets.claude` target.

#### Scenario: Skill distributed via agent-skills with package association
- **WHEN** client "linkding" has `agent-skills.enabled = true`
- **THEN** `programs.agent-skills.sources.agentplot-linkding` SHALL use `path` (not `input`) pointing to the service's skills directory
- **AND** `programs.agent-skills.skills.explicit.linkding` SHALL select the skill with `packages = [ linkding-cli-wrapper ]`
- **AND** `programs.agent-skills.targets.claude.enable` SHALL be true

#### Scenario: Renamed skill for second client
- **WHEN** client "linkding-biz" has `agent-skills.enabled = true` and `name = "linkding-biz"`
- **THEN** `programs.agent-skills.skills.explicit.linkding-biz` SHALL have `rename = "linkding-biz"` and its own `packages` list with the biz CLI wrapper

### Requirement: Delegation to programs.agent-deck
When `agent-deck.mcp.enabled = true`, the generated HM module SHALL add an entry to `programs.agent-deck.mcps.<client-name>` with the linkding MCP server connection details.

#### Scenario: Agent-deck MCP entry added
- **WHEN** client "linkding" has `agent-deck.mcp.enabled = true`
- **THEN** `programs.agent-deck.mcps.linkding` SHALL contain the MCP server configuration

#### Scenario: Two clients with distinct agent-deck entries
- **WHEN** clients "linkding" and "linkding-biz" both have `agent-deck.mcp.enabled = true`
- **THEN** `programs.agent-deck.mcps` SHALL contain both `linkding` and `linkding-biz` entries with distinct configurations

### Requirement: Delegation to programs.openclaw
When `openclaw.skill.enabled = true`, the generated HM module SHALL append a skill entry to `programs.openclaw.skills` with `mode = "symlink"` or `"inline"` pointing to the co-located skill content, using the client name as the skill name.

#### Scenario: OpenClaw skill added
- **WHEN** client "linkding-biz" has `openclaw.skill.enabled = true`
- **THEN** `programs.openclaw.skills` SHALL contain an entry with `name = "linkding-biz"` and the linkding skill content

### Requirement: Delegation to programs.claude-tools
When `claude-tools.enabled = true`, the generated HM module SHALL add the appropriate skill or plugin identifier using `programs.claude-tools.skills-installer.skillsByClient` (the `attrsOf` mode) for better module merging, or `programs.claude-tools.claude-plugins.plugins` for marketplace plugins.

#### Scenario: Marketplace skill installed via skillsByClient
- **WHEN** client "linkding" has `claude-tools.enabled = true`
- **THEN** `programs.claude-tools.skills-installer.skillsByClient.claude-code` SHALL include the linkding skill identifier

### Requirement: Per-client CLI wrapper script
When `cli.enabled = true`, the generated HM module SHALL add a per-client wrapper script to `home.packages`. Each wrapper SHALL be a `writeShellApplication` that exports `LINKDING_API_TOKEN` (read from the clan vars secret file path) and `LINKDING_BASE_URL` (from settings), then execs the base linkding-cli. The wrapper binary name SHALL be the client's `name`.

#### Scenario: Two CLI wrappers with baked-in config
- **WHEN** clients have `name = "linkding"` and `name = "linkding-biz"` with `cli.enabled = true`
- **THEN** `home.packages` SHALL contain two distinct wrapper scripts
- **AND** the `linkding` wrapper SHALL export the personal client's token and URL before exec
- **AND** the `linkding-biz` wrapper SHALL export the business client's token and URL before exec

#### Scenario: CLI wrapper reads token from clan vars path
- **WHEN** a CLI wrapper is executed
- **THEN** it SHALL read the API token from the file at the clan vars secret path captured in the perInstance closure
- **AND** it SHALL export `LINKDING_BASE_URL` with the client's configured `base_url`

### Requirement: Enable flags are independent
Each integration flag SHALL be independently toggleable. Enabling one integration SHALL NOT require or imply enabling any other.

#### Scenario: CLI only
- **WHEN** only `cli.enabled = true` and all other flags are false
- **THEN** only the CLI wrapper SHALL be added to `home.packages` and no other downstream HM modules SHALL be configured

#### Scenario: MCP without skill
- **WHEN** `claude-code.mcp.enabled = true` but `claude-code.skill.enabled = false`
- **THEN** `programs.claude-code.mcpServers.<client-name>` SHALL be configured but `programs.claude-code.skills.<client-name>` SHALL NOT be set
