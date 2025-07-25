{
  config,
  dream2nix,
  lib,
  ...
}: let
  l = lib // builtins;
  cfg = config.nodejs-pnpm-lock;

  nodejsUtils = import ../../../lib/internal/nodejsUtils.nix {inherit lib parseSpdxId;};
  parseSpdxId = import ../../../lib/internal/parseSpdxId.nix {inherit lib;};
  prepareSourceTree = import ../../../lib/internal/prepareSourceTree.nix {inherit lib;};
  simpleTranslate = import ../../../lib/internal/simpleTranslate.nix {inherit lib;};

  translate = import ./translate.nix {
    inherit lib nodejsUtils parseSpdxId simpleTranslate;
  };

  dreamLock = translate {
    projectName = config.name;
    projectRelPath = "";
    workspaces = cfg.workspaces;
    workspaceParent = "";
    source = cfg.src;
    tree = prepareSourceTree {source = cfg.source;};
    noDev = ! cfg.withDevDependencies;
    nodejs = "unknown";
    inherit (cfg) packageJson pnpmLock pnpmWorkspace;
  };
in {
  imports = [
    ./interface.nix
    dream2nix.modules.dream2nix.core
    dream2nix.modules.dream2nix.mkDerivation
  ];

  # declare external dependencies
  deps = {nixpkgs, ...}: {
    inherit
      (nixpkgs)
      fetchgit
      fetchurl
      nix
      runCommandLocal
      yq
      ;
  };
  
  nodejs-pnpm-lock = {
    inherit dreamLock;
    packageJson = l.fromJSON (l.readFile cfg.packageJsonFile);
    pnpmLock = 
      if cfg.pnpmLockFile != null
      then 
        # TODO: Implement YAML parsing via IFD
        # This will require creating a derivation that uses yq to convert YAML to JSON
        throw "pnpm-lock.yaml parsing not yet implemented - requires IFD translator"
      else lib.mkDefault {};
    pnpmWorkspace = 
      if cfg.pnpmWorkspaceFile != null
      then 
        # TODO: Implement pnpm-workspace.yaml parsing
        throw "pnpm-workspace.yaml parsing not yet implemented"
      else lib.mkDefault {};
  };
}