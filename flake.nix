{
  description = "Minecraft server operations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    markdown-formatter = {
      url = "github:i9wa4/markdown-formatter";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        git-hooks.follows = "git-hooks";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ ./nix/flake-parts ];

      perSystem =
        { pkgs, system, ... }:
        let
          ghWorkflowFiles = "^\\.github/workflows/.*\\.(yml|yaml)$";
          rumdlConfig = pkgs.writeText "rumdl.toml" ''
            disable = ["MD041"]

            [MD013]
            code-blocks = false
            headings = false
            reflow = true
          '';
          markdownFormatter = "${inputs.markdown-formatter.packages.${system}.default}/bin/mdfmt";
        in
        {
          pre-commit = {
            check.enable = true;
            settings.hooks = {
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace.enable = true;
              check-added-large-files.enable = true;
              detect-private-keys.enable = true;
              check-merge-conflicts.enable = true;
              check-json.enable = true;
              check-yaml.enable = true;

              gitleaks = {
                enable = true;
                entry = "${pkgs.gitleaks}/bin/gitleaks protect --verbose --redact --staged";
                pass_filenames = false;
              };

              betterleaks = {
                enable = true;
                entry = "${pkgs.betterleaks}/bin/betterleaks git --pre-commit --verbose --redact --staged";
                pass_filenames = false;
              };

              actionlint.enable = true;

              ghalint = {
                enable = true;
                entry = "${pkgs.ghalint}/bin/ghalint run";
                files = ghWorkflowFiles;
              };

              pinact = {
                enable = true;
                entry = "${pkgs.pinact}/bin/pinact run";
                files = ghWorkflowFiles;
              };

              zizmor = {
                enable = true;
                entry = "${pkgs.zizmor}/bin/zizmor";
                files = ghWorkflowFiles;
              };

              statix = {
                enable = true;
                entry = "${pkgs.bash}/bin/bash -c '${pkgs.statix}/bin/statix check .'";
                pass_filenames = false;
              };
              deadnix.enable = true;

              rumdl-check = {
                enable = true;
                entry = "${pkgs.rumdl}/bin/rumdl check --config ${rumdlConfig}";
                types = [ "markdown" ];
              };
              markdown-formatter = {
                enable = true;
                name = "markdown-formatter";
                entry = "${markdownFormatter} --no-heading-numbering --write";
                types = [ "markdown" ];
              };

              shellcheck.enable = true;

              treefmt = {
                enable = true;
                entry = "${pkgs.bash}/bin/bash -c 'test -n \"$NIX_BUILD_TOP\" || ${pkgs.nix}/bin/nix fmt'";
                pass_filenames = false;
                always_run = true;
              };
            };
          };
        };
    };
}
