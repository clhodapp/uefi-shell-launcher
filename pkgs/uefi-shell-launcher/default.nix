# SPDX-License-Identifier: MIT
{ callPackage, ... }:
{
  # The EDK2 shell built with NO_SHELL_PROFILES: no command that writes
  # raw memory, I/O ports, PCI configuration space or firmware
  # variables, so it can be signed for Secure Boot.
  uefi-shell = callPackage ./uefi-shell { };

  # The boot-menu stub that starts that shell (Secure Boot on) or
  # nixpkgs' stock edk2-uefi-shell (Secure Boot off) through the
  # firmware's LoadImage, after explaining and waiting for a key.
  uefi-shell-launcher = callPackage ./uefi-shell-launcher { };
}
