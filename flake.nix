{
  description = "Agent Plot kit — skills, CLI packages, and env contracts for self-hosted services";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.nix-claude-plugins = {
    url = "github:agentplot/nix-claude-plugins";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  # Upstream provenance for the vendored skills/uxc-skill-creator tree. Pinning
  # it here surfaces version bumps as flake.lock diffs; re-copy the tree on bump.
  inputs.uxc-skill-creator-src = {
    url = "github:holon-run/uxc";
    flake = false;
  };

  outputs =
    { self, nixpkgs, nix-claude-plugins, uxc-skill-creator-src }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      authorSkillApp = system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.writeShellApplication {
          name = "author-skill";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            UXC_SKILL_CREATOR_DIR="${./skills/uxc-skill-creator}"
            export UXC_SKILL_CREATOR_DIR
            ${builtins.readFile ./apps/author-skill.sh}
          '';
        };
    in
    {
      lib.envContract = import ./lib/env-contract.nix;
      lib.mkClientTooling = args: import ./lib/mkClientTooling.nix args;
      lib.mkUpstreamSkills = args: import ./lib/mkUpstreamSkills.nix args;
      lib.mkUxcProjection = args: import ./lib/mkUxcProjection.nix args;
      lib.mkUxcChecks = args: import ./lib/mkUxcChecks.nix args;
      # Upstream pin for the vendored uxc-skill-creator skill (provenance).
      lib.uxcSkillCreatorUpstream = uxc-skill-creator-src;

      nixosModules.caddy-cloudflare = import ./modules/caddy-cloudflare.nix;

      homeManagerModules.secretspec = import ./modules/home-manager/secretspec.nix;
      homeManagerModules.claude-code = import ./modules/home-manager/claude-code.nix;
      homeManagerModules.claude-plugins = nix-claude-plugins.homeManagerModules.default;
      homeManagerModules.uxc = import ./modules/home-manager/uxc.nix;

      tests.upstream-skills = import ./tests/upstream-skills.nix { lib = nixpkgs.lib; };
      tests.uxc = import ./tests/uxc.nix { lib = nixpkgs.lib; };

      apps = forAllSystems (system: {
        author-skill = {
          type = "app";
          program = "${authorSkillApp system}/bin/author-skill";
        };
      });

      # Gate committed UXC wrapper skills (D11 validate.sh + D14 spec-hash).
      # No services in this library repo, so they pass trivially here; downstream
      # repos call lib.mkUxcChecks with their own src to gate their skills.
      checks = forAllSystems (system:
        let
          uxcChecks = import ./lib/mkUxcChecks.nix {
            pkgs = pkgsFor system;
            src = self;
          };
        in
        {
          uxc-wrapper-skills = uxcChecks.wrapper-skills;
          uxc-spec-hash = uxcChecks.spec-hash;
        });

      # Service-specific packages (linkding-cli, paperless-cli) have moved to
      # agentplot/agentplot, co-located with their clanServices.
    };
}
