# mkClientTooling — generate a complete clanService client role from a capabilities declaration.
#
# Arguments:
#   serviceName       — string, the service name (e.g., "linkding")
#   capabilities      — attrset with optional keys: skills, mcp, cli, secret
#   extraClientOptions — module function returning extra options for the client submodule
#
# Returns: { interface; perInstance; } suitable for roles.client in a clanService.
{
  serviceName,
  capabilities ? { },
  extraClientOptions ? null,
}:
let
  # Normalize capabilities with defaults
  skills = capabilities.skills or null;   # list of paths (each to a SKILL.md or skill directory) or null
  mcp = capabilities.mcp or null;         # { type, urlTemplate } or null
  cli = capabilities.cli or null;         # { package, wrapperName, envVars } or null
  secret = capabilities.secret or null;   # { name, mode, description? } or null

  hasSkills = skills != null && skills != [ ];
  hasMcp = mcp != null;
  hasCli = cli != null;
  hasSecret = secret != null;

  # Derive skill entries from paths: accepts both SKILL.md file paths and skill directories.
  # ./skills/foo/SKILL.md → { name = "foo"; path = ./skills/foo/SKILL.md; dir = ./skills/foo; }
  # ./skills/foo           → { name = "foo"; path = ./skills/foo/SKILL.md; dir = ./skills/foo; }
  # For single-skill services at ./skills/SKILL.md, the skill name = serviceName
  skillEntries =
    if !hasSkills then [ ]
    else builtins.map (skillInput:
      let
        isFile = builtins.hasSuffix "SKILL.md" (builtins.baseNameOf (toString skillInput));
        dir = if isFile then builtins.dirOf skillInput else skillInput;
        skillMd = if isFile then skillInput else "${skillInput}/SKILL.md";
        dirName = builtins.baseNameOf dir;
      in {
        name = if dirName == "skills" then serviceName else dirName;
        path = skillMd;
        dir = dir;
      }
    ) skills;
