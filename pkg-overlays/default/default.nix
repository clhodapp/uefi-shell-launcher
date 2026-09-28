# SPDX-License-Identifier: MIT
#
# The default package overlay: this flake's packages under
# `pkgs.uefi-shell-launcher` (`.uefi-shell-launcher`, `.uefi-shell`;
# packages/default.nix lists them). A consumer that lists this flake in
# `projects` holds it as `uefi-shell-launcher/default`, which its package
# sets apply by default. The scope name is bound here, so the packages
# land under `pkgs.uefi-shell-launcher` in any consumer.
{ closure-lib, ... }:
{
  overlay = closure-lib.caisson.nixpkgs.mkPackagesOverlay (
    { callPackage, ... }: import ./packages { inherit callPackage; }
  ) "uefi-shell-launcher";
}
