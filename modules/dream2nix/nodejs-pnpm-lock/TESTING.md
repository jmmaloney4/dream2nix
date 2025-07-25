# Testing the nodejs-pnpm-lock Module

This guide covers various ways to test the nodejs-pnpm-lock module implementation.

## Prerequisites

Make sure you have:
- Nix with flakes enabled
- The module uses `yq-go` for YAML parsing (automatically provided by dream2nix)

## Testing Methods

### 1. Basic Module Loading Test

Test if the module loads without syntax errors:

```bash
cd modules/dream2nix/nodejs-pnpm-lock

# Test translate.nix loading  
nix eval --impure --expr '
let 
  lib = (import <nixpkgs> {}).lib;
  translate = import ./translate.nix { 
    inherit lib; 
    nodejsUtils = {}; 
    parseSpdxId = x: x; 
    simpleTranslate = x: x; 
  }; 
in "translate.nix loaded successfully"'
```

### 2. Module Discovery Test

Check if the module is properly discovered:

```bash
# From the dream2nix root directory
nix eval .#modules.dream2nix --apply builtins.attrNames | grep nodejs-pnpm-lock
```

### 3. YAML Parsing Test

Test the IFD-based YAML parsing:

```bash
# From the dream2nix root directory
nix eval --impure --expr '
let
  pkgs = import <nixpkgs> {};
  yamlPath = ./modules/dream2nix/nodejs-pnpm-lock/tests/packages/basic/pnpm-lock.yaml;
  yamlToJson = pkgs.runCommandLocal "test-yaml" {
    buildInputs = [pkgs.yq-go];
  } "${pkgs.yq-go}/bin/yq eval -o=json ${yamlPath} > $out";
  parsed = builtins.fromJSON (builtins.readFile yamlToJson);
in parsed.lockfileVersion'
```

### 4. Workspace Parsing Test

Test the workspace functionality:

```bash
# From the nodejs-pnpm-lock directory
nix eval --impure -f workspace-test.nix --json
```

This should show workspace packages being discovered and workspace protocol resolution working.

### 5. Test with the Included Test Packages

The module includes multiple test packages:

**Basic Package Test:**
```bash
cd modules/dream2nix/nodejs-pnpm-lock/tests/packages/basic
ls -la  # Should show package.json, pnpm-lock.yaml, index.js
```

**Workspace Test:**
```bash  
cd modules/dream2nix/nodejs-pnpm-lock/tests/packages/workspace
ls -la  # Should show pnpm-workspace.yaml, packages/, apps/

# Check workspace structure
tree .
```

Both test packages include complete examples with dependencies and realistic project structures.

### 4. Manual Integration Test

Create your own test project:

```bash
# Create a test directory
mkdir -p /tmp/pnpm-test
cd /tmp/pnpm-test

# Create package.json
cat > package.json << 'EOF'
{
  "name": "my-pnpm-test",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "^4.17.21"
  }
}
EOF

# If you have pnpm installed, generate the lockfile:
# pnpm install

# Or manually create a simple pnpm-lock.yaml:
cat > pnpm-lock.yaml << 'EOF'
lockfileVersion: '6.0'

dependencies:
  lodash:
    specifier: ^4.17.21
    version: 4.17.21

packages:

  /lodash@4.17.21:
    resolution: {integrity: sha512-v2kDEe57lecTulaDIuNTPy3Ry4gLGJ6Z1O3vE1krgXZNrsQ+LFTGHVxVjcXPs17LhbZVGedAJv8XZ1tvj5FvSg==}
    dev: false
EOF

# Create test.nix
cat > test.nix << 'EOF'
let
  flake = builtins.getFlake (toString /path/to/dream2nix);
in
  flake.lib.evalModules {
    packageSets.nixpkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      flake.modules.dream2nix.nodejs-pnpm-lock
      {
        name = "my-pnpm-test";
        version = "1.0.0";
        nodejs-pnpm-lock = {
          source = ./.;
        };
      }
    ];
  }
EOF

# Test evaluation
nix eval --impure -f test.nix config.name
```

### 5. Debug the Translation Process

To debug what's happening during translation:

```bash
cd modules/dream2nix/nodejs-pnpm-lock

# Test YAML parsing directly
nix eval --impure --expr '
let
  pkgs = import <nixpkgs> {};
  yamlPath = ./tests/packages/basic/pnpm-lock.yaml;
  yamlToJson = pkgs.runCommandLocal "test-yaml" {
    buildInputs = [pkgs.yq];
  } "${pkgs.yq}/bin/yq eval -o=json ${yamlPath} > $out";
  parsed = builtins.fromJSON (builtins.readFile yamlToJson);
in parsed.lockfileVersion'
```

### 6. Test Key Parsing Functions

Test the pnpm package key parsing:

```bash
nix eval --impure --expr '
let
  lib = (import <nixpkgs> {}).lib;
  
  # Simulate the parsePnpmPackageKey function
  parsePnpmPackageKey = packageKey: let
    cleanKey = lib.removePrefix "/" packageKey;
    parts = lib.splitString "_" cleanKey;
    mainPart = lib.head parts;
    peerPart = if lib.length parts > 1 then lib.concatStringsSep "_" (lib.tail parts) else null;
    atParts = lib.splitString "@" mainPart;
    name = lib.concatStringsSep "@" (lib.init atParts);  
    version = lib.last atParts;
  in {
    inherit name version;
    peerSuffix = peerPart;
    originalKey = packageKey;
  };
  
  testKeys = [
    "/lodash@4.17.21"
    "/react@18.2.0_peer@1.0.0+other@2.0.0"
    "/@types/node@20.0.0"
  ];
  
in map parsePnpmPackageKey testKeys'
```

## Common Issues and Troubleshooting

### IFD (Import From Derivation) Issues

If you get IFD-related errors, make sure:
- You're using `--impure` flag with nix eval
- `yq` is available in your system
- The pnpm-lock.yaml file exists and is readable

### Module Not Found

If the module isn't found:
```bash
# Check if it's properly exported
nix eval .#modules.dream2nix --apply builtins.attrNames
```

### YAML Parsing Errors

If YAML parsing fails:
```bash
# Test yq directly
yq eval -o=json path/to/pnpm-lock.yaml

# Check if the lockfile version is supported
yq eval '.lockfileVersion' path/to/pnpm-lock.yaml
```

## Test Development Workflow

When developing new features:

1. **Unit Tests**: Test individual functions in isolation
2. **Integration Tests**: Test the full module with simple inputs  
3. **Real-world Tests**: Test with actual pnpm projects
4. **Edge Cases**: Test with complex peer dependencies, workspaces, etc.

## Adding to CI/Test Suite

To add proper tests to the dream2nix test suite:

```bash
# Add to tests/nix-unit/ following the pattern of other tests
# See: tests/nix-unit/test_nodejs_lockutils/ for examples
```

## Performance Considerations

The IFD-based YAML parsing adds evaluation overhead. Monitor:
- Evaluation time with `time nix eval ...`
- Build cache effectiveness
- Memory usage during evaluation

## Next Steps

Once basic testing works:
1. Test with workspace projects (Phase 2)
2. Test complex peer dependency scenarios (Phase 3)
3. Integration tests with nodejs builders
4. Performance benchmarks vs npm translator