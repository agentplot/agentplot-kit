# tests/uxc.nix — eval tests for UXC projection + mkClientTooling gating.
#
# Run: nix eval --json .#tests.uxc
# Returns: { passed = N; failed = N; results = [ { name; passed; detail?; } ]; }
{ lib ? (builtins.getFlake (toString ../.)).inputs.nixpkgs.lib }:
let
  mkUxcProjection = import ../lib/mkUxcProjection.nix;
  mkClientTooling = import ../lib/mkClientTooling.nix;

  skillDir = ./fixtures/uxc-skill;

  # ── Helpers ──────────────────────────────────────────────────────────────
  assert' = name: cond: { inherit name; passed = cond; };
  assertEq = name: actual: expected: {
    inherit name;
    passed = actual == expected;
    detail =
      if actual == expected then null
      else "expected: ${builtins.toJSON expected}, got: ${builtins.toJSON actual}";
  };
  # Force a mkClientTooling interface to WHNF, catching eval-time guard throws.
  evalSucceeds = capabilities:
    (builtins.tryEval (mkClientTooling { serviceName = "testsvc"; inherit capabilities; }).interface).success;

  bearer = secret: { inherit secret; type = "bearer"; };
  opSecret = name: ref: { inherit name; mode = "op"; reference = ref; };

  # ── 11.1 openapi-only projects one credential, binding, link ───────────────
  test_openapi_only =
    let
      proj = mkUxcProjection {
        inherit lib;
        serviceName = "atomic";
        clientName = "personal";
        clientSettings = { domain = "atomic.swancloud.net"; };
        endpoints = [
          {
            protocol = "openapi";
            host = c: c.domain;
            pathPrefix = "/api";
            schemaSource = { type = "url"; url = "https://x/openapi.json"; };
            auth = bearer "admin-token";
          }
        ];
        secrets = [ (opSecret "admin-token" "op://Personal/Atomic/token") ];
        referencedSecrets = [ "admin-token" ];
      };
      # Service declaring only openapi evaluates (with a wrapper skill present).
      svcEvals = evalSucceeds {
        secret = [ (opSecret "admin-token" "op://V/I/f") ];
        openapi = {
          host = "x.net";
          schemaSource = { type = "url"; url = "https://x"; };
          auth = bearer "admin-token";
          skill = skillDir;
        };
      };
    in [
      (assertEq "openapi-only: one credential" (builtins.length (builtins.attrNames proj.credentials)) 1)
      (assertEq "openapi-only: one binding" (builtins.length proj.bindings) 1)
      (assertEq "openapi-only: one link" (builtins.length (builtins.attrNames proj.links)) 1)
      (assert' "openapi-only: link is atomic-openapi-cli" (proj.links ? "atomic-openapi-cli"))
      (assert' "openapi-only: service with only openapi evaluates" svcEvals)
    ];

  # ── 11.2 shared op secret across mcp+openapi → 1 credential, 2 bindings ─────
  test_shared_credential =
    let
      proj = mkUxcProjection {
        inherit lib;
        serviceName = "atomic";
        clientName = "personal";
        clientSettings = { domain = "atomic.swancloud.net"; };
        endpoints = [
          { protocol = "mcp"; urlTemplate = c: "https://${c.domain}/mcp"; auth = bearer "admin-token"; }
          {
            protocol = "openapi";
            host = c: c.domain;
            pathPrefix = "/api";
            schemaSource = { type = "static"; path = ./fixtures/uxc-skill/SKILL.md; };
            auth = bearer "admin-token";
          }
        ];
        secrets = [ (opSecret "admin-token" "op://Personal/Atomic/token") ];
        referencedSecrets = [ "admin-token" ];
      };
    in [
      (assertEq "shared-cred: exactly one credential" (builtins.length (builtins.attrNames proj.credentials)) 1)
      (assertEq "shared-cred: exactly two bindings" (builtins.length proj.bindings) 2)
      (assert' "shared-cred: both bindings share the credential"
        (builtins.all (b: b.credential == "agentplot-atomic-personal-admin-token") proj.bindings))
    ];

  # ── 11.3 unknown auth.secret → eval failure ────────────────────────────────
  test_unknown_secret =
    let
      ok = evalSucceeds {
        secret = [ (opSecret "admin-token" "op://V/I/f") ];
        openapi = {
          host = "x.net";
          schemaSource = { type = "url"; url = "https://x"; };
          auth = bearer "does-not-exist";
          skill = skillDir;
        };
      };
    in [
      (assert' "unknown-secret: evaluation fails" (!ok))
    ];

  # ── 11.4 non-op auth.secret → UXC projection failure ───────────────────────
  test_non_op_secret =
    let
      attempt = builtins.tryEval (
        let
          proj = mkUxcProjection {
            inherit lib;
            serviceName = "x";
            clientName = "personal";
            clientSettings = { };
            endpoints = [
              {
                protocol = "openapi";
                host = "x.net";
                schemaSource = { type = "url"; url = "https://x"; };
                auth = bearer "fs-token";
              }
            ];
            secrets = [ { name = "fs-token"; mode = "prompted"; } ];
            referencedSecrets = [ "fs-token" ];
          };
        in builtins.deepSeq proj true
      );
    in [
      (assert' "non-op: UXC projection fails" (!attempt.success))
    ];

  # ── 11.5 projection JSON matches the expected shape (snapshot) ──────────────
  test_snapshot =
    let
      proj = mkUxcProjection {
        inherit lib;
        serviceName = "atomic";
        clientName = "personal";
        clientSettings = { domain = "atomic.swancloud.net"; };
        endpoints = [
          { protocol = "mcp"; urlTemplate = c: "https://${c.domain}/mcp"; auth = bearer "admin-token"; }
          {
            protocol = "openapi";
            host = "atomic.swancloud.net";
            pathPrefix = "/api";
            schemaSource = { type = "url"; url = "https://atomic.swancloud.net/api/openapi.json"; };
            auth = bearer "admin-token";
          }
        ];
        secrets = [ (opSecret "admin-token" "op://Personal/Atomic/token") ];
        referencedSecrets = [ "admin-token" ];
      };
      expected = {
        credentials = {
          "agentplot-atomic-personal-admin-token" = {
            auth_type = "bearer";
            secret_source = { kind = "op"; reference = "op://Personal/Atomic/token"; };
          };
        };
        bindings = [
          {
            id = "agentplot-atomic-personal-mcp";
            scheme = "https";
            host = "atomic.swancloud.net";
            path_prefix = "/mcp";
            credential = "agentplot-atomic-personal-admin-token";
            priority = 100;
            enabled = true;
          }
          {
            id = "agentplot-atomic-personal-openapi";
            scheme = "https";
            host = "atomic.swancloud.net";
            path_prefix = "/api";
            credential = "agentplot-atomic-personal-admin-token";
            priority = 100;
            enabled = true;
          }
        ];
        links = {
          "atomic-mcp-cli" = { host = "https://atomic.swancloud.net/mcp"; };
          "atomic-openapi-cli" = {
            host = "atomic.swancloud.net";
            schemaUrl = "https://atomic.swancloud.net/api/openapi.json";
          };
        };
      };
    in [
      (assertEq "snapshot: projection matches expected JSON" proj expected)
    ];

  # ── 11.6 legacy MCP (no auth) needs no wrapper skill (backward compat) ──────
  test_legacy_mcp =
    let
      ok = evalSucceeds {
        mcp = { type = "http"; urlTemplate = c: "https://${c.domain}/mcp"; };
        secret = [ { name = "token"; mode = "prompted"; } ];
      };
    in [
      (assert' "legacy-mcp: no-auth MCP evaluates without a wrapper skill" ok)
    ];

  # ── Aggregate ──────────────────────────────────────────────────────────────
  allResults =
    test_openapi_only
    ++ test_shared_credential
    ++ test_unknown_secret
    ++ test_non_op_secret
    ++ test_snapshot
    ++ test_legacy_mcp;

  passed = builtins.length (builtins.filter (r: r.passed) allResults);
  failed = builtins.length (builtins.filter (r: !r.passed) allResults);
in
{
  inherit passed failed;
  results = allResults;
}
