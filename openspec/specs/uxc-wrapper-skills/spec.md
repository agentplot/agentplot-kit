### Requirement: Every UXC-projectable capability requires a committed wrapper skill

`mkClientTooling` SHALL fail evaluation if a service declares any UXC-projectable capability (`mcp` or `openapi`) but does NOT ship a wrapper-skill directory for that protocol. The directory MUST contain `SKILL.md`, `agents/openai.yaml`, `references/usage-patterns.md`, and `scripts/validate.sh`.

The wrapper-skill location SHALL be either:
- A conventional path (e.g., `services/<serviceName>/skills/<protocol>/`) auto-discovered by `mkClientTooling`, OR
- An explicit `endpoint.skill = ./path/to/skill-dir` capability field

#### Scenario: Service ships UXC capability without skill

- **WHEN** a service declares `capabilities.openapi = { ... }` but no `services/<svc>/skills/openapi/` directory exists and no `openapi.skill` is set
- **THEN** evaluation SHALL fail with an error message that names the service, the protocol, and the recipe to invoke (`nix run .#author-skill -- <serviceName> openapi`)

#### Scenario: Service ships valid skill directory

- **WHEN** a service declares `capabilities.openapi = { ... }` and ships `services/<svc>/skills/openapi/` containing the four required files
- **THEN** evaluation SHALL succeed and the skill directory SHALL flow through the existing `capabilities.skills` plumbing for client projection

### Requirement: `apps.author-skill` recipe LLM-authors wrapper skills at service-author time

`agentplot-kit`'s flake SHALL expose `apps.<system>.author-skill` invokable as `nix run .#author-skill -- <serviceName> <protocol>`. The recipe SHALL:

1. Extract `{ host, linkName, authType, schemaSource }` from the service's capability declaration via `nix eval`
2. Resolve `schemaSource` to readable content (file path or URL)
3. Spawn `claude --print` (or equivalent SDK call) with the vendored `uxc-skill-creator` skill loaded and the capability context as input
4. Capture LLM output to `services/<serviceName>/skills/<protocol>/`
5. Run `scripts/validate.sh` against the output
6. On validation failure, re-prompt with errors and retry up to 3 times
7. On success, write a `.source-spec-hash` sidecar containing `sha256(spec content)`
8. On exhausted retries, leave artifacts in place and exit non-zero with diagnostics

The recipe SHALL require `ANTHROPIC_API_KEY` in environment; absent that, exit early with a clear error.

#### Scenario: Recipe authors a new skill successfully

- **WHEN** a contributor runs `nix run .#author-skill -- atomic openapi` with `ANTHROPIC_API_KEY` set and atomic's capability declaration including a static `openapi.json` schemaSource
- **THEN** `services/atomic/skills/openapi/` SHALL exist with the four required files
- **AND** running `services/atomic/skills/openapi/scripts/validate.sh` SHALL exit 0
- **AND** `services/atomic/skills/openapi/.source-spec-hash` SHALL contain the SHA-256 of `services/atomic/openapi.json`

#### Scenario: Recipe retries on validation failure

- **WHEN** the LLM emits output that fails `scripts/validate.sh` on the first attempt (e.g., missing `command -v <link_name>` line)
- **THEN** the recipe SHALL re-invoke claude with the validation error as additional context
- **AND** SHALL accept output that passes validation on attempts 2 or 3
- **AND** SHALL exit non-zero with diagnostics if attempt 3 still fails

#### Scenario: Recipe missing API key

- **WHEN** a contributor runs the recipe without `ANTHROPIC_API_KEY` set
- **THEN** the recipe SHALL exit non-zero with a message instructing how to set the key

### Requirement: `uxc-skill-creator` is vendored under `agentplot-kit/skills/`

`agentplot-kit` SHALL vendor the upstream `uxc-skill-creator` skill at `skills/uxc-skill-creator/` (or a versioned directory under `skills/`). The vendored copy SHALL be loaded by the `author-skill` recipe and SHALL be installable on a contributor's claude-code profile via the standard `programs.claude-code.skills` mechanism.

The vendored copy SHALL track an upstream version recorded in flake.lock (or equivalent pinning). Sync to a newer upstream version SHALL surface as a flake-input bump PR.

#### Scenario: Vendored skill is loadable by the recipe

- **WHEN** the recipe constructs the claude invocation
- **THEN** it SHALL pass `--skill agentplot-kit:uxc-skill-creator` (or the project's equivalent flag) referring to the vendored path
- **AND** the LLM session SHALL have access to the skill's references and templates

### Requirement: Spec-hash sidecar drives drift detection

Every committed wrapper skill SHALL include a `.source-spec-hash` file containing the SHA-256 of the spec content used at last regeneration. `nix flake check` SHALL include a check that recomputes the current spec's SHA-256 and fails if it does not match the sidecar.

For URL-sourced specs, the check SHALL fetch the URL at check time and hash the response. For MCP services without a formal spec, the sidecar SHALL hash a committed fixture file (`<skill-dir>/fixtures/help-output.txt` or similar) capturing `uxc <host> -h` output.

#### Scenario: Spec changed without skill regen

- **WHEN** a contributor modifies `services/atomic/openapi.json` and commits without re-running the recipe
- **THEN** `nix flake check` SHALL fail with an error pointing at the mismatched skill and the recipe to re-run

#### Scenario: Skill regenerated after spec change

- **WHEN** a contributor modifies `services/atomic/openapi.json`, runs the recipe, and commits both
- **THEN** `nix flake check` SHALL pass

### Requirement: `scripts/validate.sh` enforces uxc-skill-creator's hard rules at build time

Each wrapper skill's `scripts/validate.sh` SHALL implement uxc-skill-creator's documented validation rules: required files exist; frontmatter has `name` and `description`; `command -v <link>` and `<link> -h` lines are present; banned legacy patterns (e.g., `--input-json`, raw `uxc <host> list`) are absent. `nix flake check` SHALL run each skill's `validate.sh` and fail the check on any non-zero exit.

#### Scenario: Skill missing link-first pattern

- **WHEN** a skill's `SKILL.md` lacks the `command -v <link_name>` line
- **THEN** `validate.sh` SHALL exit non-zero
- **AND** `nix flake check` SHALL surface that failure with the skill path and the failed assertion

### Requirement: Per-client `linkName` overrides flow through the existing skill substitution path

`mkSkillContent` (in `lib/mkClientTooling.nix`) SHALL extend its substitution table to rewrite the canonical link-name pattern `${serviceName}-<protocol>-cli` to the resolved per-client `linkName` when overridden, so committed skills authored against the default link name still produce correct output for clients with overrides.

#### Scenario: Default linkName, no substitution needed

- **WHEN** a client has no `uxc.linkName` override
- **THEN** the skill text SHALL pass through unchanged

#### Scenario: Per-client linkName override

- **WHEN** a client overrides `openapi.linkName = "atomic-personal-api"`
- **THEN** every occurrence of `atomic-openapi-cli` in the committed skill SHALL be rewritten to `atomic-personal-api` for that client's projected skill copy
- **AND** the SKILL.md frontmatter `name:` field SHALL be rewritten consistently
