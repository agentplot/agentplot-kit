# Home Manager module for secretspec — declarative secret management.
# Installs the secretspec CLI and writes the global config.toml.
#
# Usage:
#   programs.secretspec = {
#     enable = true;
#     settings = {
#       defaults = {
#         profile = "my_vault";
#         provider = "onepassword";
#         providers = {
#           my_vault = "onepassword://My-Vault";
#           keyring = "keyring://";
#         };
#       };
#     };
#   };
{ config, pkgs, lib, ... }:

let
  cfg = config.programs.secretspec;
  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "secretspec-config" cfg.settings;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  options.programs.secretspec = {
    enable = lib.mkEnableOption "secretspec declarative secret management";

    package = lib.mkPackageOption pkgs "secretspec" { };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        Configuration written to the secretspec config.toml.
        Typically contains a `defaults` section with `profile`, `provider`,
        and `providers` (alias -> URI mappings).
        See https://secretspec.dev for the config format.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # secretspec config path differs by platform:
    #   macOS:  ~/Library/Application Support/secretspec/config.toml
    #   Linux:  ~/.config/secretspec/config.toml
    home.file = lib.mkIf (cfg.settings != { }) (
      if isDarwin then {
        "Library/Application Support/secretspec/config.toml".source = configFile;
      } else {
        ".config/secretspec/config.toml".source = configFile;
      }
    );
  };
}
