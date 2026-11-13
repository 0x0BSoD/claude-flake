{
  description = "Anthropic Claude Code CLI and Claude desktop app for NixOS and macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
              "claude-desktop"
            ];
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          claude-code = pkgs.callPackage ./packages/claude-code.nix { };
        in
        {
          inherit claude-code;
          update = pkgs.writeShellApplication {
            name = "update";
            runtimeInputs = with pkgs; [
              coreutils
              curl
              gitMinimal
              jq
              nix
            ];
            text = builtins.readFile ./scripts/update.sh;
          };
          default = claude-code;
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          claude-desktop = pkgs.callPackage ./packages/claude-desktop-darwin.nix { };
        }
      );

      apps = forAllSystems (system: {
        update = {
          type = "app";
          program = "${self.packages.${system}.update}/bin/update";
          meta.description = "Update the pinned official Anthropic packages";
        };
      });

      nixosModules.default = import ./modules/nixos.nix self;
      nixosModules.claude = self.nixosModules.default;

      darwinModules.default = import ./modules/darwin.nix self;
      darwinModules.claude = self.darwinModules.default;

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      checks = forAllSystems (
        system:
        {
          inherit (self.packages.${system}) claude-code;
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-darwin" system) {
          inherit (self.packages.${system}) claude-desktop;
        }
      );
    };
}
