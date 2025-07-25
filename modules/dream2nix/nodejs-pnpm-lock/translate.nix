{
  lib,
  nodejsUtils,
  parseSpdxId,
  simpleTranslate,
  ...
}: let
  l = lib // builtins;

  # IFD-based YAML parser - converts YAML files to JSON for Nix consumption
  parseYamlFile = deps: yamlPath: let
    yamlToJson = deps.runCommandLocal "yaml-to-json" {
      buildInputs = [deps.yq];
    } ''
      ${deps.yq}/bin/yq eval -o=json "${yamlPath}" > $out
    '';
  in
    l.fromJSON (l.readFile yamlToJson);

  # Parse pnpm-workspace.yaml and resolve workspace patterns
  parseWorkspaceConfig = deps: source: pnpmWorkspace: let
    # If pnpmWorkspace is already parsed, use it; otherwise parse from file
    workspaceConfig = 
      if pnpmWorkspace != {} 
      then pnpmWorkspace
      else if l.pathExists (source + "/pnpm-workspace.yaml")
      then parseYamlFile deps (source + "/pnpm-workspace.yaml")
      else if l.pathExists (source + "/package.json")
      then 
        # Fallback to package.json workspaces field
        let packageJson = l.fromJSON (l.readFile (source + "/package.json"));
        in { packages = packageJson.workspaces or []; }
      else { packages = []; };

    # Resolve workspace patterns to actual package paths
    # This is a simplified implementation - real pnpm uses glob matching
    resolveWorkspacePatterns = patterns: let
      # For now, handle simple patterns like "packages/*" and "apps/*"
      expandPattern = pattern: let
        # Remove trailing /* and scan directory
        baseDir = l.removeSuffix "/*" pattern;
        fullPath = toString source + "/" + baseDir;
      in
        if l.hasSuffix "/*" pattern && l.pathExists fullPath
        then
          let
            entries = l.readDir fullPath;
            subdirs = l.filterAttrs (name: type: type == "directory") entries;
          in
            l.mapAttrsToList (name: _: baseDir + "/" + name) subdirs
        else [pattern]; # Return as-is if not a glob pattern
    in
      l.flatten (l.map expandPattern patterns);

    workspacePackages = resolveWorkspacePatterns (workspaceConfig.packages or []);
    
    # Build workspace package info by reading each workspace's package.json
    buildWorkspaceInfo = workspacePaths: 
      l.listToAttrs (l.map (workspacePath: let
        packageJsonPath = toString source + "/" + workspacePath + "/package.json";
        packageJson = 
          if l.pathExists packageJsonPath
          then l.fromJSON (l.readFile packageJsonPath)
          else { name = l.baseNameOf workspacePath; version = "0.0.0"; };
      in {
        name = packageJson.name;
        value = {
          inherit (packageJson) version;
          path = workspacePath;
          packageJson = packageJson;
        };
      }) workspacePaths);
  in {
    inherit workspaceConfig workspacePackages;
    workspaceInfo = buildWorkspaceInfo workspacePackages;
  };

  # Parse pnpm package key to extract name and version info
  # Example: "/react@18.2.0" -> { name = "react"; version = "18.2.0"; peerSuffix = null; peerDeps = []; }
  # Example: "/react@18.2.0_peer@1.0.0+other@2.0.0" -> { name = "react"; version = "18.2.0"; peerSuffix = "peer@1.0.0+other@2.0.0"; peerDeps = [{ name = "peer"; version = "1.0.0"; } { name = "other"; version = "2.0.0"; }]; }
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
    
    # Parse peer dependency part: "peer@1.0.0+other@2.0.0"
    parsePeerDeps = peerStr: 
      if peerStr == null 
      then []
      else let
        # Split on + to get individual peer deps
        peerSpecs = l.splitString "+" peerStr;
        parsePeerSpec = spec: let
          # Find last @ to separate name from version
          specParts = l.splitString "@" spec;
          peerVersion = l.last specParts;
          peerNameParts = l.init specParts;
          peerName = l.concatStringsSep "@" peerNameParts;
        in {
          name = peerName;
          version = peerVersion;
        };
      in l.map parsePeerSpec peerSpecs;
      
    peerDeps = parsePeerDeps peerPart;
  in {
    inherit name version;
    peerSuffix = peerPart;
    peerDeps = peerDeps;
    originalKey = packageKey;
    
    # Generate a unique identifier for this peer dependency combination
    peerFingerprint = 
      if peerPart == null 
      then null
      else l.concatStringsSep "+" (l.map (p: "${p.name}@${p.version}") peerDeps);
  };

  # Convert pnpm resolution to dream2nix source format
  pnpmResolutionToSource = packageInfo: resolution: let
    # Detect source type from resolution
    hasGitInfo = resolution ? repo || resolution ? gitHead || 
                 (resolution ? tarball && l.hasPrefix "git+" (resolution.tarball or ""));
    hasHttpUrl = resolution ? tarball && l.hasPrefix "http" (resolution.tarball or "");
    hasIntegrity = resolution ? integrity;
  in
    if hasGitInfo then {
      type = "git";
      url = 
        if resolution ? repo 
        then resolution.repo
        else if resolution ? tarball && l.hasPrefix "git+" resolution.tarball
        then l.removePrefix "git+" resolution.tarball
        else "https://github.com/unknown/unknown.git";  # fallback
      rev = resolution.gitHead or "HEAD";
      hash = resolution.integrity or null;
    }
    else if hasHttpUrl then {
      type = "http";
      url = resolution.tarball;
      hash = resolution.integrity or null;
    }
    else {
      type = "http";
      url = "https://registry.npmjs.org/${packageInfo.name}/-/${packageInfo.name}-${packageInfo.version}.tgz";
      hash = resolution.integrity or null;
    };

  # Resolve workspace protocol dependencies
  resolveWorkspaceProtocol = workspaceInfo: dependencySpec: let
    # Handle different workspace protocol formats:
    # "workspace:^1.0.0" -> use workspace version matching semver range
    # "workspace:*" -> use latest workspace version
    # "workspace:alias@*" -> use workspace package with alias
    
    isWorkspaceProtocol = l.hasPrefix "workspace:" dependencySpec;
    
    parseWorkspaceSpec = spec: let
      cleanSpec = l.removePrefix "workspace:" spec;
      
      # Check if it's an alias format: "alias@*"
      aliasMatch = l.match "^([^@]+)@(.*)$" cleanSpec;
      
    in
      if aliasMatch != null
      then {
        type = "alias";
        alias = l.elemAt aliasMatch 0;
        versionSpec = l.elemAt aliasMatch 1;
      }
      else {
        type = "direct";
        versionSpec = cleanSpec;
      };
  in
    if !isWorkspaceProtocol
    then dependencySpec  # Return unchanged if not workspace protocol
    else let
      workspaceSpec = parseWorkspaceSpec dependencySpec;
      
      # For now, implement simple resolution - always use the workspace version
      # TODO: Implement proper semver range matching for workspace specs
      resolveWorkspaceVersion = spec: 
        if spec.type == "alias"
        then
          # Look for workspace package by alias name
          if workspaceInfo ? ${spec.alias}
          then workspaceInfo.${spec.alias}.version
          else throw "Workspace package '${spec.alias}' not found"
        else
          # For "workspace:*" or version specs, we need to find the matching package
          # This is simplified - real implementation would need the dependency name
          spec.versionSpec;
          
    in resolveWorkspaceVersion workspaceSpec;

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

    # Parse workspace configuration
    workspaceData = parseWorkspaceConfig deps source pnpmWorkspace;
    
    # Extract lockfile version and validate
    lockfileVersion = parsedLock.lockfileVersion or "unknown";
    
    # Handle different lockfile versions
    # pnpm lockfile versions: 5.3, 5.4, 6.0, 6.1, etc.
    lockfileVersionFloat = 
      if lockfileVersion == "6.0" || lockfileVersion == "6.1" then 6.0
      else if lockfileVersion == "5.4" then 5.4
      else if lockfileVersion == "5.3" then 5.3
      else if l.isFloat lockfileVersion then lockfileVersion
      else throw "Unable to parse lockfile version: ${toString lockfileVersion}";
    
    # Normalize structure based on lockfile version
    normalizedLock = 
      if lockfileVersionFloat >= 6.0
      then {
        # v6.0+ format
        dependencies = parsedLock.dependencies or {};
        devDependencies = parsedLock.devDependencies or {};
        packages = parsedLock.packages or {};
        importers = parsedLock.importers or {};
      }
      else if lockfileVersionFloat >= 5.3
      then {
        # v5.3-5.4 format - similar structure but some differences
        dependencies = parsedLock.dependencies or {};
        devDependencies = parsedLock.devDependencies or {};
        # In older versions, packages might be under 'specifiers'
        packages = parsedLock.packages or parsedLock.specifiers or {};
        importers = {};  # Not available in older versions
      }
      else throw "Unsupported pnpm lockfile version: ${toString lockfileVersion}";
    
    # Get dependencies from the normalized lockfile
    dependencies = normalizedLock.dependencies;
    devDependencies = normalizedLock.devDependencies;
    packages = normalizedLock.packages;
    importers = normalizedLock.importers;

    # Parse all package entries
    parsedPackages = l.mapAttrs (key: value: let
      packageInfo = parsePnpmPackageKey key;
      resolution = value.resolution or {};
      
      # Check if this is a workspace package
      workspacePackage = workspaceData.workspaceInfo.${packageInfo.name} or null;
      isWorkspacePackage = workspacePackage != null;
      
    in {
      inherit (packageInfo) name version peerSuffix;
      source = 
        if isWorkspacePackage
        then {
          type = "path";
          path = workspacePackage.path;
          rootName = projectName;
          rootVersion = packageVersion;
        }
        else pnpmResolutionToSource packageInfo resolution;
      
      # Extract dependencies, handling both dependencies and peerDependencies
      dependencies = l.attrNames (value.dependencies or {});
      peerDependencies = l.attrNames (value.peerDependencies or {});
      optionalDependencies = l.attrNames (value.optionalDependencies or {});
      
      # Store original pnpm data for reference
      pnpmData = value;
      inherit isWorkspacePackage;
    }) packages;

    # Get main package dependencies (from root level)
    mainDependencies = l.mapAttrsToList (name: version: {
      inherit name;
      # For pnpm, the version in dependencies section is the resolved version
      version = 
        if l.hasPrefix "workspace:" version
        then
          # Resolve workspace protocol dependencies
          let
            resolvedVersion = resolveWorkspaceProtocol workspaceData.workspaceInfo version;
            # For workspace dependencies, we need to find the actual workspace package
            workspacePackage = workspaceData.workspaceInfo.${name} or null;
          in
            if workspacePackage != null
            then workspacePackage.version
            else resolvedVersion
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
      } // (l.mapAttrs (name: info: info.version) workspaceData.workspaceInfo);

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
        
        git = dependencyObject: dependencyObject.source;
        
        path = dependencyObject: let
          # Check if this is a workspace dependency
          workspacePackage = workspaceData.workspaceInfo.${dependencyObject.name} or null;
        in
          if workspacePackage != null
          then {
            type = "path";
            path = workspacePackage.path;
            rootName = projectName;
            rootVersion = packageVersion;
          }
          else {
            # Handle file: dependencies outside of workspaces
            type = "path";
            path = l.removePrefix "file:" dependencyObject.source.url or dependencyObject.source.path or ".";
            rootName = projectName;
            rootVersion = packageVersion;
          };
      };

      getDependencies = dependencyObject: 
        map (depName: let
          # Advanced dependency resolution considering peer dependencies
          # Look for the dependency in our parsed packages, considering peer context
          
          # Find the best matching package considering peer dependencies
          findBestMatch = let
            # Get all packages with the same name
            candidatePackages = l.filter (pkg: pkg.name == depName) (l.attrValues parsedPackages);
            
            # If we have peer dependencies in the current package, try to find a match
            # that was built with compatible peer dependencies
            currentPeerFingerprint = dependencyObject.peerFingerprint or null;
            
            # Score packages based on peer dependency compatibility
            scorePackage = pkg: let
              hasPeerSuffix = pkg.peerFingerprint != null;
              peerMatches = 
                if currentPeerFingerprint == null || pkg.peerFingerprint == null
                then true  # No peer constraints to match
                else currentPeerFingerprint == pkg.peerFingerprint;
            in
              if peerMatches then 100
              else if !hasPeerSuffix then 50  # Prefer packages without peer constraints if no match
              else 10;  # Last resort: different peer constraints
              
            # Sort by score and pick the best
            scoredPackages = l.map (pkg: {
              inherit pkg;
              score = scorePackage pkg;
            }) candidatePackages;
            
            sortedPackages = l.sort (a: b: a.score > b.score) scoredPackages;
            bestMatch = 
              if l.length sortedPackages > 0
              then (l.head sortedPackages).pkg
              else null;
              
          in bestMatch;
          
          matchingPackage = findBestMatch;
          
        in {
          name = depName;
          version = 
            if matchingPackage != null 
            then matchingPackage.version
            else "unknown";
            
          # Include peer dependency context for better resolution
          peerContext = dependencyObject.peerFingerprint or null;
        }) dependencyObject.dependencies;
    });
in
  translate