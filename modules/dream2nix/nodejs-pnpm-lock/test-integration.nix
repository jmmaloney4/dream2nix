# Simple integration test for nodejs-pnpm-lock module
let
  flake = builtins.getFlake (toString ./../../../..);
  
  testResult = flake.lib.evalModules {
    packageSets.nixpkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      flake.modules.dream2nix.nodejs-pnpm-lock
      {
        name = "basic-pnpm-test";
        version = "1.0.0";
        nodejs-pnpm-lock = {
          source = ./tests/packages/basic;
        };
      }
    ];
  };
in {
  # Test that basic properties are accessible
  name = testResult.config.name;
  version = testResult.config.version;
  
  # Test that the module loads without errors
  moduleLoaded = testResult.config ? nodejs-pnpm-lock;
  
  # Test that dreamLock is generated
  hasDreamLock = testResult.config.nodejs-pnpm-lock ? dreamLock;
  
  # Test that package.json is parsed
  hasPackageJson = testResult.config.nodejs-pnpm-lock.packageJson ? name;
  packageName = testResult.config.nodejs-pnpm-lock.packageJson.name;
}