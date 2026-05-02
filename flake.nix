{
  description = "Minimal Multi-DE Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";

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
      android-nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkHost =
        hostName: username:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs hostName username; };
          modules = [
            ({ pkgs, ... }: {
              nixpkgs.overlays = [
                android-nixpkgs.overlays.default
              ];
            })

            ./hosts/${hostName}

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.users.${username} = { config, lib, pkgs, ... }:
              {
                imports = [
                  ./users/${username}/home.nix

                  {
                    config = {
                      android-sdk = {
                        enable = true;
                        path = "${config.home.homeDirectory}/.android/sdk";
                        packages = sdk: with sdk; [
                          build-tools-34-0-0
                          cmdline-tools-latest
                          emulator
                          platforms-android-34
                          sources-android-34
                        ];
                      };
                    };
                    imports = [ android-nixpkgs.hmModule ];
                  }
                ];
              };
              home-manager.extraSpecialArgs = { inherit inputs hostName username; };
            }
          ];
        };
    in
    {
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
      nixosConfigurations = {
        laptop = mkHost "laptop" "dispe";
        desktop = mkHost "desktop" "dispe";
        work-desktop = mkHost "work-desktop" "dispe";
      };
    };
}
