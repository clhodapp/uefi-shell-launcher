# SPDX-License-Identifier: MIT
#
# The checks of uefi-shell-launcher: a flake-parts configuration
# declared inside the flake-parts caisson top
# (configs/flake/uefi-shell-launcher), whose dependencies are those of
# the caisson top with the pins of tests/dependencies beside them. The
# caisson top gathers the checks declared here into its `checks`
# output. A flake that lists uefi-shell-launcher as an input reads
# nothing of this configuration, so it locks none of the pins of
# tests/dependencies.
{ ... }:
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      # Duplicated in the formatter partition of
      # configs/flake/uefi-shell-launcher: the partition and this
      # configuration are separate evaluations.
      treefmt.programs.nixfmt.enable = true;

      caisson.checks = {
        treefmt = {
          category = "format";
          description = "the Nix files are formatted with nixfmt";
        };
        smoke = {
          derivation = pkgs.runCommand "uefi-shell-launcher-smoke-check" { } ''
            touch "$out"
          '';
          category = "eval";
          description = "the flake evaluates";
        };
        # Boots OVMF four times (safe/insecure entry, Secure Boot
        # enforced/not) and checks the launcher's decisions on the
        # serial console; see tests/launcher-vm.nix.
        launcher-vm = {
          derivation = import ../../../tests/launcher-vm.nix {
            inherit pkgs;
            launcher = pkgs.uefi-shell-launcher.uefi-shell-launcher;
            shell = pkgs.uefi-shell-launcher.uefi-shell;
            insecureShell = pkgs.edk2-uefi-shell;
          };
          category = "qemu";
          description = "the launcher starts the shell it is meant to under OVMF, with Secure Boot enforced and not, from the safe and the insecure entry";
        };
      };
    };
}
