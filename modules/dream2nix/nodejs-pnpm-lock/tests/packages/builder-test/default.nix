# Test integration with nodejs builders
{dream2nix}: let
  project = dream2nix.lib.evalModules {
    packageSets.nixpkgs = dream2nix.inputs.nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      # Use pnpm-lock translator
      dream2nix.modules.dream2nix.nodejs-pnpm-lock
      
      # Add nodejs builder for compilation/packaging
      dream2nix.modules.dream2nix.nodejs-granular-v3
      
      {
        paths.projectRoot = ./.;
        nodejs-pnpm-lock = {
          source = ./.;
          packageJsonFile = ./package.json;
          pnpmLockFile = ./pnpm-lock.yaml;
        };
        name = "builder-integration-test";
        version = "2.0.0";
        
        # Configure the builder
        nodejs-granular-v3 = {
          runBuild = true;
        };
      }
    ];
  };
in
  project.config.public