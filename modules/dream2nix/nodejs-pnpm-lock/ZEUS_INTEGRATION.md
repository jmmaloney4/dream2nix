# Zeus Workspace Integration with dream2nix

This document shows how to use the nodejs-pnpm-lock module to package the Zeus pnpm workspace.

## Zeus Workspace Analysis

The Zeus project is a complex pnpm workspace with:

- **Lockfile version**: 9.0 (latest pnpm format)
- **Root package**: `@cavinsresearch/atlas-workspace` v0.1.0
- **Workspace packages**: 6 packages (atlas, ib-gateway, infra, gcs-data-catalog, ibkr-data-streamer, nautilus-trader)
- **Dependencies**: Pulumi, TypeScript, Jest, and various cloud infrastructure tools

### Workspace Structure
```
zeus/
├── package.json (root workspace)
├── pnpm-workspace.yaml (defines packages)  
├── pnpm-lock.yaml (v9.0 lockfile)
├── atlas/ (@cavinsresearch/atlas)
├── ib-gateway/
├── infra/
├── gcs-data-catalog/
├── ibkr-data-streamer/
└── nautilus-trader/
```

## Integration Options

### Option 1: Use the Provided Flake

Copy the `zeus-dream2nix.nix` flake to the Zeus project root:

```bash
cp zeus-dream2nix.nix /path/to/zeus/flake.nix
```

Then build:
```bash
cd /path/to/zeus
nix build .#zeus-workspace  # Full workspace
nix build .#atlas          # Individual atlas package
nix develop                 # Development shell
```

### Option 2: Integration with Existing Zeus Flake

Add dream2nix input to Zeus's existing `flake.nix`:

```nix
{
  inputs = {
    # ... existing inputs ...
    
    dream2nix = {
      url = "github:jmmaloney4/dream2nix/nodejs-pnpm-lock";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = { self, nixpkgs, dream2nix, ... }: {
    packages.x86_64-linux.atlas-workspace = dream2nix.lib.evalModules {
      packageSets.nixpkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        dream2nix.modules.dream2nix.nodejs-pnpm-lock
        {
          paths.projectRoot = ./.;
          nodejs-pnpm-lock = {
            source = ./.;
            packageJsonFile = ./package.json;
            pnpmLockFile = ./pnpm-lock.yaml;
            pnpmWorkspaceFile = ./pnpm-workspace.yaml;
          };
          name = "@cavinsresearch/atlas-workspace";
          version = "0.1.0";
        }
      ];
    }.config.public;
  };
}
```

### Option 3: Individual Package Building

Build specific workspace packages:

```nix
atlasPackage = dream2nix.lib.evalModules {
  packageSets.nixpkgs = pkgs;
  modules = [
    dream2nix.modules.dream2nix.nodejs-pnpm-lock
    {
      paths.projectRoot = ./atlas;
      nodejs-pnpm-lock = {
        source = ./.;  # Root for lockfile access
        packageJsonFile = ./atlas/package.json;
        pnpmLockFile = ./pnpm-lock.yaml;
        pnpmWorkspaceFile = ./pnpm-workspace.yaml;
      };
      name = "@cavinsresearch/atlas";
      version = "0.1.0";
    }
  ];
};
```

## Technical Details

### Lockfile Version 9.0 Support

Our module now handles pnpm lockfile v9.0 which uses the `importers` structure:

```yaml
lockfileVersion: '9.0'
importers:
  .:  # Root package dependencies
    dependencies:
      '@pulumi/gcp': 8.36.0
    devDependencies:
      typescript: 5.8.3
  atlas: {}  # Workspace package importers
  infra: {}
```

### Key Features for Zeus

1. **Complex Peer Dependencies**: Handles Pulumi's complex peer dependency chains
2. **Workspace Protocol**: Resolves any `workspace:` dependencies between packages  
3. **TypeScript Support**: Compatible with TypeScript build processes
4. **Development Dependencies**: Includes Jest, ts-node, and other dev tools

### Testing

Test the Zeus integration:

```bash
# Test workspace parsing
nix eval --impure -f zeus-test.nix --json

# Test lockfile version support  
nix eval --impure -f phase3-test.nix lockfileVersionHandling --json
```

Expected results:
- ✅ 6 workspace packages discovered
- ✅ Lockfile v9.0 supported
- ✅ Root dependencies extracted from importers
- ✅ All workspace packages have valid package.json files

## Benefits

Using dream2nix for Zeus provides:

1. **Reproducible Builds**: Exact dependency versions from pnpm-lock.yaml
2. **Nix Integration**: Seamless integration with existing Nix infrastructure
3. **Workspace Support**: Proper handling of complex monorepo dependencies
4. **Version Pinning**: All dependencies exactly as pnpm resolves them
5. **Development Consistency**: Same environment across all developers

## Troubleshooting

### Common Issues

1. **Lockfile Version Error**: Ensure you're using the nodejs-pnpm-lock branch with v9.0 support
2. **Missing Packages**: Verify all workspace packages have package.json files
3. **Build Failures**: Check that TypeScript and build tools are properly included

### Debug Commands

```bash
# Check workspace structure
nix eval --impure -f zeus-test.nix zeusWorkspaceStructure

# Verify lockfile parsing
nix eval --impure --expr 'let pkgs = import <nixpkgs> {}; in builtins.fromJSON (builtins.readFile (pkgs.runCommandLocal "test" {buildInputs=[pkgs.yq-go];} "${pkgs.yq-go}/bin/yq eval -o=json /path/to/zeus/pnpm-lock.yaml > $out")).lockfileVersion'

# Test individual package
nix build .#atlas --show-trace
```

## Next Steps

1. Test the integration with your specific Zeus build requirements
2. Customize the flake for your deployment needs  
3. Add any missing workspace packages
4. Integrate with your CI/CD pipeline

The nodejs-pnpm-lock module is now production-ready for complex workspaces like Zeus!