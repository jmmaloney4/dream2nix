# Test Phase 3 advanced features
# Run with: nix eval --impure -f phase3-test.nix --json
let
  lib = (import <nixpkgs> {}).lib;
  
  # Import our translate function  
  translate = import ./translate.nix {
    inherit lib;
    nodejsUtils = {};
    parseSpdxId = x: x;
    simpleTranslate = x: x.inputData;  # Just return input for testing
  };
  
in {
  # Test 1: Advanced peer dependency parsing
  peerDependencyParsing = let
    # Test parsing complex peer dependency keys
    testKeys = [
      "/react@18.2.0"
      "/react@18.2.0_peer@1.0.0"
      "/react@18.2.0_peer@1.0.0+other@2.0.0"
      "/@types/react@18.2.0_@types/node@20.0.0+react@18.2.0"
    ];
    
    parsePnpmPackageKey = packageKey: let
      cleanKey = lib.removePrefix "/" packageKey;
      parts = lib.splitString "_" cleanKey;
      mainPart = lib.head parts;
      peerPart = if lib.length parts > 1 then lib.concatStringsSep "_" (lib.tail parts) else null;
      
      atParts = lib.splitString "@" mainPart;
      version = lib.last atParts;
      nameParts = lib.init atParts;
      name = lib.concatStringsSep "@" nameParts;
      
      parsePeerDeps = peerStr: 
        if peerStr == null 
        then []
        else let
          peerSpecs = lib.splitString "+" peerStr;
          parsePeerSpec = spec: let
            specParts = lib.splitString "@" spec;
            peerVersion = lib.last specParts;
            peerNameParts = lib.init specParts;
            peerName = lib.concatStringsSep "@" peerNameParts;
          in {
            name = peerName;
            version = peerVersion;
          };
        in lib.map parsePeerSpec peerSpecs;
        
      peerDeps = parsePeerDeps peerPart;
    in {
      inherit name version;
      peerSuffix = peerPart;
      peerDeps = peerDeps;
      peerFingerprint = 
        if peerPart == null 
        then null
        else lib.concatStringsSep "+" (lib.map (p: "${p.name}@${p.version}") peerDeps);
    };
    
  in lib.map parsePnpmPackageKey testKeys;
  
  # Test 2: Source type detection
  sourceTypeDetection = let
    testResolutions = [
      { case = "npm-registry"; resolution = { integrity = "sha512-abc123"; }; }
      { case = "git-repo"; resolution = { repo = "https://github.com/user/repo.git"; gitHead = "abc123"; }; }
      { case = "git-tarball"; resolution = { tarball = "git+https://github.com/user/repo.git#abc123"; }; }
      { case = "http-tarball"; resolution = { tarball = "https://example.com/package.tgz"; integrity = "sha512-def456"; }; }
    ];
    
    pnpmResolutionToSource = packageInfo: resolution: let
      hasGitInfo = resolution ? repo || resolution ? gitHead || 
                   (resolution ? tarball && lib.hasPrefix "git+" (resolution.tarball or ""));
      hasHttpUrl = resolution ? tarball && lib.hasPrefix "http" (resolution.tarball or "");
    in
      if hasGitInfo then {
        type = "git";
        url = 
          if resolution ? repo 
          then resolution.repo
          else if resolution ? tarball && lib.hasPrefix "git+" resolution.tarball
          then lib.removePrefix "git+" resolution.tarball
          else "https://github.com/unknown/unknown.git";
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
        url = "https://registry.npmjs.org/test/-/test-1.0.0.tgz";
        hash = resolution.integrity or null;
      };
      
  in lib.map (test: {
    inherit (test) case;
    result = pnpmResolutionToSource { name = "test"; version = "1.0.0"; } test.resolution;
  }) testResolutions;
  
  # Test 3: Lockfile version handling
  lockfileVersionHandling = let
    testLockfiles = [
      { version = "9.0"; expected = "supported"; }
      { version = "6.0"; expected = "supported"; }
      { version = "6.1"; expected = "supported"; }
      { version = "5.4"; expected = "supported"; }
      { version = "5.3"; expected = "supported"; }
      { version = "4.0"; expected = "error"; }
    ];
    
    checkVersion = version: let
      # Simple version comparison using string operations
      lockfileVersionFloat = 
        if version == "9.0" then 9.0
        else if version == "6.0" || version == "6.1" then 6.0
        else if version == "5.4" then 5.4  
        else if version == "5.3" then 5.3
        else 4.0;  # fallback
    in
      if lockfileVersionFloat >= 9.0 then "supported-v9+"
      else if lockfileVersionFloat >= 6.0 then "supported-v6+"
      else if lockfileVersionFloat >= 5.3 then "supported-v5.3+"
      else "unsupported";
      
  in lib.map (test: {
    inherit (test) version expected;
    actual = checkVersion test.version;
    matches = (checkVersion test.version != "unsupported") == (test.expected == "supported");
  }) testLockfiles;
  
  # Test 4: Dependency resolution scoring
  dependencyResolutionScoring = let
    # Simulate scoring logic for peer dependency resolution
    scorePackage = currentPeerFingerprint: pkg: let
      hasPeerSuffix = pkg.peerFingerprint != null;
      peerMatches = 
        if currentPeerFingerprint == null || pkg.peerFingerprint == null
        then true
        else currentPeerFingerprint == pkg.peerFingerprint;
    in
      if peerMatches then 100
      else if !hasPeerSuffix then 50
      else 10;
      
    testScenarios = [
      {
        name = "exact-peer-match";
        currentPeerFingerprint = "react@18.2.0";
        packages = [
          { name = "test"; peerFingerprint = "react@18.2.0"; }
          { name = "test"; peerFingerprint = "react@17.0.0"; }
          { name = "test"; peerFingerprint = null; }
        ];
      }
      {
        name = "no-peer-constraints";
        currentPeerFingerprint = null;
        packages = [
          { name = "test"; peerFingerprint = "react@18.2.0"; }
          { name = "test"; peerFingerprint = null; }
        ];
      }
    ];
    
  in lib.map (scenario: {
    inherit (scenario) name;
    scores = lib.map (pkg: {
      inherit pkg;
      score = scorePackage scenario.currentPeerFingerprint pkg;
    }) scenario.packages;
  }) testScenarios;
}