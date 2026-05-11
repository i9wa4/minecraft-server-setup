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

      yamlfmt = {
        command = "${pkgs.yamlfmt}/bin/yamlfmt";
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
}
