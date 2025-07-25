{
  lib,
  nodejsUtils,
  parseSpdxId,
  simpleTranslate,
  ...
}: let
  l = lib // builtins;

  # IFD-based YAML parser - converts pnpm-lock.yaml to JSON for Nix consumption
  parseYamlFile = deps: yamlPath: let
    yamlToJson = deps.runCommandLocal "pnpm-lock-json" {
      buildInputs = [deps.yq];
    } ''
      ${deps.yq}/bin/yq eval -o=json "${yamlPath}" > $out
    '';
  in
    l.fromJSON (l.readFile yamlToJson);

  # Parse pnpm package key to extract name and version info
  # Example: "/react@18.2.0" -> { name = "react"; version = "18.2.0"; peerSuffix = null; }
  # Example: "/react@18.2.0_peer@1.0.0+other@2.0.0" -> { name = "react"; version = "18.2.0"; peerSuffix = "peer@1.0.0+other@2.0.0"; }
  parsePnpmPackageKey = packageKey: let
    # Remove leading slash
    cleanKey = l.removePrefix "/" packageKey;
    
    # Split on underscore to separate main package from peer dependencies
    parts = l.splitString "_" cleanKey;
    mainPart = l.head parts;
    peerPart = if l.length parts > 1 then l.concatStringsSep "_" (l.tail parts) else null;
    
    # Parse main part: "react@18.2.0" or "@types/node@20.0.0"
    # Find the last @ in the string to separate name from version
    atParts = l.splitString "@" mainPart;
    # For scoped packages like "@types/node@20.0.0", we need the last part as version
    # and everything before the last @ as name
    version = l.last atParts;
    nameParts = l.init atParts;
    name = l.concatStringsSep "@" nameParts;
  in {
    inherit name version;
    peerSuffix = peerPart;
    originalKey = packageKey;
  };

  # Convert pnpm resolution to dream2nix source format
  pnpmResolutionToSource = packageInfo: resolution: {
    type = "http";
    url = 
      if resolution ? tarball 
      then resolution.tarball
      else "https://registry.npmjs.org/${packageInfo.name}/-/${packageInfo.name}-${packageInfo.version}.tgz";
    hash = resolution.integrity or null;
  };

  # Main translate function
  translate = {
    projectName,
    projectRelPath ? "",
    workspaces ? [],
    workspaceParent ? projectRelPath,
    source,
    tree,
    noDev ? true,
    nodejs ? "unknown",
    packageJson,
    pnpmLock,
    pnpmWorkspace ? {},
    deps,
    ...
  } @ args: let
    # Parse the YAML lockfile using IFD
    parsedLock = 
      if pnpmLock != {}
      then pnpmLock
      else parseYamlFile deps (source + "/pnpm-lock.yaml");

    # Extract lockfile version and validate
    lockfileVersion = parsedLock.lockfileVersion or "unknown";
    
    # Get dependencies from the lockfile
    dependencies = parsedLock.dependencies or {};
    devDependencies = parsedLock.devDependencies or {};
    packages = parsedLock.packages or {};

    # Parse all package entries
    parsedPackages = l.mapAttrs (key: value: let
      packageInfo = parsePnpmPackageKey key;
      resolution = value.resolution or {};
    in {
      inherit (packageInfo) name version peerSuffix;
      source = pnpmResolutionToSource packageInfo resolution;
      
      # Extract dependencies, handling both dependencies and peerDependencies
      dependencies = l.attrNames (value.dependencies or {});
      peerDependencies = l.attrNames (value.peerDependencies or {});
      optionalDependencies = l.attrNames (value.optionalDependencies or {});
      
      # Store original pnpm data for reference
      pnpmData = value;
    }) packages;

    # Get main package dependencies (from root level)
    mainDependencies = l.mapAttrsToList (name: version: {
      inherit name;
      # For pnpm, the version in dependencies section is the resolved version
      version = 
        if l.hasPrefix "workspace:" version
        then
          # TODO: Implement workspace protocol resolution
          throw "Workspace protocol not yet implemented: ${version}"
        else version;
    }) (dependencies // (if noDev then {} else devDependencies));

    packageVersion = packageJson.version or "unknown";
  in
    simpleTranslate
    ({
      getDepByNameVer,
      dependenciesByOriginalID,
      ...
    }: rec {
      translatorName = "nodejs-pnpm-lock";
      location = projectRelPath;

      # Input data for processing
      inputData = parsedPackages;

      defaultPackage = projectName;

      packages = {
        "${defaultPackage}" = packageVersion;
      };

      mainPackageDependencies = mainDependencies;

      subsystemName = "nodejs";

      subsystemAttrs = {
        nodejsVersion = l.toString nodejs;
        meta = nodejsUtils.getMetaFromPackageJson packageJson;
      };

      # Serialize packages for dream2nix format
      serializePackages = inputData: 
        l.mapAttrsToList (key: packageData: 
          packageData // {
            pname = packageData.name;
            # Filter out peer-dependency-only packages if requested
          }
        ) (l.filterAttrs (key: packageData:
          # Include all packages for now, but filter dev deps if noDev is true
          if noDev 
          then !(packageData.pnpmData.dev or false)
          else true
        ) inputData);

      getName = dependencyObject: dependencyObject.pname;

      getVersion = dependencyObject: dependencyObject.version;

      getSourceType = dependencyObject: dependencyObject.source.type;

      sourceConstructors = {
        http = dependencyObject: dependencyObject.source;
        
        # TODO: Add git and path constructors for workspace dependencies
        git = dependencyObject: 
          throw "Git dependencies not yet implemented in pnpm translator";
          
        path = dependencyObject:
          throw "Path dependencies not yet implemented in pnpm translator";
      };

      getDependencies = dependencyObject: 
        map (depName: let
          # Look for the dependency in our parsed packages
          # This is a simplified version - full implementation would need proper resolution
          matchingPackage = l.findFirst 
            (pkg: pkg.name == depName) 
            null 
            (l.attrValues parsedPackages);
        in {
          name = depName;
          version = 
            if matchingPackage != null 
            then matchingPackage.version
            else "unknown";
        }) dependencyObject.dependencies;
    });
in
  translate