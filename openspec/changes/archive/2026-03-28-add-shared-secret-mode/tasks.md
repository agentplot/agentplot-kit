## 1. Secret Normalization

- [x] 1.1 Normalize `capabilities.secret` to a list (`secrets`): accept single attrset, list, or null; replace `hasSecret` with `secrets != []`
- [x] 1.2 Update `hasSecret` guard and remove old singular `secret` binding after normalization

## 2. Shared Mode — secretPaths Resolution

- [x] 2.1 Build `secretPaths` attrset from `secrets` list: for `shared` mode, resolve to `config.clan.core.vars.generators.${s.generator}.files.${s.file}.path`; for `prompted`/`generated`, resolve to existing per-client generator path
- [x] 2.2 Remove old `tokenPath` variable entirely — all consumers use `secretPaths` keyed by secret name

## 3. Vars Generator Registration

- [x] 3.1 Filter `secrets` to only `prompted` and `generated` modes when building `vars` attrset — skip `shared` entries
- [x] 3.2 Support multiple non-shared secrets in the generator attrset (one generator key per non-shared secret)

## 4. CLI Wrapper Integration

- [x] 4.1 Pass `secretPaths` to `cli.envVars` callback via `clientSettings`
- [x] 4.2 Verify SC2155 compliance in env exports (existing `declare`/`export` split pattern)

## 5. MCP Config Integration

- [x] 5.1 Add `mcp.extraConfig` callback support: call with `clientSettings` (including `secretPaths`) and merge result into MCP config
- [x] 5.2 Add backward compat shim: if `mcp.tokenFile` is present but `mcp.extraConfig` is not, synthesize `extraConfig` from first secret path
- [x] 5.3 Remove hardcoded `tokenFile` logic from `mcpConfig` builder

## 6. Verification

- [x] 6.1 Update existing services that reference `tokenPath` in `cli.envVars` to use `secretPaths.<name>`
- [x] 6.2 Confirm existing services (linkding, paperless, etc.) still evaluate without changes
- [x] 6.3 Test a subcog-style multi-secret shared config evaluates correctly (both secretPaths resolve)
