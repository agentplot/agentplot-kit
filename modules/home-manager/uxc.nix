# programs.uxc — declaratively own UXC's on-disk state.
#
# Renders the module-system-merged value of its own options into:
#   ~/.uxc/credentials.json    { version = 1; credentials = <programs.uxc.credentials>; }
#   ~/.uxc/auth_bindings.json  { version = 1; bindings    = <programs.uxc.bindings>; }
#   link shims on $PATH        one writeShellApplication per programs.uxc.links entry
#
# These options are the single population surface for BOTH first-party service
# projections (written by mkClientTooling's client role) and consumer-declared
# third-party endpoints (deepwiki, context7, …). The module never crawls
# services — it only reads its own options, so ordinary module merging unifies
# both classes into one set (D16).
#
# The module does NOT install the `uxc` binary, nor touch ~/.uxc/cache or the
# daemon socket — those are runtime state owned by `uxc` itself.
#
# Minimum supported UXC: >= 0.16 (the release that sends
# `notifications/initialized` on the streamable-HTTP MCP transport).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.uxc;
  jsonFormat = pkgs.formats.json { };

  minUxcVersion = "0.16";

  linkSubmodule = lib.types.submodule {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = ''
          UXC endpoint the shim targets. For OpenAPI this is the bare host
          (paired with `schemaUrl`); for MCP / command transports it is the
          full URL or `command:` string UXC expects.
        '';
      };
      schemaUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional `--schema-url` value (OpenAPI specs).";
      };
      injectEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Environment variables to export before invoking `uxc`. Values are
          emitted verbatim, so `"$FOO"` passes the ambient `FOO` through.
        '';
      };
    };
  };

  # One link shim per entry. `uxc` is intentionally NOT a runtimeInput — the
  # shim resolves it from $PATH so a missing binary fails at call time, not at
  # Nix build time.
  mkLinkShim =
    name: link:
    let
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''export ${k}="${v}"'') link.injectEnv
      );
      schemaArg = lib.optionalString (link.schemaUrl != null) "--schema-url '${link.schemaUrl}' ";
    in
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        ${envExports}
        exec uxc '${link.host}' ${schemaArg}"$@"
      '';
    };

  linkShims = lib.mapAttrsToList mkLinkShim cfg.links;

  credentialsFile = jsonFormat.generate "uxc-credentials.json" {
    version = 1;
    credentials = cfg.credentials;
  };
  bindingsFile = jsonFormat.generate "uxc-auth_bindings.json" {
    version = 1;
    bindings = cfg.bindings;
  };

  uxcHome = "${config.home.homeDirectory}/.uxc";

  # Credential ids referenced by bindings must resolve to a declared credential.
  bindingCredentials = lib.unique (
    builtins.filter (c: c != null) (builtins.map (b: b.credential or null) cfg.bindings)
  );
  declaredCredentials = builtins.attrNames cfg.credentials;
  danglingCredentials = builtins.filter (c: !(builtins.elem c declaredCredentials)) bindingCredentials;
in
{
  options.programs.uxc = {
    enable = lib.mkEnableOption "declarative UXC config (~/.uxc) and link shims";

    credentials = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      description = ''
        UXC credential definitions keyed by credential id. Each value has
        `auth_type` (`bearer` | `api_key`) and a `secret_source` of kind
        `literal` | `env` | `op`.
      '';
      example = lib.literalExpression ''
        {
          "agentplot-atomic-personal-admin-token" = {
            auth_type = "bearer";
            secret_source = { kind = "op"; reference = "op://Personal/Atomic/token"; };
          };
        }
      '';
    };

    bindings = lib.mkOption {
      type = lib.types.listOf jsonFormat.type;
      default = [ ];
      description = ''
        UXC endpoint→credential bindings, keyed on scheme + host + path_prefix
        and ordered by priority.
      '';
    };

    links = lib.mkOption {
      type = lib.types.attrsOf linkSubmodule;
      default = { };
      description = ''
        Link shims to install on $PATH, keyed by link name. Each becomes a
        `uxc` wrapper executable of that name.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = danglingCredentials == [ ];
        message =
          "programs.uxc.bindings reference undeclared credential id(s): "
          + lib.concatStringsSep ", " danglingCredentials
          + ". Declare them in programs.uxc.credentials.";
      }
    ];

    # Note for operators: requires `uxc` >= ${minUxcVersion} on $PATH.
    warnings = lib.optional (cfg.links != { } || cfg.bindings != [ ]) ''
      programs.uxc renders ~/.uxc config for UXC >= ${minUxcVersion}.
      Install the `uxc` binary separately (homebrew / cargo / nixpkgs);
      this module does not provide it.
    '';

    home.packages = linkShims;

    # home.file can only symlink world-readable store paths, so render the
    # credential/binding files via an activation step that installs them with
    # mode 0600. Daemon/cache state under ~/.uxc is left untouched.
    home.activation.uxcConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p $VERBOSE_ARG "${uxcHome}"
      $DRY_RUN_CMD install $VERBOSE_ARG -m 0600 ${credentialsFile} "${uxcHome}/credentials.json"
      $DRY_RUN_CMD install $VERBOSE_ARG -m 0600 ${bindingsFile} "${uxcHome}/auth_bindings.json"
    '';
  };
}
