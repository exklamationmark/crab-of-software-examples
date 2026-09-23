{
  description = "Minimal macOS home-manager flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin"; # or: "x86_64-darwin", "x86_64-linux", "aarch64-linux"
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."USERNAME" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            home.username = "USERNAME";
            home.homeDirectory = "/Users/USERNAME";
            home.stateVersion = "26.05";

            # example packages
            home.packages = with pkgs; [
              just
            ];

            programs.home-manager.enable = true;
          }
        ];
      };
    };
}
