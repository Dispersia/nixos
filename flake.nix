{
  description = "Minimal Multi-DE Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }: 
  let
    mkHost = hostName: username: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs hostName username; };
      modules = [
        ./hosts/${hostName}

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          home-manager.users.${username} = import ./users/${username}/home.nix;
          home-manager.extraSpecialArgs = { inherit inputs hostName username; };
        }
      ];
    };
  in {
    nixosConfigurations = {
      laptop = mkHost "laptop" "dispe";
      desktop = mkHost "desktop" "dispe";
    };
  };
}
