{
  description = "Minimal Multi-DE Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-darwin = {
     url = "github:nix-darwin/nix-darwin";
     inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      linuxSystem = "x86_64-linux";
      darwinSystem = "aarch64-darwin";
      mkNixosHost =
        hostName: username:
        nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs hostName username; };
          modules = [
            ./hosts/${hostName}

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.users.${username} =
                {
                  config,
                  lib,
                  pkgs,
                  ...
                }:
                {
                  imports = [
                    ./users/${username}/home.nix
                 ];
                };
              home-manager.extraSpecialArgs = { inherit inputs hostName username; };
            }
            {
              environment.etc."brave/policies/managed/brave-default-search.json".text = ''
                {
                  "DefaultSearchProviderEnabled": true,
                  "DefaultSearchProviderName": "Google",
                  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}"
                }
              '';
            }
          ];
        };
      mkDarwinHost = hostName: username:
        inputs.nix-darwin.lib.darwinSystem {
          system = darwinSystem;
          specialArgs = { inherit inputs hostName username; };
          modules = [
            ./hosts/${hostName}

            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
 
              home-manager.users.${username} = {
                imports = [ ./users/${username}/home.nix ];
              };

              home-manager.extraSpecialArgs = { inherit inputs hostName username; };
            }
            ({ pkgs, ... }: {


  environment.shells = with pkgs; [
    nushell
  ];


            })
          ];
        };
    in
    {
      formatter.${linuxSystem} = nixpkgs.legacyPackages.${linuxSystem}.nixfmt-tree;
      formatter.${darwinSystem} = nixpkgs.legacyPackages.${darwinSystem}.nixfmt-tree;


      nixosConfigurations = {
        laptop = mkNixosHost "laptop" "dispe";
        work-desktop = mkNixosHost "work-desktop" "dispe";
      };

      darwinConfigurations = {
        work-laptop = mkDarwinHost "ML-DWR5XQ9FLW" "AHoush";
      };
    };
}
