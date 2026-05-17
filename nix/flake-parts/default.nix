{ inputs, ... }:
{
  imports = [
    inputs.git-hooks.flakeModule
    inputs.treefmt-nix.flakeModule
    ./modules/apps.nix
    ./modules/checks.nix
    ./modules/devshells.nix
    ./modules/home-manager.nix
    ./modules/packages.nix
    ./modules/treefmt.nix
  ];
}