in
{
  # ── Interface ────────────────────────────────────────────────────────────────
  interface = { lib, ... }:
    let
      profileSubmodule = lib.types.submodule {
        options.mcp.enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Add ${serviceName} MCP server entry to this Claude Code profile";
        };
      };

      clientSubmodule = lib.types.submodule ({ name, ... }: {
        options = builtins.foldl' lib.recursiveUpdate {
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Integration identifier and CLI binary name";
          };
        } (builtins.filter (x: x != { }) [
          # Skill-consuming targets (only when capabilities.skills is provided)
          (lib.optionalAttrs hasSkills {
            claude-code.skill.enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Install Claude Code agent skill for ${serviceName}";
            };
            agent-skills.enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Distribute skill via agent-skills module";
            };
            openclaw.skill.enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Add OpenClaw skill";
            };
            agent-deck.skill.enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Add skill to agent-deck skill pool";
            };
          })
          # MCP-consuming targets (only when capabilities.mcp is provided)
          (lib.optionalAttrs hasMcp {
            claude-code.mcp.enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Configure Claude Code MCP server (default profile)";
            };
            claude-code.profiles = lib.mkOption {
              type = lib.types.attrsOf profileSubmodule;
              default = { };
              description = "Per-profile MCP configuration for Claude Code";
            };
            agent-deck.mcp.enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Add agent-deck MCP entry";
            };
          })
          # CLI target (only when capabilities.cli is provided)
          (lib.optionalAttrs hasCli {
            cli.enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Install per-client CLI wrapper script";
            };
          })
          # Extra service-specific options
          (if extraClientOptions != null then
            extraClientOptions { inherit lib; }
          else { })
        ]);
      });
    in
    {
      options.clients = lib.mkOption {
        type = lib.types.attrsOf clientSubmodule;
        default = { };
        description = "Named client configurations for ${serviceName} instances";
      };
    };

  # ── Per Instance ─────────────────────────────────────────────────────────────
  perInstance = { settings, ... }:
    let
      clientModule = { config, pkgs, lib, ... }:
        let
          mkClientConfig = clientName: clientSettings:
            let
              clientNameId = clientSettings.name;

              # Secret path (if secret capability is declared)
              tokenPath =
                if hasSecret then
                  config.clan.core.vars.generators."agentplot-${serviceName}-${clientName}-${secret.name}".files."${secret.name}".path
                else null;

              # CLI wrapper (if cli capability is declared)
              cliWrapper =
                if hasCli then
                  let
                    basePkg = if builtins.isPath cli.package
                      then pkgs.callPackage cli.package { }
                      else cli.package;
                    wrapperName = if cli ? wrapperName then cli.wrapperName clientSettings else clientNameId;
                    envVarAttrs = if cli ? envVars then cli.envVars (clientSettings // { inherit tokenPath; }) else { };
                    envExports = lib.concatStringsSep "\n" (
                      lib.mapAttrsToList (k: v: ''
                        export ${k}="${v}"
                      '') envVarAttrs
                    );
                  in
                  pkgs.writeShellApplication {
                    name = wrapperName;
                    runtimeInputs = [ basePkg ];
                    text = ''
                      ${envExports}
                      exec ${builtins.baseNameOf (lib.getExe basePkg)} "$@"
                    '';
                  }
                else null;

              # Per-skill content substitution
              mkSkillContent = entry:
                builtins.replaceStrings
                  [ "name: ${serviceName}" "${serviceName}-cli" ]
                  [ "name: ${clientNameId}" clientNameId ]
                  (builtins.readFile entry.path);

              # MCP config (if mcp capability is declared)
              mcpConfig =
                if hasMcp then
                  let
                    url = mcp.urlTemplate clientSettings;
                  in
                  { inherit url; } // lib.optionalAttrs (mcp.type == "http") { type = "http"; }
                    // lib.optionalAttrs (mcp ? tokenFile && tokenPath != null) { tokenFile = tokenPath; }
                else null;
            in
            {
              # Clan vars generator for this client's secret
              vars = lib.optionalAttrs hasSecret {
                "agentplot-${serviceName}-${clientName}-${secret.name}" =
                  if secret.mode == "prompted" then {
                    prompts."${secret.name}" = {
                      type = "hidden";
                      description =
                        if secret ? description then secret.description clientSettings
                        else "${secret.name} for ${serviceName} client '${clientName}'";
                    };
                    files."${secret.name}" = {
                      secret = true;
                    } // lib.optionalAttrs (config ? agentplot && config.agentplot.user != null) {
                      owner = config.agentplot.user;
                      group = "staff";
                    };
                    script = ''
                      cp "$prompts/${secret.name}" "$out/${secret.name}"
                    '';
                  }
                  else {
                    # generated mode
                    share = true;
                    files."${secret.name}" = {
                      secret = true;
                      mode = "0440";
                    } // lib.optionalAttrs (config ? agentplot && config.agentplot.user != null) {
                      owner = config.agentplot.user;
                      group = "staff";
                    };
                    runtimeInputs = [ pkgs.openssl ];
                    script = ''
                      openssl rand -hex 32 > $out/${secret.name}
                    '';
                  };
              };

              # HM module for this client
              hmModule = { ... }:
                let
                  # Skill-related options (guarded by hasSkills)
                  skillEnabled = hasSkills && (clientSettings.claude-code.skill.enabled or false);
                  agentSkillsEnabled = hasSkills && (clientSettings.agent-skills.enabled or false);
                  openclawEnabled = hasSkills && (clientSettings.openclaw.skill.enabled or false);
                  agentDeckSkillEnabled = hasSkills && (clientSettings.agent-deck.skill.enabled or false);

                  # MCP-related options (guarded by hasMcp)
                  ccMcpEnabled = hasMcp && (clientSettings.claude-code.mcp.enabled or false);
                  ccProfiles = if hasMcp then (clientSettings.claude-code.profiles or { }) else { };
                  adMcpEnabled = hasMcp && (clientSettings.agent-deck.mcp.enabled or false);

                  # CLI option (guarded by hasCli)
                  cliEnabled = hasCli && (clientSettings.cli.enabled or false);
                in
                lib.mkMerge [
                  # CLI wrapper package
                  (lib.mkIf (cliEnabled && cliWrapper != null) {
                    home.packages = [ cliWrapper ];
                  })

                  # Claude Code skill (when agent-skills not taking over)
                  # Pass the skill directory as a path so multi-file skill directories
                  # are accessible to claude-code (uses `either lines path` type)
                  (lib.mkIf (skillEnabled && !agentSkillsEnabled) {
                    programs.claude-code.skills = builtins.listToAttrs (
                      builtins.map (entry: {
                        name = if builtins.length skillEntries == 1 then clientNameId else "${clientNameId}-${entry.name}";
                        value = entry.dir;
                      }) skillEntries
                    );
                  })

                  # Claude Code MCP (default profile)
                  (lib.mkIf ccMcpEnabled {
                    programs.claude-code.mcpServers.${clientNameId} = mcpConfig;
                  })

                  # Claude Code MCP (per-profile)
                  (lib.mkIf (ccProfiles != { }) {
                    programs.claude-code.profiles = lib.mapAttrs (
                      _profileName: profileSettings:
                      lib.mkIf profileSettings.mcp.enabled {
                        mcpServers.${clientNameId} = mcpConfig;
                      }
                    ) ccProfiles;
                  })

                  # Agent-skills delegation
                  (lib.mkIf agentSkillsEnabled {
                    programs.agent-skills = {
                      enable = true;
                      sources."agentplot-${serviceName}" = {
                        path = (builtins.head skillEntries).dir;
                      };
                    } // {
                      skills.explicit = builtins.listToAttrs (
                        builtins.map (entry:
                          let
                            skillKey = if builtins.length skillEntries == 1 then clientNameId else "${clientNameId}-${entry.name}";
                          in {
                            name = skillKey;
                            value = {
                              from = "agentplot-${serviceName}";
                              transform = { original, ... }:
                                builtins.replaceStrings
                                  [ "name: ${serviceName}" "${serviceName}-cli" ]
                                  [ "name: ${clientNameId}" clientNameId ]
                                  original;
                            } // lib.optionalAttrs (cliWrapper != null) {
                              packages = [ cliWrapper ];
                            };
                          }
                        ) skillEntries
                      );
                      targets.claude.enable = true;
                    };
                  })

                  # Agent-deck MCP
                  (lib.mkIf adMcpEnabled {
                    programs.agent-deck.mcps.${clientNameId} = mcpConfig;
                  })

                  # Agent-deck skill pool
                  (lib.mkIf agentDeckSkillEnabled {
                    programs.agent-deck.skillSources = builtins.listToAttrs (
                      builtins.map (entry: {
                        name = if builtins.length skillEntries == 1 then clientNameId else "${clientNameId}-${entry.name}";
                        value = entry.dir;
                      }) skillEntries
                    );
                  })

                  # OpenClaw skill
                  (lib.mkIf openclawEnabled {
                    programs.openclaw.skills = builtins.map (entry: {
                      name = if builtins.length skillEntries == 1 then clientNameId else "${clientNameId}-${entry.name}";
                      mode = "inline";
                      body = mkSkillContent entry;
                      description =
                        let content = builtins.readFile entry.path;
                            # Extract description from frontmatter
                            lines = lib.splitString "\n" content;
                            descLines = builtins.filter (l: lib.hasPrefix "description:" l) lines;
                        in if descLines != [ ]
                           then lib.removePrefix "description: " (builtins.head descLines)
                           else "${serviceName} skill";
                    }) skillEntries;
                  })
                ];
            };

          clientConfigs = lib.mapAttrs mkClientConfig settings.clients;
        in
        {
          # Register clan vars generators for all clients
          clan.core.vars.generators = lib.mkMerge (
            lib.mapAttrsToList (_: cc: cc.vars) clientConfigs
          );

          # Wire HM modules through the agentplot passthrough
          agentplot.hmModules = lib.mapAttrs' (
            clientName: cc:
            lib.nameValuePair "${serviceName}-${clientName}" cc.hmModule
          ) clientConfigs;
        };
    in
    {
      nixosModule = clientModule;
      darwinModule = clientModule;
    };
}
