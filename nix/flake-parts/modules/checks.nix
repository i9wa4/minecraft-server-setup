{ self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = import ../../checks.nix {
        inherit self system pkgs;
      };
    };
}
