{dream2nix}: let
  project = dream2nix.lib.evalModules {
    packageSets.nixpkgs = dream2nix.inputs.nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      dream2nix.modules.dream2nix.nodejs-pnpm-lock
      {
        paths.projectRoot = ./.;
        nodejs-pnpm-lock = {
          source = ./.;
          packageJsonFile = ./package.json;
          pnpmLockFile = ./pnpm-lock.yaml;
          pnpmWorkspaceFile = ./pnpm-workspace.yaml;
        };
        name = "workspace-test";
        version = "1.0.0";
      }
    ];
  };
in
  project.config.public