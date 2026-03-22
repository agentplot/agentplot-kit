## ADDED Requirements

### Requirement: Skill directory as canonical unit
mkClientTooling SHALL accept skill directories (paths to directories containing SKILL.md) in `capabilities.skills` in addition to direct SKILL.md file paths. A skill directory MUST contain a file named `SKILL.md` at its root. Sibling files and subdirectories within the skill directory are preserved for directory-aware downstream targets.

#### Scenario: Skill directory path provided
- **WHEN** a skill entry in `capabilities.skills` is a path to a directory containing SKILL.md (e.g., `${src}/skills/gno`)
- **THEN** mkClientTooling SHALL derive `entry.dir` as that directory, `entry.path` as `${dir}/SKILL.md`, and `entry.name` as the directory basename

#### Scenario: SKILL.md file path provided (backward compat)
- **WHEN** a skill entry in `capabilities.skills` is a path to a SKILL.md file (e.g., `./skills/foo/SKILL.md`)
- **THEN** mkClientTooling SHALL derive `entry.dir` as `builtins.dirOf` of the path, `entry.path` as the given path, and `entry.name` as the parent directory basename — identical to current behavior

#### Scenario: Root-level SKILL.md path
- **WHEN** a skill entry path resolves to a SKILL.md whose parent directory is named "skills"
- **THEN** `entry.name` SHALL default to `serviceName` — identical to current behavior

### Requirement: mkUpstreamSkills helper
A new function `lib.mkUpstreamSkills` SHALL resolve upstream source trees into a list of skill directory paths consumable by `capabilities.skills`.

#### Scenario: Single-skill upstream repo
- **WHEN** called with `{ src = fetchFromGitHub { owner = "gmickel"; repo = "gno"; ... }; include = [ "gno" ]; }`
- **THEN** the function SHALL return a list containing one path: `${src}/skills/gno`

#### Scenario: Multi-skill upstream repo
- **WHEN** called with `{ src = fetchFromGitHub { owner = "ogham-mcp"; repo = "ogham-mcp"; ... }; }` and no `include` filter
- **THEN** the function SHALL return paths for all subdirectories under `${src}/skills/` that contain a SKILL.md file

#### Scenario: Custom skills directory
- **WHEN** called with `{ src = ...; skillsDir = "agent-skills"; include = [ "foo" ]; }`
- **THEN** the function SHALL look under `${src}/agent-skills/foo` instead of the default `${src}/skills/foo`

#### Scenario: Flake input source
- **WHEN** called with `{ src = inputs.gno; include = [ "gno" ]; }`
- **THEN** the function SHALL resolve `${inputs.gno}/skills/gno` as the skill directory path

#### Scenario: Package store path
- **WHEN** called with `{ src = pkgs.gno.src; include = [ "gno" ]; }`
- **THEN** the function SHALL resolve `${pkgs.gno.src}/skills/gno` as the skill directory path

### Requirement: Directory-aware downstream delegation
mkClientTooling SHALL pass the full skill directory to directory-aware downstream targets and the SKILL.md content to text-only targets.

#### Scenario: agent-skills receives full directory
- **WHEN** agent-skills delegation is enabled for a skill with sibling reference files (e.g., gno with cli-reference.md, examples.md)
- **THEN** `programs.agent-skills.sources` SHALL point to the skill directory containing SKILL.md and all sibling files

#### Scenario: agent-deck receives full directory
- **WHEN** agent-deck skill pool is enabled for a multi-file skill
- **THEN** `programs.agent-deck.skillSources` SHALL point to the skill directory containing SKILL.md and all sibling files

#### Scenario: claude-code receives directory as path
- **WHEN** claude-code skill is enabled (Phase 1, not delegating to agent-skills) for a multi-file skill
- **THEN** `programs.claude-code.skills.<name>` SHALL be set to the skill directory path (using the `path` type of `either lines path`)

#### Scenario: openclaw receives SKILL.md content only
- **WHEN** openclaw skill is enabled for a multi-file skill
- **THEN** `programs.openclaw.skills` SHALL receive inline text from `builtins.readFile entry.path` (SKILL.md only), with sibling files not included

### Requirement: Content substitution scope
The `mkSkillContent` function SHALL only perform per-client name substitution on SKILL.md content. Sibling files within a skill directory SHALL NOT undergo content substitution.

#### Scenario: SKILL.md content substituted
- **WHEN** a skill's SKILL.md contains `name: ${serviceName}` and the client is named "linkding-biz"
- **THEN** the substituted content SHALL replace `name: ${serviceName}` with `name: linkding-biz`

#### Scenario: Sibling files not substituted
- **WHEN** a skill directory contains `cli-reference.md` with references to the service name
- **THEN** `cli-reference.md` SHALL be passed through unchanged to directory-aware targets

### Requirement: Backward compatibility
Existing `capabilities.skills` lists using SKILL.md file paths SHALL continue to produce identical downstream configurations.

#### Scenario: Existing single-skill service unchanged
- **WHEN** a clanService uses `skills = [ ./skills/SKILL.md ]` (current format)
- **THEN** all downstream target outputs (claude-code, agent-skills, agent-deck, openclaw) SHALL be identical to the output before this change

#### Scenario: Existing multi-skill service unchanged
- **WHEN** a clanService uses `skills = [ ./skills/foo/SKILL.md ./skills/bar/SKILL.md ]` (current format)
- **THEN** all downstream target outputs SHALL be identical to the output before this change
