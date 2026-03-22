## Context

mkClientTooling currently accepts `capabilities.skills` as a list of paths pointing to individual SKILL.md files. It derives skill entries (`{ name, path, dir }`) by parsing directory structure: `./skills/foo/SKILL.md` yields name "foo", path to the file, and dir to its parent.

Upstream tools ship skill folders on GitHub with varying structures:
- **gno**: `skills/gno/` — SKILL.md + cli-reference.md + examples.md + mcp-reference.md (multi-file)
- **qmd**: `skills/qmd/` — SKILL.md + references/mcp-setup.md (subdirectory)
- **ogham-mcp**: 3 single-file skill dirs (ogham-maintain, ogham-recall, ogham-research)
- **subcog**: 3 single-file skill dirs (memory-capture, memory-recall, subcog-integrator)

Downstream targets have different consumption models:
- **claude-code** (Phase 1): `attrsOf (either lines path)` — accepts inline text or path (path can be a directory)
- **agent-skills**: directory-based `sources` + `skills.explicit` with transforms
- **agent-deck**: `skillSources = attrsOf path` — directory symlinks
- **openclaw**: `listOf { name, mode, body }` — inline text only

## Goals / Non-Goals

**Goals:**
- Allow clanService definitions to reference skill directories from upstream Nix packages, `fetchFromGitHub` results, or flake input source trees
- Preserve the full skill directory (SKILL.md + sibling files) for directory-aware targets (agent-skills, agent-deck, claude-code path mode)
- Gracefully degrade to SKILL.md-only for text-only targets (openclaw, claude-code lines mode)
- Maintain full backward compatibility with existing `[ ./skills/foo/SKILL.md ]` path lists

**Non-Goals:**
- Runtime fetching of skills (all resolution happens at Nix evaluation/build time)
- Automatic discovery of skills within an upstream repo (callers explicitly declare which skill dirs to use)
- Modifying downstream HM module interfaces (they already support the needed types)
- Supporting non-GitHub upstream sources (git forges only for now)

## Decisions

### 1. Unify on skill directories as the canonical unit

**Decision**: The fundamental skill unit becomes a **directory containing SKILL.md**, not an individual SKILL.md file path.

**Rationale**: All four upstream repos use directories (even single-file skills live in named directories). All directory-aware downstream targets (agent-skills, agent-deck) already consume directories. The current SKILL.md path approach is a special case of this — `builtins.dirOf` already extracts the directory.

**Alternative considered**: Keep SKILL.md paths as canonical and add a separate `skillDirs` option. Rejected because it creates parallel paths through the same delegation logic with no benefit.

### 2. Accept both path formats in `capabilities.skills`

**Decision**: `capabilities.skills` accepts a list where each element is either:
- A path to a SKILL.md file (backward compat: `./skills/foo/SKILL.md`)
- A path to a skill directory containing SKILL.md (new: `./skills/foo` or `${src}/skills/foo`)

**Rationale**: Backward compatibility requires accepting SKILL.md paths. Upstream repos naturally provide directory paths from source trees. The normalization logic detects which format was provided by checking if the path is a directory or if its basename is "SKILL.md".

### 3. Introduce `mkUpstreamSkills` helper for source resolution

**Decision**: Create `lib/mkUpstreamSkills.nix` that takes an upstream source attrset and returns a list of skill directory paths suitable for `capabilities.skills`.

**Interface**:
```nix
mkUpstreamSkills {
  src = <source>;              # fetchFromGitHub, flake input, or package
  skillsDir = "skills";       # relative path to skills root (default: "skills")
  include = [ "gno" ];        # optional: specific skill dirs to include (default: all)
}
# Returns: [ /nix/store/.../skills/gno ]
```

**Rationale**: Separates source resolution from skill consumption. clanService definitions call `mkUpstreamSkills` once and pass the result to `capabilities.skills`. This keeps mkClientTooling itself source-agnostic.

**Alternative considered**: Embed source resolution directly into mkClientTooling via a new `upstreamSkills` capability key. Rejected because it mixes concerns — mkClientTooling handles delegation, not fetching.

### 4. Normalize skill entries in mkClientTooling

**Decision**: Replace the current `skillEntries` derivation (lines 26-39) with normalization that handles both formats:

```nix
skillEntries = builtins.map (skillInput:
  let
    isFile = lib.hasSuffix "SKILL.md" (builtins.baseNameOf (toString skillInput));
    dir = if isFile then builtins.dirOf skillInput else skillInput;
    skillMd = if isFile then skillInput else "${skillInput}/SKILL.md";
    dirName = builtins.baseNameOf dir;
  in {
    name = if dirName == "skills" then serviceName else dirName;
    path = skillMd;
    dir = dir;
  }
) skills;
```

**Rationale**: Minimal change to existing logic. The `dir` field already exists and is used by agent-skills and agent-deck. The `path` field continues to point to SKILL.md for text-extraction targets.

### 5. Directory-aware delegation per target

**Decision**: Each downstream delegation block uses the appropriate field:

| Target | Uses `entry.dir` (full directory) | Uses `entry.path` (SKILL.md only) |
|--------|----------------------------------|-----------------------------------|
| claude-code (Phase 1, no agent-skills) | Yes — pass dir as path type | Fallback: readFile for inline |
| agent-skills | Yes — `sources` registration | No |
| agent-deck | Yes — `skillSources` | No |
| openclaw | No | Yes — `readFile` for inline body |

Claude-code's `attrsOf (either lines path)` type means we can pass the directory directly when the skill has sibling files, giving claude-code access to the full skill folder. For openclaw (text-only), we continue reading just SKILL.md.

## Risks / Trade-offs

**[Risk] Upstream skill directory structure varies** → Mitigation: The only contract is "directory contains SKILL.md at root". Sibling files are passed through to directory-aware targets without interpretation. Text-only targets always read just SKILL.md.

**[Risk] `builtins.readFile` on store paths from `fetchFromGitHub`** → Mitigation: Nix `builtins.readFile` works on any store path, including those from `fetchFromGitHub`. No special handling needed.

**[Risk] Content substitution (`mkSkillContent`) may miss references in sibling files** → Mitigation: Substitution only applies to SKILL.md content (CLI name rewriting). Sibling reference files don't contain per-client names, so no substitution needed. If future skills need sibling file substitution, that's a separate enhancement.

**[Trade-off] `mkUpstreamSkills` requires callers to know `skillsDir` path** → Acceptable because skill directory locations are stable conventions in upstream repos and are documented.
