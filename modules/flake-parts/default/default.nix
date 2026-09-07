# SPDX-License-Identifier: MIT
#
# The exported flake module, for consumers composing this flake with
# caisson. Consuming the binaries needs none of it: `overlays.packages`
# is a plain nixpkgs overlay and `packages.<system>` holds the launcher
# and the reduced shell, so any flake can take either without adopting
# a framework.
{ mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./uefi-shell-launcher)
  ];
}
