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

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          linkding-cli = pkgs.callPackage ./packages/linkding-cli { };
          pocket-id-cli = pkgs.callPackage ./packages/pocket-id-cli { };
          paperless-cli = pkgs.callPackage ./packages/paperless-cli { };
        }
      );
    };
}
