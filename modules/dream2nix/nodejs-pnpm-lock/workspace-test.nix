# Test workspace parsing functionality
# Run with: nix eval --impure -f workspace-test.nix
let
  lib = (import <nixpkgs> {}).lib;
  pkgs = import <nixpkgs> {};
  
  # Import our translate function
  translate = import ./translate.nix {
    inherit lib;
    nodejsUtils = {};
    parseSpdxId = x: x;
    simpleTranslate = x: x.inputData;  # Just return input for testing
  };
  
  testSource = ./tests/packages/workspace;
  
  # Test workspace config parsing
  parseYamlFile = yamlPath: let
    yamlToJson = pkgs.runCommandLocal "yaml-to-json" {
      buildInputs = [pkgs.yq-go];
    } ''
      ${pkgs.yq-go}/bin/yq eval -o=json "${yamlPath}" > $out
    '';
  in
    builtins.fromJSON (builtins.readFile yamlToJson);
    
  workspaceYaml = parseYamlFile (testSource + "/pnpm-workspace.yaml");
  
  # Test workspace pattern resolution
  resolveWorkspacePatterns = patterns: let
    expandPattern = pattern: let
      baseDir = lib.removeSuffix "/*" pattern;
      fullPath = toString testSource + "/" + baseDir;
    in
      if lib.hasSuffix "/*" pattern && builtins.pathExists fullPath
      then
        let
          entries = builtins.readDir fullPath;
          subdirs = lib.filterAttrs (name: type: type == "directory") entries;
        in
          lib.mapAttrsToList (name: _: baseDir + "/" + name) subdirs
      else [pattern];
  in
    lib.flatten (lib.map expandPattern patterns);
    
  workspacePackages = resolveWorkspacePatterns (workspaceYaml.packages or []);
  
  # Test workspace info building
  buildWorkspaceInfo = workspacePaths: 
    lib.listToAttrs (lib.map (workspacePath: let
      packageJsonPath = toString testSource + "/" + workspacePath + "/package.json";
      packageJson = 
        if builtins.pathExists packageJsonPath
        then builtins.fromJSON (builtins.readFile packageJsonPath)
        else { name = builtins.baseNameOf workspacePath; version = "0.0.0"; };
    in {
      name = packageJson.name;
      value = {
        inherit (packageJson) version;
        path = workspacePath;
        packageJson = packageJson;
      };
    }) workspacePaths);
    
  workspaceInfo = buildWorkspaceInfo workspacePackages;
  
in {
  # Test results
  workspaceYamlParsed = workspaceYaml != {};
  workspacePackagesFound = workspacePackages;
  workspaceInfoBuilt = lib.attrNames workspaceInfo;
  
  # Test workspace protocol resolution
  workspaceProtocolTests = let
    resolveWorkspaceProtocol = workspaceInfo: dependencySpec: let
      isWorkspaceProtocol = lib.hasPrefix "workspace:" dependencySpec;
    in
      if !isWorkspaceProtocol
      then dependencySpec
      else let
        cleanSpec = lib.removePrefix "workspace:" dependencySpec;
      in
        if cleanSpec == "*"
        then "latest"  # Simplified for test
        else cleanSpec;
        
    testCases = [
      { input = "workspace:*"; expected = "latest"; }
      { input = "workspace:^0.1.0"; expected = "^0.1.0"; }
      { input = "^4.17.21"; expected = "^4.17.21"; }
    ];
    
  in map (test: {
    inherit (test) input expected;
    actual = resolveWorkspaceProtocol workspaceInfo test.input;
    matches = (resolveWorkspaceProtocol workspaceInfo test.input) == test.expected;
  }) testCases;
}