{
  description = "Minimal Multi-DE Flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
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

    b123d-server = {
      url = "github:Dispersia/build123d_server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      home-manager,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          formatter = pkgs.nixfmt-tree;

          packages = {
            neovim = pkgs.neovim;
          };
        };

      flake =
        let
          bravePolicies = {
            environment.etc."brave/policies/managed/brave-default-search.json".text = ''
              {
                "DefaultSearchProviderEnabled": true,
                "DefaultSearchProviderName": "Google",
                "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}"
              }
            '';

            environment.etc."brave/policies/managed/brave-url-blocklist.json".text = ''
              {
                "URLBlocklist": ["reddit.com/r/popular", "youtube.com/shorts"]
              }
            '';
          };

          mkNixosHost =
            hostName: username:
            nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
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
                bravePolicies
              ];
            };
          mkAndroidHost =
            hostName: username:
            nixpkgs.lib.nixosSystem {
              system = "aarch64-linux";
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
                bravePolicies
              ];
            };

          mkDarwinHost =
            hostName: username:
            inputs.nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
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
                (
                  { pkgs, ... }:
                  {

                    environment.shells = with pkgs; [
                      nushell
                    ];

                  }
                )
              ];
            };
        in
        {
          nixosConfigurations = {
            laptop = mkNixosHost "laptop" "dispe";
            work-desktop = mkNixosHost "work-desktop" "dispe";
            desktop = mkNixosHost "desktop" "dispe";
            home-server = mkNixosHost "home-server" "dispe";
            android = mkAndroidHost "phone" "dispe";
          };

          darwinConfigurations = {
            ML-DWR5XQ9FLW = mkDarwinHost "ML-DWR5XQ9FLW" "AHoush";
          };
        };
    };
}
