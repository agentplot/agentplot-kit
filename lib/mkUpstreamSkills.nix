# mkUpstreamSkills — resolve upstream source trees into skill directory paths.
#
# Arguments:
#   src       — source tree (fetchFromGitHub, flake input, or package .src)
#   skillsDir — relative path to skills root within src (default: "skills")
#   include   — optional list of skill directory names to include (default: null = all)
#
# Returns: list of paths, each pointing to a skill directory containing SKILL.md.
{ src, skillsDir ? "skills", include ? null }:
let
  skillsRoot = "${src}/${skillsDir}";

  # Auto-discover: list subdirectories under skillsRoot that contain SKILL.md
  discoverSkillDirs =
    let
      entries = builtins.readDir skillsRoot;
      dirNames = builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries);
      hasSkillMd = name: builtins.pathExists "${skillsRoot}/${name}/SKILL.md";
    in
    builtins.filter hasSkillMd dirNames;

  selectedDirs =
    if include != null then include
    else discoverSkillDirs;
in
builtins.map (name: "${skillsRoot}/${name}") selectedDirs
