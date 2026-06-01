# Downstream illustration — swancloud

Grounds the UXC change in the real consumer (`~/Code/github_afterthought/swancloud`).
Shows the two server classes side by side per partition, and the three-stage
transition from pure MCP → ad-hoc uxc links (today) → declarative uxc (this change).

Identity partitions map to claude-code profiles:

| Partition | claude-code profile | configDir |
|-----------|---------------------|-----------|
| personal  | default             | `.claude`          |
| business  | business            | `.claude-business` |
| willdan (client) | willdan      | `.claude-willdan`  |
| willdan-bedrock  | willdan-bedrock | `.claude-willdan-bedrock` |

Two server classes — the whole point of the design seam (D16):

- **First-party (kit owns it)** → declared once via `mkClientTooling`, auto-projected
  into `programs.uxc.*`. Carries a kit-managed secret lifecycle (clan vars / `op://`),
  a wrapper-skill gate, sometimes a packaged binary. Examples in swancloud: `atomic`
  (OpenAPI + MCP), `paperless` (per-client domain).
- **Third-party (you consume it)** → declared by swancloud directly on the same
  `programs.uxc.*` options. No kit lifecycle. Examples: `deepwiki`, `context7`,
  `github`, `cua`, `zoho`, `workiq`.

---

## Stage 0 — pure MCP (before any uxc)

Every selected server is an always-on stdio/http child per Claude session. Tokens
live in the ambient shell env. Per-partition selection is a plain list.

```nix
# lib/agent-config.nix (real today)
mcpServers = {
  deepwiki = { type = "http"; url = "https://mcp.deepwiki.com/mcp"; };
  cua      = { type = "http"; url = "https://vk-mcp.cua.ai/mcp"; };
  context7 = { command = "${pkgs.nodejs}/bin/npx"; args = [ "-y" "@upstash/context7-mcp@latest" ]; };
  github   = { command = "${githubMcpBinary}/bin/github-mcp-server"; args = [ "stdio" "--toolsets" "default,projects" ]; };
  zoho     = { type = "http"; url = "https://…zohomcp.com/…/message"; };
  workiq   = { command = "${pkgs.nodejs}/bin/npx"; args = [ "-y" "@microsoft/workiq" "mcp" ]; };
};

partitions = {
  personal = [ "github" "context7" "deepwiki" "cua" "workiq" ];
  business = [ "github" "context7" "deepwiki" "cua" "zoho" "workiq" ];
  willdan  = [ "github" "context7" "deepwiki" "cua" "workiq" ];
};
```

```nix
# modules/home-claude-code.nix (pure-MCP form)
programs.claude-code.mcpServers = selectionFor "personal";  # 5 stdio/http children/session
programs.claude-code.profiles.business.mcpServers = selectionFor "business";
programs.claude-code.profiles.willdan.mcpServers  = selectionFor "willdan";
```

Costs: N children per session, every tool schema loaded into context, tokens in env.

---

## Stage 1 — ad-hoc uxc links (swancloud TODAY)

`modules/home-uxc.nix` already exists. It makes a `<name>-mcp-cli` link for **all**
servers and zeroes out `mcpServers`. But it is hand-rolled `writeShellScriptBin`,
ignores `partitions`, writes no `credentials.json`, and still relies on ambient env.

```nix
# modules/home-uxc.nix (real today — crude)
mkLink = name: srv: pkgs.writeShellScriptBin "${name}-mcp-cli" ''
  UXC_LINK_NAME='${name}-mcp-cli' exec ${pkgs.uxc}/bin/uxc '${hostOf srv}' "$@"
'';
home.packages = lib.mapAttrsToList mkLink agentConfig.mcpServers;   # ALL servers, every profile
```

```nix
# modules/home-claude-code.nix (real today)
mcpServers = { };   # no children spawn; reach servers via `<name>-mcp-cli` + uxc skill
```

Gaps this change closes: no per-partition link sets, no Nix-managed credentials,
no first-party projection path (atomic/paperless still hand-wired), env-only secrets.

---

## Stage 2 — declarative uxc (this change)

`mkClientTooling` projects first-party services into `programs.uxc.*`. swancloud
declares third-party servers on the **same** options. The kit's `uxc.nix` renders
the merged result. Per-partition selection drives which links land per profile.

### First-party: `atomic` and `paperless` through uxc

Declared once in the service capability; projected automatically when the client
sets `uxc.enabled = true`. No swancloud-side uxc wiring for these.

```nix
# clan inventory — atomic service client (per partition)
services.atomic.clients.personal = {
  uxc.enabled = true;            # → programs.uxc.links."atomic-openapi-cli" + "atomic-mcp-cli"
  claude-code.mcp.enabled = false;   # MCP now fronted by uxc, not a native child
};
services.atomic.clients.business.uxc.enabled = true;
services.atomic.clients.willdan.uxc.enabled  = true;
```

