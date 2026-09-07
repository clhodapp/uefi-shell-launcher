# Commands

```bash
# Format
nix fmt

# Run checks
nix flake check

# Build the binaries
nix build .#uefi-shell-launcher
nix build .#uefi-shell
```

Local iteration from a consumer flake:

```bash
nix flake check --override-input uefi-shell-launcher path:../uefi-shell-launcher
```
