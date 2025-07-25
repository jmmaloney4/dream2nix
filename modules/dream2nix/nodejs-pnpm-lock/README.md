# nodejs-pnpm-lock

A dream2nix module for building Node.js packages from pnpm lockfiles (`pnpm-lock.yaml`).

## Status

✅ **Phase 1 Complete** - Basic pnpm-lock.yaml support  
✅ **Phase 2 Complete** - Workspace support  
✅ **Phase 3 Complete** - Advanced features

## Overview

This module enables dream2nix to work with pnpm packages by parsing `pnpm-lock.yaml` files and handling pnpm's unique features like workspace protocols and advanced peer dependency resolution.

## Background Analysis

### Why pnpm Support is Needed

pnpm (performant npm) has gained significant adoption due to its:
- **Space Efficiency**: Uses hard linking and a global content-addressable store
- **Strict Dependency Management**: Prevents access to undeclared dependencies
- **Superior Peer Dependency Handling**: Creates multiple hard-linked sets for different peer dependency combinations
- **Workspace Protocol**: Provides precise local package referencing with `workspace:` protocol

Major projects using pnpm include Next.js, Vite, Vue, and many others, making pnpm support essential for dream2nix's ecosystem coverage.

### Technical Challenges

#### 1. Lockfile Format Differences

**pnpm-lock.yaml vs package-lock.json:**
- **Format**: YAML (requires IFD translator) vs JSON (native Nix support)
- **Structure**: Snapshot-based dependency tracking vs nested dependency trees
- **Peer Dependencies**: Complex suffixes like `foo@1.0.0_bar@1.0.0+baz@1.1.0` vs simpler resolution
- **Content Addressing**: Uses integrity hashes for content-addressable storage

#### 2. Workspace Protocol Support

pnpm's `workspace:` protocol requires special handling:
```yaml
dependencies:
  my-package: "workspace:^1.0.0"  # References local workspace package
  other-pkg: "workspace:*"        # Always use workspace version
  alias-pkg: "workspace:alias@*"  # Workspace package with alias
```

#### 3. Advanced Peer Dependency Resolution

Unlike npm/yarn, pnpm creates multiple hard-linked sets when peer dependencies are involved:
- Single package version can have different dependency configurations
- Complex symlink structures ensure correct peer dependency resolution
- Multiple dependency sets for each unique peer dependency combination

#### 4. Workspace Configuration

pnpm workspaces are configured via `pnpm-workspace.yaml`:
```yaml
packages:
  - 'packages/*'
  - 'apps/*'
  - '!**/test/**'
```

This differs from npm's `package.json` workspace configuration.

## Implementation Approach Analysis

After analyzing the dream2nix architecture and pnpm specifications, three approaches were considered:

### Approach 1: New `nodejs-pnpm-lock` Module ✅ **Recommended**

**Architecture:** Create dedicated `modules/dream2nix/nodejs-pnpm-lock/` following existing patterns.

**Pros:**
- ✅ Aligns with dream2nix's modular architecture
- ✅ Clean separation of concerns between package managers
- ✅ Can evolve independently without affecting npm support
- ✅ Lower risk implementation strategy
- ✅ Community validation from issue #234

**Cons:**
- ⚠️ Requires IFD translator for YAML parsing
- ⚠️ Initial implementation complexity

### Approach 2: Extend `nodejs-package-lock` Module ❌

**Architecture:** Modify existing package-lock translator to handle pnpm-lock.yaml.

**Pros:**
- ✅ Code reuse from existing npm infrastructure

**Cons:**
- ❌ Architecture mismatch - pnpm structure fundamentally different
- ❌ Creates complexity mixing two different lock formats
- ❌ Maintenance issues - changes affect both formats
- ❌ Violates single responsibility principle

### Approach 3: Universal Node.js Lock Translator ❌

**Architecture:** Build new module handling multiple lock file formats.

**Pros:**
- ✅ Future-proof for other package managers

**Cons:**
- ❌ Over-engineering for current needs
- ❌ Complex abstraction layer
- ❌ Higher maintenance burden
- ❌ Premature optimization

## Implementation Plan

### Phase 1: Basic pnpm-lock.yaml Support

**Goal:** Support standard pnpm projects without workspaces

**Tasks:**
1. **IFD YAML Parser**
   - Create derivation using `yq` to convert `pnpm-lock.yaml` to JSON
   - Handle pnpm's lockfile structure and format
   - Parse dependency snapshots and integrity hashes

2. **Basic Translation Logic**
   - Implement `translate.nix` following `nodejs-package-lock` patterns
   - Handle pnpm's peer dependency suffixes in package resolution
   - Convert pnpm dependencies to dream2nix's internal format

3. **Package Resolution**
   - Map pnpm's content-addressable identifiers to npm registry URLs
   - Handle pnpm's integrity hash format
   - Support basic dependency tree construction

**Expected Deliverables:**
- Working `translate.nix` with IFD YAML parser
- Basic test cases for simple pnpm projects
- Documentation for basic usage

### Phase 2: Workspace Support ✅ **COMPLETED**

**Goal:** Full pnpm workspace protocol support

**Implemented Features:**
1. **Workspace Configuration**
   - ✅ Parse `pnpm-workspace.yaml` configuration
   - ✅ Support workspace pattern matching (`packages/*`, `apps/*`)
   - ✅ Fallback to `package.json` workspaces field if needed

2. **Workspace Protocol Resolution**
   - ✅ Implement `workspace:` protocol parsing (`workspace:*`, `workspace:^1.0.0`)
   - ✅ Resolve workspace dependencies to actual package versions
   - ✅ Handle workspace aliases and version specifiers

