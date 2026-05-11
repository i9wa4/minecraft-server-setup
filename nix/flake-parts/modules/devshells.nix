{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells = {
        default = pkgs.mkShell {
          packages = [
            config.packages.mc-server
            pkgs.actionlint
            pkgs.deadnix
            pkgs.docker-compose
            pkgs.ghalint
            pkgs.gitleaks
            pkgs.jq
            pkgs.pinact
            pkgs.shellcheck
            pkgs.statix
            pkgs.zizmor
            config.treefmt.build.wrapper
          ];
          shellHook = config.pre-commit.installationScript;
        };
        ci = pkgs.mkShell {
          packages = [
            pkgs.actionlint
            pkgs.ghalint
            pkgs.gitleaks
            pkgs.pinact
            pkgs.zizmor
          ];
        };
      };
    };
}
