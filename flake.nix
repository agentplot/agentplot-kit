{
  description = "Agent Plot kit — skills, CLI packages, and env contracts for self-hosted services";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
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

      homeManagerModules.secretspec = import ./modules/home-manager/secretspec.nix;
      homeManagerModules.claude-code = import ./modules/home-manager/claude-code.nix;

      # Service-specific packages (linkding-cli, paperless-cli) have moved to
      # agentplot/agentplot, co-located with their clanServices.
    };
}
