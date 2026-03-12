{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude-code;
  jsonFormat = pkgs.formats.json { };

  transformedMcpServers = lib.optionalAttrs (cfg.enableMcpIntegration && config.programs.mcp.enable) (
    lib.mapAttrs (
      name: server:
      (removeAttrs server [ "disabled" ])
      // (lib.optionalAttrs (server ? url) { type = "http"; })
      // (lib.optionalAttrs (server ? command) { type = "stdio"; })
      // {
        enabled = !(server.disabled or false);
      }
    ) config.programs.mcp.servers
  );

  # Structured agent submodule (cherry-picked from devenv)
  agentSubmodule = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "What the sub-agent does.";
      };

      proactive = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether Claude should use this sub-agent automatically.";
      };

      tools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of allowed tools for this sub-agent.";
      };

      model = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "opus"
            "sonnet"
            "haiku"
          ]
        );
        default = null;
        description = "Override the model for this agent.";
      };

      permissionMode = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "default"
            "acceptEdits"
            "plan"
            "bypassPermissions"
          ]
        );
        default = null;
        description = "Permission mode for this specific sub-agent.";
      };

      prompt = lib.mkOption {
        type = lib.types.lines;
        description = "The system prompt for the sub-agent.";
      };
    };
  };

  # Shared content options used by both top-level and profiles
  mkContentOptions =
    { isProfile }:
    {
      configDir = lib.mkOption {
        type = lib.types.str;
        description = "Config directory path relative to home directory.";
      } // (if isProfile then { } else { default = ".claude"; });

      settings = lib.mkOption {
        inherit (jsonFormat) type;
        default = { };
        example = {
          theme = "dark";
          permissions = {
            allow = [
              "Bash(git diff:*)"
              "Edit"
            ];
            deny = [ "WebFetch" ];
            defaultMode = "acceptEdits";
          };
        };
        description = "JSON configuration for Claude Code settings.json";
      };

      agents = lib.mkOption {
        type = lib.types.attrsOf agentSubmodule;
        default = { };
        description = ''
          Custom sub-agents for Claude Code.
          Each agent gets a structured YAML frontmatter markdown file in the agents directory.
        '';
        example = lib.literalExpression ''
          {
            code-reviewer = {
              description = "Expert code review specialist";
              proactive = true;
              model = "opus";
              tools = [ "Read" "Grep" "TodoWrite" ];
              permissionMode = "plan";
              prompt = '''
                You are an expert code reviewer. Check for quality, security, and best practices.
              ''';
            };
          }
        '';
      };

      commands = lib.mkOption {
        type = lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path);
        default = { };
        description = ''
          Custom commands for Claude Code.
          The attribute name becomes the command filename, and the value is either:
          - Inline content as a string
          - A path to a file containing the command content
          Commands are stored in <configDir>/commands/ directory.
        '';
      };

      hooks = lib.mkOption {
        type = lib.types.attrsOf lib.types.lines;
        default = { };
        description = ''
          Custom hooks for Claude Code.
          The attribute name becomes the hook filename, and the value is the hook script content.
          Hooks are stored in <configDir>/hooks/ directory.
        '';
      };

      memory = {
        text = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          description = ''
            Inline memory content for CLAUDE.md.
            This option is mutually exclusive with memory.source.
          '';
        };

        source = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a file containing memory content for CLAUDE.md.
            This option is mutually exclusive with memory.text.
          '';
        };
      };

      rules = lib.mkOption {
        type = lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path);
        default = { };
        description = ''
          Modular rule files for Claude Code.
          Rules are stored in <configDir>/rules/ directory.
        '';
      };

      rulesDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a directory containing rule files for Claude Code.";
      };

      agentsDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a directory containing agent files for Claude Code.";
      };

      commandsDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a directory containing command files for Claude Code.";
      };

      hooksDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a directory containing hook files for Claude Code.";
      };

      outputStyles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path);
        default = { };
        description = ''
          Custom output styles for Claude Code.
          Written to <configDir>/output-styles/<name>.md
        '';
      };

      skills = lib.mkOption {
        type = lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path);
        default = { };
        description = ''
          Custom skills for Claude Code.
          The attribute name becomes the skill directory name.
          - Inline string or file path creates <configDir>/skills/<name>/SKILL.md
          - A directory path creates <configDir>/skills/<name>/ with all files
        '';
      };

      skillsDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a directory containing skill directories for Claude Code.";
      };

      mcpServers = lib.mkOption {
        type = lib.types.attrsOf jsonFormat.type;
        default = { };
        description = "MCP (Model Context Protocol) servers configuration.";
      };
    };

  # Generate home.file entries from a content config attrset
  mkHomeFiles =
    conf:
    let
      cd = conf.configDir;
    in
    {
      "${cd}/settings.json" = lib.mkIf (conf.settings != { }) {
        source = jsonFormat.generate "claude-code-settings.json" (
          conf.settings
          // {
            "$schema" = "https://json.schemastore.org/claude-code-settings.json";
          }
        );
      };

      "${cd}/CLAUDE.md" = lib.mkIf (conf.memory.text != null || conf.memory.source != null) (
        if conf.memory.text != null then { text = conf.memory.text; } else { source = conf.memory.source; }
      );

      "${cd}/rules" = lib.mkIf (conf.rulesDir != null) {
        source = conf.rulesDir;
        recursive = true;
      };

      "${cd}/agents" = lib.mkIf (conf.agentsDir != null) {
        source = conf.agentsDir;
        recursive = true;
      };

      "${cd}/commands" = lib.mkIf (conf.commandsDir != null) {
        source = conf.commandsDir;
        recursive = true;
      };

      "${cd}/hooks" = lib.mkIf (conf.hooksDir != null) {
        source = conf.hooksDir;
        recursive = true;
      };

      "${cd}/skills" = lib.mkIf (conf.skillsDir != null) {
        source = conf.skillsDir;
        recursive = true;
      };
    }
    // lib.mapAttrs' (
      name: content:
      lib.nameValuePair "${cd}/rules/${name}.md" (
        if lib.isPath content then { source = content; } else { text = content; }
      )
    ) conf.rules
    // lib.mapAttrs' (
      name: agent:
      lib.nameValuePair "${cd}/agents/${name}.md" {
        text =
          let
            toolsLine =
              if agent.tools != [ ] then
                "tools: ${lib.concatStringsSep ", " agent.tools}"
              else
                null;
            modelLine = if agent.model != null then "model: ${agent.model}" else null;
            permLine =
              if agent.permissionMode != null then
                "permissionMode: ${agent.permissionMode}"
              else
                null;
            frontmatterLines = lib.filter (x: x != null) [
              "name: ${name}"
              "description: ${agent.description}"
              "proactive: ${lib.boolToString agent.proactive}"
              toolsLine
              modelLine
              permLine
            ];
          in
          ''
            ---
            ${lib.concatStringsSep "\n" frontmatterLines}
            ---

            ${agent.prompt}
          '';
      }
    ) conf.agents
    // lib.mapAttrs' (
      name: content:
      lib.nameValuePair "${cd}/commands/${name}.md" (
        if lib.isPath content then { source = content; } else { text = content; }
      )
    ) conf.commands
    // lib.mapAttrs' (
      name: content:
      lib.nameValuePair "${cd}/hooks/${name}" { text = content; }
    ) conf.hooks
    // lib.mapAttrs' (
      name: content:
      if lib.isPath content && lib.pathIsDirectory content then
        lib.nameValuePair "${cd}/skills/${name}" {
          source = content;
          recursive = true;
        }
      else
        lib.nameValuePair "${cd}/skills/${name}/SKILL.md" (
          if lib.isPath content then { source = content; } else { text = content; }
        )
    ) conf.skills
    // lib.mapAttrs' (
      name: content:
      lib.nameValuePair "${cd}/output-styles/${name}.md" (
        if lib.isPath content then { source = content; } else { text = content; }
      )
    ) conf.outputStyles;

  # Generate assertions for a content config
  mkAssertions =
    conf: prefix:
    [
      {
        assertion = !(conf.memory.text != null && conf.memory.source != null);
        message = "Cannot specify both `${prefix}.memory.text` and `${prefix}.memory.source`";
      }
      {
        assertion = !(conf.rules != { } && conf.rulesDir != null);
        message = "Cannot specify both `${prefix}.rules` and `${prefix}.rulesDir`";
      }
      {
        assertion = !(conf.agents != { } && conf.agentsDir != null);
        message = "Cannot specify both `${prefix}.agents` and `${prefix}.agentsDir`";
      }
      {
        assertion = !(conf.commands != { } && conf.commandsDir != null);
        message = "Cannot specify both `${prefix}.commands` and `${prefix}.commandsDir`";
      }
      {
        assertion = !(conf.hooks != { } && conf.hooksDir != null);
        message = "Cannot specify both `${prefix}.hooks` and `${prefix}.hooksDir`";
      }
      {
        assertion = !(conf.skills != { } && conf.skillsDir != null);
        message = "Cannot specify both `${prefix}.skills` and `${prefix}.skillsDir`";
      }
    ];

  # Profile submodule type
  profileModule = lib.types.submodule {
    options = mkContentOptions { isProfile = true; };
  };
