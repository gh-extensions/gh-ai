{
  description = "gh-ai development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            bash # 4.4+ required; macOS ships with 3.2
            gh
            gum
            jq
            bats
            shellcheck
            gettext # provides envsubst
          ];

          shellHook = ''
            if ! command -v claude &>/dev/null; then
              echo "warning: 'claude' CLI not found — install via: npm install -g @anthropic-ai/claude-code"
            fi
          '';
        };
      }
    );
}
