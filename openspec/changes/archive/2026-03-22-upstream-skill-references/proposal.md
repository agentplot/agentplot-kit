## Why

mkClientTooling only accepts local paths to individual SKILL.md files (`skills = [ ./skills/cli/SKILL.md ]`). Upstream tools like gno, qmd, ogham-mcp, and subcog ship their own skill folders on GitHub — often with multi-file directories containing references, examples, and MCP docs alongside SKILL.md. There is no way to consume these upstream skill directories without manually copying them into local trees.

## What Changes

- Extend `capabilities.skills` to accept **skill directory references** in addition to individual SKILL.md paths. A skill directory is any directory containing a SKILL.md at its root, optionally with sibling reference files.
- Add a `mkUpstreamSkills` helper that resolves upstream skill sources (Nix package store paths, `fetchFromGitHub` results, or flake input source trees) into the skill entry format mkClientTooling expects.
- Update downstream delegation logic so directory-aware targets (agent-skills, agent-deck) receive the full skill directory, while text-only targets (claude-code Phase 1, openclaw) receive the concatenated/transformed SKILL.md content.
- Preserve backward compatibility: existing `[ ./skills/foo/SKILL.md ]` paths continue to work unchanged.

## Capabilities

### New Capabilities
- `upstream-skill-resolution`: Resolving upstream GitHub skill folders into consumable skill entries, supporting three source types: package store paths, fetchFromGitHub, and flake input source trees.

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **lib/mkClientTooling.nix**: Core skill entry derivation logic (lines 26-39) and all five downstream delegation blocks
- **lib/mkUpstreamSkills.nix** (new): Helper for resolving upstream skill sources
- **Downstream modules**: No changes required — claude-code already accepts `either lines path`, agent-skills uses directory sources, agent-deck uses directory paths, openclaw uses inline text
- **clanService consumers** (in agentplot repo): Services like gno, qmd, ogham-mcp, subcog will switch from local skill copies to upstream references
