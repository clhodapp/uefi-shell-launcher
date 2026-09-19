# SPDX-License-Identifier: MIT
{

  description = "UEFI shell launcher: a signed boot-menu stub that starts a reduced (signable) EDK2 shell, or the full shell only where Secure Boot allows it";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";

    # Stable channel on purpose: boot-path artifacts should churn as
    # little as possible, and nothing here needs bleeding-edge nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      lib = caisson.lib.caisson-core.mkLib {
        inherit inputs;
        systems = [ "x86_64-linux" ];

        projects = {
          inherit caisson;
        };

        modules = lib: {
          flake = {
            default = lib.caisson.flake-parts.mkModule ./modules/flake-parts/default;
          };
        };

        libOverlays = mkLibOverlay: {
          default = mkLibOverlay ./lib-overlays/default;
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      name = "uefi-shell-launcher";
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/default;
    };

}