3. **Inter-workspace Dependencies**
   - ✅ Build dependency graphs between workspace packages
   - ✅ Support workspace dependencies as path sources
   - ✅ Integration with dream2nix's package system

**Deliverables:**
- ✅ Complete workspace protocol support
- ✅ Comprehensive test cases with multi-package workspace
- ✅ Path source constructor for workspace dependencies

### Phase 3: Advanced Features ✅ **COMPLETED**

**Goal:** Full feature parity with pnpm's dependency resolution

**Implemented Features:**
1. **Advanced Peer Dependencies**
   - ✅ Parse complex peer dependency suffixes (`/pkg@1.0.0_peer@2.0.0+other@3.0.0`)
   - ✅ Generate peer dependency fingerprints for resolution
   - ✅ Scoring-based dependency resolution considering peer contexts
   - ✅ Support for scoped packages in peer dependencies

2. **Git and Path Dependencies**
   - ✅ Detect and handle git repositories in resolutions
   - ✅ Support git+ protocol URLs
   - ✅ Handle file: protocol dependencies
   - ✅ Path source constructor for non-workspace dependencies

3. **Multiple Lockfile Versions**
   - ✅ Support pnpm lockfile versions 5.3, 5.4, 6.0, 6.1+
   - ✅ Normalize lockfile structure across versions
   - ✅ Handle version-specific differences in package organization

4. **Enhanced Dependency Resolution**
   - ✅ Improved source type detection (http/git/path)
   - ✅ Better package matching with peer dependency awareness
   - ✅ Context-aware dependency resolution scoring

**Deliverables:**
- ✅ Complete pnpm feature support for production use
- ✅ Advanced test suite with complex scenarios
- ✅ Integration examples with nodejs builders
- ✅ Comprehensive documentation

## Technical Implementation Details

### IFD Translator Pattern

Following the pattern established in issue #234, YAML parsing requires Import From Derivation (IFD):

```nix
# translate.nix structure
{ lib, nodejsUtils, simpleTranslate, ... }:
let
  parseYaml = yamlFile: 
    # Create derivation that converts YAML to JSON using yq
    # This will be called during evaluation (IFD)
    ...;
    
  translate = { pnpmLock, ... }:
    let
      parsedLock = parseYaml pnpmLock;
    in
      simpleTranslate { ... };
in
  translate
```

### Lockfile Structure Mapping

pnpm-lock.yaml structure requires careful mapping:

```yaml
# pnpm-lock.yaml
lockfileVersion: '6.0'
settings:
  autoInstallPeers: true

dependencies:
  react: 18.2.0
  
packages:
  /react@18.2.0:
    resolution: {integrity: sha512-...}
    engines: {node: '>=0.10.0'}
    
  /react@18.2.0_peer-dep@1.0.0:
    resolution: {integrity: sha512-...}
    peerDependencies:
      peer-dep: ^1.0.0
```

Must map to dream2nix's expected format:
```nix
{
  packages = {
    "react" = {
      version = "18.2.0";
      dependencies = [ ... ];
      source = { type = "http"; url = "..."; hash = "..."; };
    };
  };
}
```

### Workspace Protocol Handling

The workspace protocol requires special resolution logic:

```nix
resolveWorkspaceProtocol = workspaceSpec: workspacePackages:
  if lib.hasPrefix "workspace:" workspaceSpec
  then
    let
      spec = lib.removePrefix "workspace:" workspaceSpec;
      # Handle workspace:^1.0.0, workspace:*, workspace:alias@*
    in
      resolveWorkspaceVersion spec workspacePackages
  else
    workspaceSpec;
```

## Risk Mitigation

### IFD Concerns
- **Risk**: IFD can slow evaluation and complicate caching
- **Mitigation**: Follow established IFD patterns in dream2nix, optimize YAML parsing derivation

### Complexity Management
- **Risk**: pnpm's advanced features create implementation complexity
- **Mitigation**: Phased approach starting with MVP, iterative development based on community feedback

### Maintenance Burden
- **Risk**: New module requires ongoing maintenance
- **Mitigation**: Follow dream2nix testing standards, comprehensive documentation, community involvement

## Testing Strategy

### Unit Tests
- YAML parsing with various pnpm-lock.yaml formats
- Workspace protocol resolution edge cases
- Peer dependency suffix parsing
- Integration with existing nodejs utilities

### Integration Tests
- Real-world pnpm projects (Next.js, Vite-based apps)
- Complex monorepo scenarios
- Mixed workspace and non-workspace dependencies
- Development and production builds

### Compatibility Tests
- Different pnpm lockfile versions (5.4, 6.0, 6.1)
- Various Node.js versions
- Integration with all nodejs builders

## References

### Primary Sources
- **dream2nix Documentation**: https://dream2nix.dev/
- **GitHub Issue #234**: https://github.com/nix-community/dream2nix/issues/234
- **pnpm Documentation**: https://pnpm.io/
  - [Workspaces](https://pnpm.io/workspaces)
  - [Limitations](https://pnpm.io/limitations)  
  - [Peer Dependencies](https://pnpm.io/how-peers-are-resolved)
  - [pnpm vs npm](https://pnpm.io/pnpm-vs-npm)

### Community Validation
- Issue #234 received 10 👍 reactions indicating community demand
- @wmertens confirmed IFD translator requirement for YAML parsing
- @hsjobeki noted pnpm as "the only tool capable of resolving peerDependency conflicts"

### Architecture Patterns
- Follows established dream2nix modular architecture
- Based on analysis of existing modules:
  - `nodejs-package-lock/` (npm support)
  - `php-composer-lock/` (PHP Composer support)
  - `rust-cargo-lock/` (Rust Cargo support)

This implementation plan provides a systematic approach to adding robust pnpm support to dream2nix while maintaining architectural consistency and managing complexity through phased development.