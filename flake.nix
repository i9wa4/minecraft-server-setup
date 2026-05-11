{
  description = "Minecraft server operations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      treefmt-nix,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      treefmtEval = pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      mkUbuntuHome =
        username:
        let
          system = "x86_64-linux";
          pkgs = import nixpkgs {
            localSystem = system;
            config.allowUnfree = true;
          };
          homeDir = "/home/${username}";
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.default
            (
              { lib, ... }:
              {
                home = {
                  inherit username;
                  homeDirectory = homeDir;
                  enableNixpkgsReleaseCheck = false;
                  stateVersion = "25.11";
                };

                programs.home-manager.enable = true;
                systemd.user.startServices = "sd-switch";

                services.minecraft = {
                  enable = true;
                  servers = {
                    mbs = {
                      enable = true;
                      repoDir = "${homeDir}/mc/server-setup";
                      envFile = "${homeDir}/mc/server-setup/.env.mbs";
                      composeFile = "${homeDir}/mc/server-setup/compose.yml";
                    };

                    mjs = {
                      enable = lib.mkDefault false;
                      repoDir = "${homeDir}/mc/server-setup";
                      envFile = "${homeDir}/mc/server-setup/.env.mjs";
                      composeFile = "${homeDir}/mc/server-setup/compose.mjs.yml";
                      backup.enable = false;
                      backup.cloud.enable = false;
                    };
                  };
                };
              }
            )
          ];
        };
    in
    {
      packages = forAllSystems (
        _system: pkgs:
        import ./nix/packages.nix {
          inherit pkgs;
        }
      );

      apps = forAllSystems (
        system: pkgs:
        let
          mc-server = "${self.packages.${system}.mc-server}/bin/mc-server";
          mbs = "${self.packages.${system}.mbs}/bin/mbs";
          mjs = "${self.packages.${system}.mjs}/bin/mjs";
          mkApp =
            package: command:
            let
              app = pkgs.writeShellApplication {
                name = "mc-${command}";
                text = ''
                  exec ${package} ${command} "$@"
                '';
              };
            in
            {
              type = "app";
              program = "${app}/bin/mc-${command}";
              meta.description = "Run ${command}";
            };
        in
        {
          default = {
            type = "app";
            program = mc-server;
            meta.description = "Run the Minecraft server operations CLI";
          };
          mc-server = {
            type = "app";
            program = mc-server;
            meta.description = "Run the Minecraft server operations CLI";
          };
          mbs = {
            type = "app";
            program = mbs;
            meta.description = "Run the Minecraft Bedrock server operations CLI";
          };
          mjs = {
            type = "app";
            program = mjs;
            meta.description = "Run the Minecraft Java server operations CLI";
          };
          mbs-doctor = mkApp mbs "doctor";
          mbs-host-setup = mkApp mbs "host-setup";
          mbs-host-init = mkApp mbs "host-init";
          mbs-init = mkApp mbs "init";
          mbs-up = mkApp mbs "up";
          mbs-down = mkApp mbs "down";
          mbs-stop = mkApp mbs "stop";
          mbs-restart = mkApp mbs "restart";
          mbs-update = mkApp mbs "update";
          mbs-ps = mkApp mbs "ps";
          mbs-logs = mkApp mbs "logs";
          mbs-timers = mkApp mbs "timers";
          mbs-backup-local = mkApp mbs "backup-local";
          mbs-backup-cloud = mkApp mbs "backup-cloud";
          mjs-doctor = mkApp mjs "doctor";
          mjs-host-setup = mkApp mjs "host-setup";
          mjs-host-init = mkApp mjs "host-init";
          mjs-init = mkApp mjs "init";
          mjs-up = mkApp mjs "up";
          mjs-down = mkApp mjs "down";
          mjs-stop = mkApp mjs "stop";
          mjs-restart = mkApp mjs "restart";
          mjs-update = mkApp mjs "update";
          mjs-ps = mkApp mjs "ps";
          mjs-logs = mkApp mjs "logs";
          mjs-timers = mkApp mjs "timers";
        }
      );

      homeManagerModules.default = import ./nix/home-manager-module.nix { inherit self; };

      formatter = forAllSystems (_system: pkgs: (treefmtEval pkgs).config.build.wrapper);

      checks = forAllSystems (
        system: pkgs:
        (import ./nix/checks.nix {
          inherit self system pkgs;
        })
        // {
          formatting = (treefmtEval pkgs).config.build.check self;
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              self.packages.${system}.mc-server
              pkgs.deadnix
              pkgs.docker-compose
              pkgs.jq
              pkgs.shellcheck
              pkgs.statix
              (treefmtEval pkgs).config.build.wrapper
            ];
          };
        }
      );

      homeConfigurations.mc =
        let
          username =
            let
              logname = builtins.getEnv "LOGNAME";
              user = builtins.getEnv "USER";
            in
            if logname != "" then
              logname
            else if user != "" then
              user
            else
              "uma";
        in
        mkUbuntuHome username;
    };
}
