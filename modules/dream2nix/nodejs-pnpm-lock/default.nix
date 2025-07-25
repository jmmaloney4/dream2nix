{
  config,
  dream2nix,
  lib,
  runCommandLocal,
  yq-go,
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
    source = cfg.source;
    tree = prepareSourceTree {source = cfg.source;};
    noDev = ! cfg.withDevDependencies;
    nodejs = "unknown";
    inherit (cfg) packageJson pnpmLock pnpmWorkspace;
    deps = {inherit runCommandLocal; yq = yq-go;};
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
      yq-go
      ;
  };
  
  nodejs-pnpm-lock = {
    inherit dreamLock;
    packageJson = l.fromJSON (l.readFile cfg.packageJsonFile);
    pnpmLock = 
      if cfg.pnpmLockFile != null && l.pathExists cfg.pnpmLockFile
      then 
        # YAML parsing is handled in translate.nix via IFD
        {}  # Empty here since translate.nix will parse directly from file
      else lib.mkDefault {};
    pnpmWorkspace = 
      if cfg.pnpmWorkspaceFile != null && l.pathExists cfg.pnpmWorkspaceFile
      then 
        # TODO: Implement pnpm-workspace.yaml parsing
        # For now, return empty - workspace support is Phase 2
        {}
      else lib.mkDefault {};
  };
}