Projection result (kit-generated, illustrative):

```nix
# what mkClientTooling writes onto the personal profile's HM config
programs.uxc.credentials."agentplot-atomic-personal-admin-token" = {
  auth_type = "bearer";
  secret_source = { kind = "op"; reference = "op://swancloud/atomic/admin-token"; };
};
programs.uxc.bindings = [
  { id = "agentplot-atomic-personal-openapi"; host = "atomic.swancloud.net"; path_prefix = "/api";
    credential = "agentplot-atomic-personal-admin-token"; priority = 10; }
  { id = "agentplot-atomic-personal-mcp"; host = "atomic.swancloud.net"; path_prefix = "/mcp";
    credential = "agentplot-atomic-personal-admin-token"; priority = 10; }
];
programs.uxc.links."atomic-openapi-cli" = { host = "atomic.swancloud.net"; schemaUrl = "file:///nix/store/…-atomic-openapi.json"; };
programs.uxc.links."atomic-mcp-cli"     = { host = "https://atomic.swancloud.net/mcp"; };
```

`paperless` is the per-client-domain case (D10) — same shape, `host = client: client.domain`.

### Third-party: `deepwiki` and friends through uxc

swancloud declares these directly. Same options, no `mkClientTooling`. deepwiki has
no auth → just a link. context7/github carry an env token → `injectEnv` (no `op://`
credential needed; keeps the existing ambient-env secret flow).

```nix
# modules/home-uxc.nix (declarative form — replaces the writeShellScriptBin loop)
let thirdParty = {
  deepwiki = { host = "https://mcp.deepwiki.com/mcp"; };
  cua      = { host = "https://vk-mcp.cua.ai/mcp"; };
  context7 = { host = "command:${pkgs.nodejs}/bin/npx -y @upstash/context7-mcp@latest";
               injectEnv = { CONTEXT7_API_KEY = "$CONTEXT7_API_KEY"; }; };
  github   = { host = "command:${githubMcpBinary}/bin/github-mcp-server stdio --toolsets default,projects";
               injectEnv = { GITHUB_PERSONAL_ACCESS_TOKEN = "$GITHUB_PERSONAL_ACCESS_TOKEN"; }; };
  zoho     = { host = "https://…zohomcp.com/…/message"; };
  workiq   = { host = "command:${pkgs.nodejs}/bin/npx -y @microsoft/workiq mcp"; };
};
# honor the per-partition selection that Stage 1 ignored
linksFor = partition: lib.getAttrs agentConfig.partitions.${partition} thirdParty;
in {
  programs.uxc.enable = true;
  programs.uxc.links = linksFor "personal";   # github context7 deepwiki cua workiq — NOT zoho
}
```

### Merge — one credentials.json, both classes

Per profile, the rendered `~/.uxc/` is the module-merged union:

| Partition | first-party links (projected) | third-party links (declared) |
|-----------|-------------------------------|------------------------------|
| personal  | `atomic-openapi-cli`, `atomic-mcp-cli` | github, context7, deepwiki, cua, workiq |
| business  | `atomic-*`                    | github, context7, deepwiki, cua, **zoho**, workiq |
| willdan   | `atomic-*`, `paperless-openapi-cli` | github, context7, deepwiki, cua, workiq |

`credentials.json` holds only what auth needs: the `op://` atomic admin-token
(first-party). deepwiki/cua = none; context7/github/zoho/workiq = env-injected at the
link, so no credential entry. A name clash (e.g. swancloud declaring `atomic-mcp-cli`)
fails eval — see the collision assertion (D16).

---

## What stays in claude-code vs uxc

- `claude-code.mcpServers` → `{ }` for everything fronted by uxc (already true in
  swancloud). A server can stay a native child if you *want* its schemas auto-loaded.
- `claude-code.mcp.enabled` / `uxc.enabled` are independent per client — a service can
  be claude-code-direct, uxc, or both during migration.
- Channel launchers (`claude-discord`, `claude-imessage` → willdan profile) are
  unaffected; they inherit whatever the willdan profile's uxc links resolve to.

## Migration order (per partition, reversible)

1. Service-side: declare `openapi`/`mcp` capability + `op` secret + wrapper skill on
   `atomic`/`paperless`; set `uxc.enabled = true`, `claude-code.mcp.enabled = false`.
2. Consumer-side: replace the `writeShellScriptBin` loop with declarative
   `programs.uxc.links` honoring `partitions`; keep `injectEnv` for env-token servers.
3. Verify `<link> -h` resolves and `atomic-openapi-cli` authenticates via `op://`.
4. Drop any now-dead native `mcpServers` entries (already `{ }` here).
