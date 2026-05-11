{
  perSystem =
    { pkgs, ... }:
    let
      rumdlConfig = pkgs.writeText "rumdl.toml" ''
        disable = ["MD041"]

        [MD013]
        code-blocks = false
        headings = false
        reflow = true
      '';
    in
    {
      treefmt = {
        projectRootFile = "flake.nix";

        programs = {
          nixfmt.enable = true;

          shfmt = {
            enable = true;
            indent_size = 2;
          };
        };

        settings = {
          formatter = {
            rumdl = {
              command = "${pkgs.rumdl}/bin/rumdl";
              options = [
                "fmt"
                "--config"
                "${rumdlConfig}"
              ];
              includes = [ "*.md" ];
            };

            jq = {
              command = "${pkgs.jq}/bin/jq";
              options = [ "." ];
              includes = [ "*.json" ];
            };

            yamlfmt = {
              command = "${pkgs.yamlfmt}/bin/yamlfmt";
              options = [
                "-formatter"
                "retain_line_breaks=true"
                "-formatter"
                "retain_line_breaks_single=true"
              ];
              includes = [
                "*.yaml"
                "*.yml"
              ];
            };
          };

          global.excludes = [
            ".direnv"
            ".git"
            "*.lock"
            "result"
            "result-*"
          ];
        };
      };
    };
}
