# SPDX-License-Identifier: MIT
{

  description = "UEFI shell launcher: a signed boot-menu stub that starts a reduced (signable) EDK2 shell, or the full shell only where Secure Boot allows it";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";

    # Stable channel on purpose: boot-path artifacts should churn as
    # little as possible, and nothing here needs bleeding-edge nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      lib = caisson.lib.caisson-core.mkLib {
        inherit (caisson.lib.caisson-core.pins.flake inputs) sources root;
        name = "uefi-shell-launcher";
        systems = [ "x86_64-linux" ];
        projects = {
          inherit caisson;
        };

        modules = caisson.lib.caisson-core.mkModules ./modules;
        configs = caisson.lib.caisson-core.mkModules ./configs;
        pkgSets = lib: lib.caisson.nixpkgs.mkConfigurations { };

        libOverlays = caisson.lib.caisson-core.mkLibOverlays ./lib-overlays;
        pkgOverlays = caisson.lib.caisson-core.mkPkgOverlays ./pkg-overlays;
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration { };

}
