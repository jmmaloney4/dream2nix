# Test Zeus workspace structure parsing
# Run with: nix eval --impure -f zeus-test.nix --json
let
  lib = (import <nixpkgs> {}).lib;
  pkgs = import <nixpkgs> {};
  
  zeusPath = /Users/jack/git/github.com/cavinsresearch/zeus;
  
  # Test YAML parsing for Zeus
  parseYamlFile = yamlPath: let
    yamlToJson = pkgs.runCommandLocal "yaml-to-json" {
      buildInputs = [pkgs.yq-go];
    } ''
      ${pkgs.yq-go}/bin/yq eval -o=json "${yamlPath}" > $out
    '';
  in
    builtins.fromJSON (builtins.readFile yamlToJson);
  
  # Parse Zeus workspace config
  zeusWorkspaceYaml = parseYamlFile (zeusPath + "/pnpm-workspace.yaml");
  zeusPackageJson = builtins.fromJSON (builtins.readFile (zeusPath + "/package.json"));
  
  # Parse Zeus lockfile (first 20 lines to check structure)
  zeusLockfile = parseYamlFile (zeusPath + "/pnpm-lock.yaml");
  
  # Test workspace pattern resolution for Zeus
  resolveZeusWorkspaces = let
    patterns = zeusWorkspaceYaml.packages or [];
    expandPattern = pattern: let
      # For Zeus, patterns are direct package names, not globs
      packagePath = toString zeusPath + "/" + pattern;
    in
      if builtins.pathExists packagePath
      then [pattern]
      else [];
  in
    lib.flatten (lib.map expandPattern patterns);
    
  # Check which workspace packages exist
  workspacePackageInfo = let
    workspaces = resolveZeusWorkspaces;
  in
    lib.listToAttrs (lib.map (workspacePath: let
      packageJsonPath = toString zeusPath + "/" + workspacePath + "/package.json";
      packageJson = 
        if builtins.pathExists packageJsonPath
        then builtins.fromJSON (builtins.readFile packageJsonPath)
        else { name = builtins.baseNameOf workspacePath; version = "0.0.0"; };
    in {
      name = packageJson.name;
      value = {
        version = packageJson.version or "0.0.0";
        path = workspacePath;
        exists = builtins.pathExists packageJsonPath;
      };
    }) workspaces);
    
in {
  # Test results
  zeusWorkspaceStructure = {
    rootPackageName = zeusPackageJson.name;
    rootPackageVersion = zeusPackageJson.version;
    lockfileVersion = zeusLockfile.lockfileVersion;
    workspacePackages = zeusWorkspaceYaml.packages or [];
    resolvedWorkspaces = resolveZeusWorkspaces;
  };
  
  workspacePackageDetails = workspacePackageInfo;
  
  # Check if importers structure exists (v9.0 feature)
  hasImporters = zeusLockfile ? importers;
  importerKeys = 
    if zeusLockfile ? importers 
    then builtins.attrNames zeusLockfile.importers
    else [];
    
  # Sample dependencies from root importer
  rootImporter = 
    if zeusLockfile ? importers && zeusLockfile.importers ? "."
    then {
      dependencies = builtins.attrNames (zeusLockfile.importers.".".dependencies or {});
      devDependencies = builtins.attrNames (zeusLockfile.importers.".".devDependencies or {});
    }
    else { dependencies = []; devDependencies = []; };
}