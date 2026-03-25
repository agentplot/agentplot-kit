# agentplot-kit

## mkClientTooling
- Skill keys: always `${serviceName}-${clientNameId}`, never bare `clientNameId`
- CLI wrappers use `writeShellApplication` — shellcheck runs; avoid SC2155 (`export VAR="$(cmd)"`)
- `extraPackages` are added to `home.packages` (global), CLI wrappers are scoped per-client

## claude-code HM Module
- `programs.claude-code.skills` type: `attrsOf (either lines path)` — also accepts derivations (checked via `? outPath`)
- Skill directories from `mkSkillDir` are derivations, not literal paths — dispatch must handle both
