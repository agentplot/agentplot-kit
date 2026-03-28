# agentplot-kit

## mkClientTooling
- Skill keys: always `${serviceName}-${clientNameId}`, never bare `clientNameId`
- CLI wrappers use `writeShellApplication` — shellcheck runs; avoid SC2155 (`export VAR="$(cmd)"`)
- `extraPackages` are added to `home.packages` (global), CLI wrappers are scoped per-client
- `secret` accepts single attrset or list; normalized to `secrets` list internally
- Secret modes: `prompted` (interactive), `generated` (openssl rand, share=true), `shared` (references existing server-side generator by name)
- `secretPaths` attrset (keyed by secret name) replaces old `tokenPath`; passed to `cli.envVars` and `mcp.extraConfig` callbacks
- `mcp.extraConfig` callback replaces hardcoded `tokenFile` — services declare their own MCP config fields

## claude-code HM Module
- `programs.claude-code.skills` type: `attrsOf (either lines path)` — also accepts derivations (checked via `? outPath`)
- Skill directories from `mkSkillDir` are derivations, not literal paths — dispatch must handle both
