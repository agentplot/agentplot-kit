# mkClientTooling — generate a complete clanService client role from a capabilities declaration.
#
# Arguments:
#   serviceName       — string, the service name (e.g., "linkding")
#   capabilities      — attrset with optional keys: skills, mcp, openapi, cli, secret, plugins, extraPackages
#   extraClientOptions — module function returning extra options for the client submodule
#
# Capabilities:
#   skills  — list of paths (SKILL.md files or skill directories) consumed by the
#             claude-code / agent-skills / openclaw / agent-deck skill targets
#   mcp     — { type, urlTemplate, extraConfig?, auth?, viaUxcInClaudeCode?, skill? }
#             `urlTemplate` is a string OR fn-of-clientSettings. An `auth = { secret; type; }`
#             block makes the endpoint UXC-projectable (and requires a wrapper skill, D15).
#   openapi — { host, schemaSource, auth, scheme?, pathPrefix?, linkName?, priority?, skill? }
#             `host`/`scheme`/`pathPrefix` are string OR fn-of-clientSettings.
#             `schemaSource` is { type = "static"|"derivation"|"url"; ... }. Always
#             UXC-projectable, so always requires `auth` and a wrapper skill.
#   cli     — { package, wrapperName?, envVars? } wrapped as a writeShellApplication
#   secret  — { name, mode, ... } or list. Modes: prompted, generated, shared, op.
#             `op` mode references a 1Password path (`reference = "op://Vault/Item/field"`)
#             that UXC resolves at call time; it has no file on disk and no vars generator.
#   plugins, extraPackages — miscellaneous
#
# Endpoints that declare an `auth` block project into UXC's credentials/bindings/link
# shims (via lib/mkUxcProjection.nix) when a client sets `uxc.enabled = true`.
#
# Returns: { interface; perInstance; } suitable for roles.client in a clanService.
{
  serviceName,
  capabilities ? { },
  extraClientOptions ? null,
}:
let
  mkUxcProjection = import ./mkUxcProjection.nix;

  # Normalize capabilities with defaults
  skills = capabilities.skills or null;   # list of paths (each to a SKILL.md or skill directory) or null
  mcp = capabilities.mcp or null;         # { type, urlTemplate, auth?, ... } or null
  openapi = capabilities.openapi or null; # { host, schemaSource, auth, ... } or null
  cli = capabilities.cli or null;         # { package, wrapperName, envVars } or null
  secret = capabilities.secret or null;   # { name, mode, ... } or list thereof, or null
  secrets =
    if builtins.isList secret then secret
    else if secret != null then [ secret ]
    else [ ];
  extraPackages = capabilities.extraPackages or [ ];  # list of packages for global HM install
  plugins = capabilities.plugins or [ ];  # list of "pluginName@marketplace" strings to enable

  hasMcp = mcp != null;
  hasOpenapi = openapi != null;
  hasCli = cli != null;
  hasSecret = secrets != [ ];
  hasExtraPackages = extraPackages != [ ];
  hasPlugins = plugins != [ ];

  # An endpoint is UXC-projectable once it carries an `auth` block. OpenAPI is
  # always projectable; MCP is projectable only when it opts in via `auth`
  # (legacy claude-code-direct MCP keeps working untouched — no auth, no gate).
  mcpUxc = hasMcp && (mcp ? auth);
  hasUxcProjectable = mcpUxc || hasOpenapi;
  # `uxc.enabled` is offered whenever any UXC-compatible capability is present.
  hasUxc = hasMcp || hasOpenapi;

  # ── op-secret validation + opSecrets map ─────────────────────────────────
  # op secrets reference a 1Password path; reject missing / malformed refs.
  validateOpRef =
    s:
    if !(s ? reference) then
      throw "mkClientTooling: op-mode secret '${s.name}' in service '${serviceName}' is missing the required `reference` field (expected op://Vault/Item/field)"
    else if builtins.substring 0 5 s.reference != "op://" then
      throw "mkClientTooling: op-mode secret '${s.name}' in service '${serviceName}' has reference '${s.reference}' which must start with 'op://'"
    else
      s.reference;
  opSecrets = builtins.listToAttrs (
    builtins.map (s: { name = s.name; value = validateOpRef s; }) (
      builtins.filter (s: s.mode == "op") secrets
    )
  );

  # ── Endpoint auth shape validation (D9 / authSubmodule: { secret; type; }) ──
  validAuthTypes = [ "bearer" "api_key" ];
  checkEndpointAuth =
    protocol: ep:
    if !(ep ? auth) then
      throw "mkClientTooling: service '${serviceName}' `${protocol}` endpoint is UXC-projectable but declares no `auth = { secret; type; }` block"
    else if !((ep.auth ? secret) && builtins.isString ep.auth.secret) then
      throw "mkClientTooling: service '${serviceName}' `${protocol}` endpoint `auth.secret` must be a string naming a declared secret"
    else if !((ep.auth ? type) && builtins.elem ep.auth.type validAuthTypes) then
      throw "mkClientTooling: service '${serviceName}' `${protocol}` endpoint `auth.type` must be one of ${builtins.concatStringsSep ", " validAuthTypes}"
    else
      true;
  authChecks =
    (if hasOpenapi then [ (checkEndpointAuth "openapi" openapi) ] else [ ])
    ++ (if mcpUxc then [ (checkEndpointAuth "mcp" mcp) ] else [ ]);

  # ── Endpoint auth validation + referencedSecrets ─────────────────────────
  secretNames = builtins.map (s: s.name) secrets;
  endpointAuthSecrets =
    (if mcpUxc then [ mcp.auth.secret ] else [ ])
    ++ (if hasOpenapi && (openapi ? auth) then [ openapi.auth.secret ] else [ ]);
  unknownAuthRefs = builtins.filter (n: !(builtins.elem n secretNames)) endpointAuthSecrets;
  # referencedSecrets — secrets named by an endpoint `auth.secret`; only these
  # project into UXC credentials. Forcing it triggers the unknown-ref guard.
  referencedSecrets =
    if unknownAuthRefs != [ ] then
      throw "mkClientTooling: service '${serviceName}' endpoint auth.secret references unknown secret(s): ${builtins.concatStringsSep ", " unknownAuthRefs}. Declared secrets: ${builtins.concatStringsSep ", " secretNames}"
    else
      lib0.unique endpointAuthSecrets;

  # ── D15 wrapper-skill gate ───────────────────────────────────────────────
  # Every UXC-projectable endpoint must ship a wrapper skill (SKILL.md +
  # agents/openai.yaml + references/usage-patterns.md + scripts/validate.sh).
  requiredSkillFiles = [ "SKILL.md" "agents/openai.yaml" "references/usage-patterns.md" "scripts/validate.sh" ];
  requireWrapperSkill =
    protocol: endpoint:
    let
      dir = endpoint.skill or null;
    in
    if dir == null then
      throw "mkClientTooling: service '${serviceName}' declares a `${protocol}` capability with `auth` but ships no wrapper skill.\n       Run: nix run .#author-skill -- ${serviceName} ${protocol}\n       Or set: capabilities.${protocol}.skill = ./skills/${protocol}"
    else
      let
        missing = builtins.filter (f: !(builtins.pathExists "${dir}/${f}")) requiredSkillFiles;
      in
      if missing != [ ] then
        throw "mkClientTooling: service '${serviceName}' ${protocol} wrapper skill at ${toString dir} is missing required file(s): ${builtins.concatStringsSep ", " missing}"
      else
        dir;
  wrapperSkillDirs =
    (if mcpUxc then [ (requireWrapperSkill "mcp" mcp) ] else [ ])
    ++ (if hasOpenapi then [ (requireWrapperSkill "openapi" openapi) ] else [ ]);

  # Wrapper skills flow through the ordinary `skills` plumbing for client projection.
  allSkills = (if skills != null then skills else [ ]) ++ wrapperSkillDirs;
  hasSkills = allSkills != [ ];

  # Eval-time guards: force the op-secret + auth + wrapper-skill checks so any
  # consumer of the returned interface / perInstance triggers them.
  forceUxcChecks = builtins.deepSeq authChecks (
    builtins.deepSeq opSecrets (
      builtins.seq referencedSecrets (builtins.deepSeq wrapperSkillDirs true)
    )
  );

  # ── UXC endpoint records (capability-level; resolved per-client at projection) ──
  uxcEndpoints =
    (if mcpUxc then [
      ({
        protocol = "mcp";
        urlTemplate = mcp.urlTemplate;
        auth = mcp.auth;
      } // (if mcp ? priority then { priority = mcp.priority; } else { }))
    ] else [ ])
    ++ (if hasOpenapi then [
      ({
        protocol = "openapi";
        host = openapi.host;
        schemaSource = openapi.schemaSource;
        auth = openapi.auth;
      }
      // (if openapi ? scheme then { scheme = openapi.scheme; } else { })
      // (if openapi ? pathPrefix then { pathPrefix = openapi.pathPrefix; } else { })
      // (if openapi ? priority then { priority = openapi.priority; } else { }))
    ] else [ ]);

  # Default per-protocol link names (per-client overrides applied at projection).
  defaultLinkNames = {
    mcp = if hasMcp && (mcp ? linkName) then mcp.linkName else "${serviceName}-mcp-cli";
    openapi = if hasOpenapi && (openapi ? linkName) then openapi.linkName else "${serviceName}-openapi-cli";
  };

  # Minimal lib helpers usable at top level (real `lib` arrives in interface/perInstance).
  lib0 = {
    unique = list: builtins.foldl' (acc: x: if builtins.elem x acc then acc else acc ++ [ x ]) [ ] list;
  };

  # Derive skill entries from paths: accepts both SKILL.md file paths and skill directories.
  # ./skills/foo/SKILL.md → { name = "foo"; path = ./skills/foo/SKILL.md; dir = ./skills/foo; }
  # ./skills/foo           → { name = "foo"; path = ./skills/foo/SKILL.md; dir = ./skills/foo; }
  # For single-skill services at ./skills/SKILL.md, the skill name = serviceName
  skillEntries =
    if !hasSkills then [ ]
    else builtins.map (skillInput:
      let
        baseName = builtins.baseNameOf (toString skillInput);
        isFile = baseName == "SKILL.md";
        dir = if isFile then builtins.dirOf skillInput else skillInput;
        skillMd = if isFile then skillInput else "${skillInput}/SKILL.md";
        dirName = builtins.baseNameOf dir;
      in {
        name = if dirName == "skills" then serviceName else dirName;
        path = skillMd;
        dir = dir;
      }
    ) allSkills;
in
{
  # ── Interface ────────────────────────────────────────────────────────────────
  interface = builtins.seq forceUxcChecks ({ lib, ... }:
    let
      profileSubmodule = lib.types.submodule {
        options.mcp.enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Add ${serviceName} MCP server entry to this Claude Code profile";
        };
        options.plugins.enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable ${serviceName} plugins in this Claude Code profile";
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
          # Plugin-consuming targets (only when capabilities.plugins is provided)
          (lib.optionalAttrs hasPlugins {
            claude-code.plugins.enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable ${serviceName} plugins in Claude Code (default profile)";
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
          # UXC consumer toggle (only when a UXC-compatible capability is present).
          # Credential selection is driven by endpoint `auth` blocks (D9), so there
          # is intentionally no per-client `uxc.credential` override.
          (lib.optionalAttrs hasUxc (builtins.foldl' lib.recursiveUpdate {
            uxc.enabled = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Project ${serviceName} endpoints into UXC (~/.uxc) for this client";
            };
          } [
            (lib.optionalAttrs hasOpenapi {
              uxc.openapi.linkName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Override the OpenAPI link shim name for this client";
              };
            })
            (lib.optionalAttrs mcpUxc {
              uxc.mcp.linkName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Override the MCP link shim name for this client";
              };
            })
          ]))
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
    });

  # ── Per Instance ─────────────────────────────────────────────────────────────
  perInstance = builtins.seq forceUxcChecks ({ settings, ... }:
    let
      clientModule = { config, pkgs, lib, ... }:
        let
          mkClientConfig = clientName: clientSettings:
            let
              clientNameId = clientSettings.name;

              # Resolve a string-or-fn-of-clientSettings to its string value.
              resolveSF = v: if builtins.isFunction v then v clientSettings else v;

              # File-backed secrets only. `op`-mode secrets resolve via the `op`
              # CLI at call time, so they have no path and are excluded here.
              fileSecrets = builtins.filter (s: s.mode != "op") secrets;

              # Secret paths (file-backed secrets only — op secrets have no file)
              secretPaths =
                builtins.listToAttrs (builtins.map (s:
                  {
                    name = s.name;
                    value =
                      if s.mode == "shared" then
                        config.clan.core.vars.generators.${s.generator}.files.${s.file}.path
                      else
                        config.clan.core.vars.generators."agentplot-${serviceName}-${clientName}-${s.name}".files."${s.name}".path;
                  }
                ) fileSecrets);

              # Convenience alias: path to the first (or only) file-backed secret
              tokenPath =
                if fileSecrets != [ ] then
                  let first = builtins.head fileSecrets;
                  in secretPaths.${first.name}
                else null;

              # CLI wrapper (if cli capability is declared)
              cliWrapper =
                if hasCli then
                  let
                    basePkg = if builtins.isPath cli.package
                      then pkgs.callPackage cli.package { }
                      else cli.package;
                    wrapperName = if cli ? wrapperName then cli.wrapperName clientSettings else clientNameId;
                    envVarAttrs = if cli ? envVars then cli.envVars (clientSettings // { inherit secretPaths tokenPath; }) else { };
                    envExports = lib.concatStringsSep "\n" (
                      lib.mapAttrsToList (k: v: ''
                        ${k}="${v}"
                        export ${k}
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

              # Per-client UXC link-name overrides (null when not overridden).
              clientUxc = clientSettings.uxc or { };
              resolvedOpenapiLinkName = clientUxc.openapi.linkName or null;
              resolvedMcpLinkName = clientUxc.mcp.linkName or null;
              # Rewrite canonical `<service>-<protocol>-cli` link names to the
              # per-client override (covers SKILL.md body + frontmatter name:).
              linkSubsFrom =
                (lib.optional (resolvedOpenapiLinkName != null) defaultLinkNames.openapi)
                ++ (lib.optional (resolvedMcpLinkName != null) defaultLinkNames.mcp);
              linkSubsTo =
                (lib.optional (resolvedOpenapiLinkName != null) resolvedOpenapiLinkName)
                ++ (lib.optional (resolvedMcpLinkName != null) resolvedMcpLinkName);

              # Per-skill content substitution. The frontmatter `name:` match is
              # newline-anchored so a wrapper skill's `name: <service>-openapi-cli`
              # is not partially rewritten; link-name subs apply per-client overrides.
              applySkillSubs = text:
                builtins.replaceStrings
                  ([ "name: ${serviceName}\n" "${serviceName}-cli" ] ++ linkSubsFrom)
                  ([ "name: ${clientNameId}\n" clientNameId ] ++ linkSubsTo)
                  text;
              mkSkillContent = entry: applySkillSubs (builtins.readFile entry.path);

              # Per-skill directory with substituted SKILL.md (for directory-aware targets)
              mkSkillDir = entry:
                pkgs.runCommand "${clientNameId}-skill-${entry.name}" { } ''
                  cp -r --no-preserve=mode ${entry.dir} $out
                  chmod -R u+w $out
                  substitute=${builtins.toFile "substituted-skill.md" (mkSkillContent entry)}
                  cp "$substitute" $out/SKILL.md
                '';

              uxcEnabled = hasUxc && (clientSettings.uxc.enabled or false);

              # Resolved MCP URL + bare host (urlTemplate accepts string OR fn).
              mcpUrl = if hasMcp then resolveSF mcp.urlTemplate else null;
              mcpUrlHost =
                if mcpUrl != null then
                  let m = builtins.match "^https?://([^/]+).*$" mcpUrl;
                  in if m != null then builtins.head m else mcpUrl
                else null;

              # When the MCP endpoint is UXC-projected AND the service opts in via
              # `mcp.viaUxcInClaudeCode`, claude-code targets `uxc` as a stdio
              # command (no on-disk token — UXC resolves op:// at call time).
              mcpViaUxc = mcpUxc && (mcp.viaUxcInClaudeCode or false) && uxcEnabled;

              # MCP config (if mcp capability is declared)
              mcpConfig =
                if !hasMcp then null
                else if mcpViaUxc then
                  { command = "uxc"; args = [ "mcp" mcpUrlHost ]; }
                else
                  let
                    url = mcpUrl;
                    mcpExtraConfig =
                      if mcp ? extraConfig then mcp.extraConfig
                      else if mcp ? tokenFile then
                        (settings: { tokenFile = builtins.head (builtins.attrValues settings.secretPaths); })
                      else null;
                  in
                  { inherit url; } // lib.optionalAttrs (mcp.type == "http") { type = "http"; }
                    // lib.optionalAttrs (mcpExtraConfig != null && hasSecret) (mcpExtraConfig (clientSettings // { inherit secretPaths tokenPath; }))
                ;

              # ── UXC projection for this client (only when uxc.enabled) ────────
              # Apply per-client link-name overrides onto the endpoint records.
              uxcEndpointsForClient = builtins.map (ep:
                let
                  override =
                    if ep.protocol == "openapi" then resolvedOpenapiLinkName
                    else resolvedMcpLinkName;
                in
                ep // lib.optionalAttrs (override != null) { linkName = override; }
              ) uxcEndpoints;

              uxcProjection =
                if uxcEnabled && uxcEndpoints != [ ] then
                  mkUxcProjection {
                    inherit lib serviceName clientName clientSettings referencedSecrets;
                    endpoints = uxcEndpointsForClient;
                    secrets = secrets;
                  }
                else null;
              # CLI wrapper name for serialization (null when CLI not enabled)
              cliToolName =
                if hasCli && (clientSettings.cli.enabled or false) && cliWrapper != null
                then cliWrapper.name
                else null;
            in
            {
              inherit cliToolName;

              # Clan vars generators for this client's secrets.
              # Only prompted/generated modes get a generator; shared references
              # an existing one, and op resolves via 1Password at call time.
              vars =
                let
                  localSecrets = builtins.filter (s: s.mode != "shared" && s.mode != "op") secrets;
                in
                builtins.listToAttrs (builtins.map (s:
                  {
                    name = "agentplot-${serviceName}-${clientName}-${s.name}";
                    value =
                      if s.mode == "prompted" then {
                        prompts."${s.name}" = {
                          type = "hidden";
                          description =
                            if s ? description then s.description clientSettings
                            else "${s.name} for ${serviceName} client '${clientName}'";
                        };
                        files."${s.name}" = {
                          secret = true;
                        } // lib.optionalAttrs (config ? agentplot && config.agentplot.user != null) {
                          owner = config.agentplot.user;
                          group = "staff";
                        };
                        script = ''
                          cp "$prompts/${s.name}" "$out/${s.name}"
                        '';
                      }
                      else {
                        # generated mode
                        share = true;
                        files."${s.name}" = {
                          secret = true;
                          mode = "0440";
                        } // lib.optionalAttrs (config ? agentplot && config.agentplot.user != null) {
                          owner = config.agentplot.user;
                          group = "staff";
                        };
                        runtimeInputs = [ pkgs.openssl ];
                        script = ''
                          openssl rand -hex 32 > $out/${s.name}
                        '';
                      };
                  }
                ) localSecrets);

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

                  # Plugin-related options (guarded by hasPlugins)
                  pluginsEnabled = hasPlugins && (clientSettings.claude-code.plugins.enabled or false);
                  pluginEnabledAttrs = builtins.listToAttrs (
                    builtins.map (p: { name = p; value = true; }) plugins
                  );

                  # CLI option (guarded by hasCli)
                  cliEnabled = hasCli && (clientSettings.cli.enabled or false);
                in
                lib.mkMerge [
                  # Extra packages (global HM installs, not scoped CLI wrappers)
                  (lib.mkIf hasExtraPackages {
                    home.packages = extraPackages;
                  })

                  # CLI wrapper package
                  (lib.mkIf (cliEnabled && cliWrapper != null) {
                    home.packages = [ cliWrapper ];
                  })

                  # UXC projection (credentials / bindings / link shims). Written
                  # onto the shared programs.uxc.* options so multiple services
                  # targeting the same client merge rather than overwrite.
                  (lib.mkIf (uxcProjection != null) {
                    programs.uxc.enable = true;
                    programs.uxc.credentials = uxcProjection.credentials;
                    programs.uxc.bindings = uxcProjection.bindings;
                    programs.uxc.links = uxcProjection.links;
                  })

                  # Claude Code plugins (default profile enabledPlugins)
                  (lib.mkIf pluginsEnabled {
                    programs.claude-code.enabledPlugins = pluginEnabledAttrs;
                  })

                  # Claude Code plugins (per-profile enabledPlugins)
                  (lib.mkIf (hasPlugins && ccProfiles != { }) {
                    programs.claude-code.profiles = lib.mapAttrs (
                      _profileName: profileSettings:
                      lib.mkIf (profileSettings.plugins.enabled or false) {
                        enabledPlugins = pluginEnabledAttrs;
                      }
                    ) ccProfiles;
                  })

                  # Claude Code skill (when agent-skills not taking over)
                  # Pass a skill directory with substituted SKILL.md so claude-code gets
                  # both sibling files and per-client name rewriting
                  (lib.mkIf (skillEnabled && !agentSkillsEnabled) {
                    programs.claude-code.skills = builtins.listToAttrs (
                      builtins.map (entry: {
                        name = if builtins.length skillEntries == 1 then "${serviceName}-${clientNameId}" else "${serviceName}-${clientNameId}-${entry.name}";
                        value = mkSkillDir entry;
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
                            skillKey = if builtins.length skillEntries == 1 then "${serviceName}-${clientNameId}" else "${serviceName}-${clientNameId}-${entry.name}";
                          in {
                            name = skillKey;
                            value = {
                              from = "agentplot-${serviceName}";
                              transform = { original, ... }: applySkillSubs original;
                            } // lib.optionalAttrs (cliWrapper != null || hasExtraPackages) {
                              packages =
                                (lib.optional (cliWrapper != null) cliWrapper)
                                ++ extraPackages;
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
                        name = if builtins.length skillEntries == 1 then "${serviceName}-${clientNameId}" else "${serviceName}-${clientNameId}-${entry.name}";
                        value = mkSkillDir entry;
                      }) skillEntries
                    );
                  })

                  # OpenClaw skill
                  (lib.mkIf openclawEnabled {
                    programs.openclaw.skills = builtins.map (entry: {
                      name = if builtins.length skillEntries == 1 then "${serviceName}-${clientNameId}" else "${serviceName}-${clientNameId}-${entry.name}";
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

          # Expose CLI wrapper names for capabilities serialization
          agentplot._contributedCliTools = builtins.filter (x: x != null) (
            lib.mapAttrsToList (_: cc: cc.cliToolName) clientConfigs
          );
        };
    in
    {
      nixosModule = clientModule;
      darwinModule = clientModule;
    });
}
