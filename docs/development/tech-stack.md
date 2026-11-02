# Technology Stack

- **Nix** for package definitions and checks
- **caisson** for closed-input `mkLib` and class-keyed module exports
  ([github:nix-caisson/caisson](https://github.com/nix-caisson/caisson))
- **nixpkgs stable** (`nixos-26.05`): edk2 toolchain (`edk2.mkDerivation`),
  `edk2-uefi-shell` (both as the base of the reduced build and as the
  unsigned full shell), OVMF, qemu, sbsigntool and virt-firmware for
  the VM check
- **C (EDK2 UEFI application)**: the launcher lives under
  `pkg-overlays/default/packages/uefi-shell-launcher/src/UefiShellLauncherPkg`
  and is built out-of-tree against MdePkg via a minimal DSC, the same
  way [big-console](https://github.com/clhodapp/big-console) builds its
  driver
