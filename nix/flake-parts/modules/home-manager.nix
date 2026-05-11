{
  inputs,
  self,
  ...
}:
let
  inherit (inputs) home-manager nixpkgs;
  homeManagerModule = import ../../home-manager-module.nix { inherit self; };
  mkUbuntuHome =
    username: enabled:
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
        homeManagerModule
        (_: {
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
                enable = enabled.mbs or false;
                repoDir = "${homeDir}/mc/server-setup";
                envFile = "${homeDir}/mc/server-setup/.env.mbs";
                composeFile = "${homeDir}/mc/server-setup/compose.mbs.yml";
              };

              mjs = {
                enable = enabled.mjs or false;
                repoDir = "${homeDir}/mc/server-setup";
                envFile = "${homeDir}/mc/server-setup/.env.mjs";
                composeFile = "${homeDir}/mc/server-setup/compose.mjs.yml";
                backup.cloud.enable = false;
              };
            };
          };
        })
      ];
    };
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
{
  flake = {
    homeManagerModules.default = homeManagerModule;
    homeConfigurations = {
      mbs = mkUbuntuHome username { mbs = true; };
      mjs = mkUbuntuHome username { mjs = true; };
      mc = mkUbuntuHome username {
        mbs = true;
        mjs = true;
      };
    };
  };
}
