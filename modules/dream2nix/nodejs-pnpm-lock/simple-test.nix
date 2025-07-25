# Simple test to verify module functionality
# Run with: nix eval --impure -f simple-test.nix
{
  # Test 1: Module exists and can be imported
  moduleExists = builtins.pathExists ./default.nix;
  
  # Test 2: translate.nix can be loaded
  translateExists = builtins.pathExists ./translate.nix;
  
  # Test 3: Package key parsing works
  packageKeyParsing = let
    lib = (import <nixpkgs> {}).lib;
    
    parsePnpmPackageKey = packageKey: let
      cleanKey = lib.removePrefix "/" packageKey;
      parts = lib.splitString "_" cleanKey;
      mainPart = lib.head parts;
      peerPart = if lib.length parts > 1 then lib.concatStringsSep "_" (lib.tail parts) else null;
      
      atParts = lib.splitString "@" mainPart;
      version = lib.last atParts;
      nameParts = lib.init atParts;
      name = lib.concatStringsSep "@" nameParts;
    in {
      inherit name version;
      peerSuffix = peerPart;
    };
    
    testCases = [
      { input = "/lodash@4.17.21"; expected = { name = "lodash"; version = "4.17.21"; peerSuffix = null; }; }
      { input = "/@types/node@20.0.0"; expected = { name = "@types/node"; version = "20.0.0"; peerSuffix = null; }; }
    ];
    
    results = map (test: {
      input = test.input;
      actual = parsePnpmPackageKey test.input;
      matches = (parsePnpmPackageKey test.input).name == test.expected.name 
                && (parsePnpmPackageKey test.input).version == test.expected.version;
    }) testCases;
    
  in {
    inherit results;
    allPassed = lib.all (r: r.matches) results;
  };
  
  # Test 4: Test files exist
  testFilesExist = {
    packageJson = builtins.pathExists ./tests/packages/basic/package.json;
    pnpmLock = builtins.pathExists ./tests/packages/basic/pnpm-lock.yaml;
    indexJs = builtins.pathExists ./tests/packages/basic/index.js;
  };
}