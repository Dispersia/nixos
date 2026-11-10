{
  description = "Minimal Multi-DE Flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";

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

    llm-agents.url = "github:numtide/llm-agents.nix";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenDesign — the local-first design workspace (`od` CLI + daemon + web UI).
    # Upstream retired its official Nix distribution in Aug 2026
    # (nexu-io/open-design#7644 removed the flake and Home Manager/NixOS
    # modules). We track the Dispersia fork's `opencode2` branch, which keeps the
    # flake + Home Manager module (based on the last upstream commit that shipped
    # them) and adds an `opencode2` runtime definition so OpenCode 2 works as the
    # local design agent.
    open-design = {
      url = "github:Dispersia/open-design/opencode2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    obsidian-extensions = {
      url = "github:karaolidis/nix-obsidian-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    globalprotect-openconnect = {
      url = "github:yuezk/GlobalProtect-openconnect";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        naersk.inputs.nixpkgs.follows = "nixpkgs";
        rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
      };
    };

    # YomiFin sidecars. Both flakes live in subdirectories of the same checkout
    # (`ocr/flake.nix` and `upscale/flake.nix`); they follow this flake's nixpkgs
    # so python/uv/models come from a single closure.
    #
    # These are `path:` inputs so the Mac mini always evaluates the working
    # checkout. Once the packaging is pushed, switch to
    # `github:Dispersia/yomifin?dir=ocr` / `?dir=upscale` so comin no longer
    # depends on a local checkout.
    yomifin-ocr = {
      url = "path:/Users/dispe/development/yomifin?dir=ocr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    yomifin-upscale = {
      url = "path:/Users/dispe/development/yomifin?dir=upscale";
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
                ./modules/tailnet-ca.nix
                bravePolicies
              ];
            };
          mkServerHost =
            hostName: username:
            nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = { inherit inputs hostName username; };
              modules = [
                ./hosts/${hostName}
                ./modules/tailnet-ca.nix
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
                ./modules/tailnet-ca.nix
                bravePolicies
              ];
            };

          mkDarwinHost =
            hostName: username: file:
            inputs.nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              specialArgs = {
                inherit
                  inputs
                  hostName
                  username
                  file
                  ;
              };
              modules = [
                ./hosts/${hostName}
                ./modules/tailnet-ca-darwin.nix

                home-manager.darwinModules.home-manager
                {
                  home-manager.useGlobalPkgs = true;
                  home-manager.useUserPackages = true;

                  home-manager.users.${username} = {
                    imports = [ ./users/${file}/home.nix ];
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
            home-server = mkServerHost "home-server" "dispe";
            wsl = mkNixosHost "wsl" "nixos";
            android = mkAndroidHost "phone" "dispe";
          };

          darwinConfigurations = {
            ML-DWR5XQ9FLW = mkDarwinHost "ML-DWR5XQ9FLW" "AHoush" "AHoush";
            Aarons-Mac-Mini = mkDarwinHost "Aarons-Mac-Mini" "dispe" "dispe-mac";
          };
        };
    };
}
