{
  description = "gh-ai development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            bash
            gh
            gum
            bats
            shellcheck
            ossp-uuid
          ];

          shellHook = ''
            if ! command -v claude &>/dev/null; then
              echo "warning: 'claude' CLI not found — install via: https://code.claude.com/docs/en/terminal-guide"
            fi
          '';
        };
      }
    );
}