in
{
  meta.maintainers = [ lib.maintainers.khaneliman ];

  options.programs.claude-code =
    {
      enable = lib.mkEnableOption "Claude Code, Anthropic's official CLI";

      package = lib.mkPackageOption pkgs "claude-code" { nullable = true; };

      finalPackage = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        internal = true;
        description = "Resulting customized claude-code package.";
      };

      enableMcpIntegration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to integrate the MCP servers config from
          {option}`programs.mcp.servers` into
          {option}`programs.claude-code.mcpServers`.

          Note: Settings defined in {option}`programs.mcp.servers` are merged
          with {option}`programs.claude-code.mcpServers`, with Claude Code servers
          taking precedence.
        '';
      };

      dangerouslySkipPermissions = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Add the --dangerously-skip-permissions flag to the wrapped binary.
          This bypasses all permission checks. Use with extreme caution.
        '';
      };

      profiles = lib.mkOption {
        type = lib.types.attrsOf profileModule;
        default = { };
        description = ''
          Additional Claude Code config directories with independent settings.
          Each profile creates its own config directory with its own settings,
          agents, commands, hooks, rules, skills, and MCP servers.
          Useful for identity isolation with agent-deck profiles.
        '';
        example = lib.literalExpression ''
          {
            business = {
              configDir = ".claude-business";
              settings = {
                permissions.defaultMode = "bypassPermissions";
              };
            };
            client = {
              configDir = ".claude-client";
              settings = {
                permissions.defaultMode = "default";
              };
            };
          }
        '';
      };
    }
    // mkContentOptions { isProfile = false; };

  config = lib.mkIf cfg.enable {
    assertions =
      [
        {
          assertion = (cfg.mcpServers == { } && !cfg.enableMcpIntegration) || cfg.package != null;
          message = "`programs.claude-code.package` cannot be null when `mcpServers` or `enableMcpIntegration` is configured";
        }
        {
          assertion =
            let
              allDirs = [ cfg.configDir ] ++ map (p: p.configDir) (lib.attrValues cfg.profiles);
            in
            lib.unique allDirs == allDirs;
          message = "Duplicate configDir values across programs.claude-code default and profiles. Each configDir must be unique.";
        }
      ]
      ++ mkAssertions cfg "programs.claude-code"
      ++ lib.concatMap (
        name: mkAssertions cfg.profiles.${name} "programs.claude-code.profiles.${name}"
      ) (lib.attrNames cfg.profiles);

    programs.claude-code.finalPackage =
      let
        mergedMcpServers = transformedMcpServers // cfg.mcpServers;
        makeWrapperArgs = lib.flatten (
          lib.filter (x: x != [ ]) [
            (lib.optional (cfg.mcpServers != { } || transformedMcpServers != { }) [
              "--append-flags"
              "--mcp-config ${
                jsonFormat.generate "claude-code-mcp-config.json" { mcpServers = mergedMcpServers; }
              }"
            ])
            (lib.optional cfg.dangerouslySkipPermissions [
              "--append-flags"
              "--dangerously-skip-permissions"
            ])
          ]
        );

        hasWrapperArgs = makeWrapperArgs != [ ];
      in
      if hasWrapperArgs then
        pkgs.symlinkJoin {
          name = "claude-code";
          paths = [ cfg.package ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/claude ${lib.escapeShellArgs makeWrapperArgs}
          '';
          inherit (cfg.package) meta;
        }
      else
        cfg.package;

    home = {
      packages = lib.mkIf (cfg.package != null) [ cfg.finalPackage ];

      file =
        mkHomeFiles cfg
        // lib.foldl' (acc: profileCfg: acc // mkHomeFiles profileCfg) { } (
          lib.attrValues cfg.profiles
        );
    };
  };
}
