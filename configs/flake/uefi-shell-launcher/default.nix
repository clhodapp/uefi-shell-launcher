# SPDX-License-Identifier: MIT
{ ... }:
{
  config,
  inputs,
  lib,
  self,
  ...
}:
{

  imports = [ inputs.flake-parts.flakeModules.partitions ];

  debug = false;
  caisson = {
    libOverlays.exported = libOverlays: { inherit (libOverlays) default; };
    modules = {
      flake.exported = modules: { inherit (modules) default; };
    };
  };

  # The sole package overlay is the `default` entry of this flake's
  # package overlay registry (pkg-overlays/, registered on mkLib): it adds
  # the `uefi-shell-launcher` scope to nixpkgs
  # (pkgs.uefi-shell-launcher.uefi-shell-launcher, .uefi-shell), the
  # package set applies it by default, and the flake exports it as
  # `pkgOverlays` and as the plain `overlays.default`.
  caisson.nixpkgs = {
    packages.export.enabled = true;
  };

  # checks and formatter live in isolated partitions; packages deliberately
  # do not: downstream flakes consume packages.* against this flake's main
  # lock (inherited locks), so dev-only inputs must not taint them.
  partitionedAttrs.checks = "checks";
  partitionedAttrs.formatter = "formatter";

  partitions.formatter = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).sources;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem.treefmt.programs.nixfmt.enable = true;
      };
  };

  partitions.checks = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).sources;
    module =
      { inputs, self, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem =
          { pkgs, ... }:
          {
            checks = {
              smoke = pkgs.runCommand "uefi-shell-launcher-smoke-check" { } ''
                touch "$out"
              '';
              # Boots OVMF four times (safe/insecure entry, Secure Boot
              # enforced/not) and checks the launcher's decisions on the
              # serial console; see tests/launcher-vm.nix.
              launcher-vm = import ../../../tests/launcher-vm.nix {
                inherit pkgs;
                launcher = pkgs.uefi-shell-launcher.uefi-shell-launcher;
                shell = pkgs.uefi-shell-launcher.uefi-shell;
                insecureShell = pkgs.edk2-uefi-shell;
              };
            };
            treefmt.programs.nixfmt.enable = true;
          };
      };
  };

}
