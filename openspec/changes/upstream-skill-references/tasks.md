## 1. mkUpstreamSkills helper

- [ ] 1.1 Create `lib/mkUpstreamSkills.nix` — takes `{ src, skillsDir ? "skills", include ? null }` and returns a list of skill directory paths. When `include` is null, auto-discover all subdirectories containing SKILL.md under `${src}/${skillsDir}/`.
- [ ] 1.2 Export `lib.mkUpstreamSkills` in flake.nix alongside existing `lib.mkClientTooling`

## 2. Skill entry normalization in mkClientTooling

- [ ] 2.1 Update `skillEntries` derivation (lines 26-39) to detect whether each entry is a SKILL.md file path or a skill directory path, and normalize both to `{ name, path, dir }` — file paths use `builtins.dirOf`, directory paths append `/SKILL.md`
- [ ] 2.2 Verify backward compat: existing `[ ./skills/foo/SKILL.md ]` inputs produce identical `skillEntries` output

## 3. Directory-aware downstream delegation

- [ ] 3.1 Update claude-code Phase 1 delegation (lines 244-251) to pass `entry.dir` as a path instead of inline text from `mkSkillContent`, so multi-file skill directories are accessible to claude-code
- [ ] 3.2 Verify agent-skills delegation (lines 268-297) already uses `entry.dir` for sources — confirm no changes needed
- [ ] 3.3 Verify agent-deck delegation (lines 305-312) already uses `entry.dir` for skillSources — confirm no changes needed
- [ ] 3.4 Verify openclaw delegation (lines 314-329) continues to use `builtins.readFile entry.path` for inline text — confirm no changes needed

## 4. Content substitution

- [ ] 4.1 Ensure `mkSkillContent` (lines 166-170) continues to operate on `entry.path` (SKILL.md only), not on sibling files — verify scope is correct after normalization changes

## 5. Integration testing

- [ ] 5.1 Add test case: single-skill upstream directory (e.g., gno-style with sibling reference files) — verify all four downstream targets produce correct output
- [ ] 5.2 Add test case: multi-skill upstream directory (e.g., ogham-mcp-style with 3 skill subdirs) — verify skill naming and delegation for all targets
- [ ] 5.3 Add test case: backward compat — existing SKILL.md file paths produce unchanged output across all targets
- [ ] 5.4 Add test case: mkUpstreamSkills with `include` filter — verify only specified skill dirs are returned
- [ ] 5.5 Add test case: mkUpstreamSkills auto-discovery — verify all SKILL.md-containing subdirs are found when `include` is null
