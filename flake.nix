{
  description = "Agent Plot kit — skills, CLI packages, and env contracts for self-hosted services";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.nix-claude-plugins = {
    url = "github:agentplot/nix-claude-plugins";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, nix-claude-plugins }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      lib.envContract = import ./lib/env-contract.nix;
      lib.mkClientTooling = args: import ./lib/mkClientTooling.nix args;
      lib.mkUpstreamSkills = args: import ./lib/mkUpstreamSkills.nix args;

      nixosModules.caddy-cloudflare = import ./modules/caddy-cloudflare.nix;

      homeManagerModules.secretspec = import ./modules/home-manager/secretspec.nix;
      homeManagerModules.claude-code = import ./modules/home-manager/claude-code.nix;
      homeManagerModules.claude-plugins = nix-claude-plugins.homeManagerModules.default;

      tests.upstream-skills = import ./tests/upstream-skills.nix { lib = nixpkgs.lib; };

      # Service-specific packages (linkding-cli, paperless-cli) have moved to
      # agentplot/agentplot, co-located with their clanServices.
    };
}
