# tests/upstream-skills.nix — integration tests for upstream skill references
#
# Run: nix eval --json .#tests.upstream-skills
# Returns: { passed = N; failed = N; results = [ { name; passed; detail?; } ]; }
{ lib ? (builtins.getFlake (toString ../.)).inputs.nixpkgs.lib }:
let
  mkUpstreamSkills = import ../lib/mkUpstreamSkills.nix;

  fixturesDir = ./fixtures;

  # ── Helpers ──────────────────────────────────────────────────────────────────
  assert' = name: cond: {
    inherit name;
    passed = cond;
  };

  assertEq = name: actual: expected: {
    inherit name;
    passed = actual == expected;
    detail = if actual == expected then null
             else "expected: ${builtins.toJSON expected}, got: ${builtins.toJSON actual}";
  };

  # Simulate mkClientTooling's skillEntries normalization (extracted for testing)
  normalizeSkillEntries = serviceName: skills:
    builtins.map (skillInput:
      let
        baseName = builtins.baseNameOf (toString skillInput);
        isFile = baseName == "SKILL.md";
        dir = if isFile then builtins.dirOf skillInput else skillInput;
        skillMd = if isFile then skillInput else "${skillInput}/SKILL.md";
        dirName = builtins.baseNameOf dir;
      in {
        name = if dirName == "skills" then serviceName else dirName;
        path = toString skillMd;
        dir = toString dir;
      }
    ) skills;

  # ── Test Cases ───────────────────────────────────────────────────────────────

  # 5.1 Single-skill upstream directory (gno-style)
  test_single_upstream =
    let
      skillDirs = mkUpstreamSkills {
        src = "${fixturesDir}/upstream-single";
        include = [ "gno" ];
      };
      entries = normalizeSkillEntries "test-service" skillDirs;
      entry = builtins.head entries;
    in [
      (assertEq "single-upstream: returns one dir" (builtins.length skillDirs) 1)
      (assert' "single-upstream: dir ends with skills/gno"
        (lib.hasSuffix "skills/gno" (builtins.head skillDirs)))
      (assertEq "single-upstream: entry name is gno" entry.name "gno")
      (assert' "single-upstream: entry.path ends with SKILL.md"
        (lib.hasSuffix "SKILL.md" entry.path))
      (assert' "single-upstream: entry.dir ends with skills/gno"
        (lib.hasSuffix "skills/gno" entry.dir))
      (assert' "single-upstream: SKILL.md is readable"
        (builtins.isString (builtins.readFile entry.path)))
      # Verify sibling files exist in the directory
      (assert' "single-upstream: cli-reference.md exists"
        (builtins.pathExists "${entry.dir}/cli-reference.md"))
      (assert' "single-upstream: examples.md exists"
        (builtins.pathExists "${entry.dir}/examples.md"))
    ];

  # 5.2 Multi-skill upstream directory (ogham-mcp-style)
  test_multi_upstream =
    let
      skillDirs = mkUpstreamSkills {
        src = "${fixturesDir}/upstream-multi";
      };
      entries = normalizeSkillEntries "test-service" skillDirs;
      entryNames = builtins.map (e: e.name) entries;
    in [
      (assertEq "multi-upstream: discovers 3 skill dirs" (builtins.length skillDirs) 3)
      (assert' "multi-upstream: no-skill-here excluded"
        (!(builtins.any (d: lib.hasSuffix "no-skill-here" d) skillDirs)))
      (assert' "multi-upstream: ogham-maintain included"
        (builtins.elem "ogham-maintain" entryNames))
      (assert' "multi-upstream: ogham-recall included"
        (builtins.elem "ogham-recall" entryNames))
      (assert' "multi-upstream: ogham-research included"
        (builtins.elem "ogham-research" entryNames))
    ];

  # 5.3 Backward compat — SKILL.md file paths
  test_backward_compat =
    let
      skillPath = "${fixturesDir}/backward-compat/skills/foo/SKILL.md";
      entries = normalizeSkillEntries "test-service" [ skillPath ];
      entry = builtins.head entries;
    in [
      (assertEq "backward-compat: entry count" (builtins.length entries) 1)
      (assertEq "backward-compat: name derived from parent dir" entry.name "foo")
      (assert' "backward-compat: path is original SKILL.md"
        (lib.hasSuffix "foo/SKILL.md" entry.path))
      (assert' "backward-compat: dir is parent of SKILL.md"
        (lib.hasSuffix "skills/foo" entry.dir))
      (assert' "backward-compat: content is readable"
        (builtins.isString (builtins.readFile entry.path)))
    ];

  # 5.4 mkUpstreamSkills with include filter
  test_include_filter =
    let
      skillDirs = mkUpstreamSkills {
        src = "${fixturesDir}/upstream-multi";
        include = [ "ogham-maintain" "ogham-recall" ];
      };
    in [
      (assertEq "include-filter: returns exactly 2" (builtins.length skillDirs) 2)
      (assert' "include-filter: ogham-maintain present"
        (builtins.any (d: lib.hasSuffix "ogham-maintain" d) skillDirs))
      (assert' "include-filter: ogham-recall present"
        (builtins.any (d: lib.hasSuffix "ogham-recall" d) skillDirs))
      (assert' "include-filter: ogham-research excluded"
        (!(builtins.any (d: lib.hasSuffix "ogham-research" d) skillDirs)))
    ];

  # 5.5 mkUpstreamSkills auto-discovery
  test_auto_discovery =
    let
      skillDirs = mkUpstreamSkills {
        src = "${fixturesDir}/upstream-multi";
      };
      dirNames = builtins.map builtins.baseNameOf skillDirs;
    in [
      (assertEq "auto-discovery: finds 3 skill dirs" (builtins.length skillDirs) 3)
      (assert' "auto-discovery: excludes dirs without SKILL.md"
        (!(builtins.elem "no-skill-here" dirNames)))
      (assert' "auto-discovery: all returned dirs have SKILL.md"
        (builtins.all (d: builtins.pathExists "${d}/SKILL.md") skillDirs))
    ];

  # ── Aggregate ────────────────────────────────────────────────────────────────
  allResults = test_single_upstream
    ++ test_multi_upstream
    ++ test_backward_compat
    ++ test_include_filter
    ++ test_auto_discovery;

  passed = builtins.length (builtins.filter (r: r.passed) allResults);
  failed = builtins.length (builtins.filter (r: !r.passed) allResults);
in {
  inherit passed failed;
  results = allResults;
}
