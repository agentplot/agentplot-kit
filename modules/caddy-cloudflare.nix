# Caddy with Cloudflare DNS-01 ACME — shared config for all machines using Caddy.
# Provides: custom Caddy build with cloudflare plugin, API token from clan vars.
# Service modules must add `tls` block to each virtualHost via config.caddy-cloudflare.tls.
{ config, pkgs, lib, ... }:
let
  cfg = config.services.caddy;
  tokenPath = config.clan.core.vars.generators.cloudflare-dns-token.files.api-token.path;
in
{
  # Expose TLS directive for service modules to reference
  options.caddy-cloudflare.tls = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Caddy TLS block for ACME DNS-01 via Cloudflare (set automatically when caddy is enabled)";
  };

  config = lib.mkIf cfg.enable {
    caddy-cloudflare.tls = ''
      tls {
        issuer acme {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        issuer acme {
          dir https://acme-staging-v02.api.letsencrypt.org/directory
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
      }
    '';

    services.caddy.package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
      hash = "sha256-mmkziFzEMBcdnCWCRiT3UyWPNbINbpd3KUJ0NMW632w=";
    };

    # Oneshot service creates the env file BEFORE caddy starts
    # (systemd loads EnvironmentFile before ExecStartPre, so preStart is too late)
    systemd.services.caddy-env = {
      description = "Generate Caddy Cloudflare environment";
      before = [ "caddy.service" ];
      requiredBy = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        printf 'CLOUDFLARE_API_TOKEN=%s\n' "$(cat ${tokenPath})" > /run/caddy-cloudflare.env
      '';
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile = "/run/caddy-cloudflare.env";

    clan.core.vars.generators.cloudflare-dns-token = {
      share = true;
      files.api-token.secret = true;
      prompts.api-token = {
        description = "Cloudflare API token (Zone.Zone:Read + Zone.DNS:Edit)";
        type = "hidden";
      };
      script = ''
        cp "$prompts/api-token" "$out/api-token"
      '';
    };
  };
}
