# SPDX-License-Identifier: MIT
{ callPackage, ... }:
{
  # The EDK2 shell built with NO_SHELL_PROFILES: no command that writes
  # raw memory, I/O ports, PCI configuration space or firmware
  # variables, so it can be signed for Secure Boot.
  uefi-shell = callPackage ./uefi-shell { };

  # The boot-menu stub that starts either that shell or nixpkgs' stock
  # edk2-uefi-shell through the firmware's LoadImage.
  uefi-shell-launcher = callPackage ./uefi-shell-launcher { };
}
