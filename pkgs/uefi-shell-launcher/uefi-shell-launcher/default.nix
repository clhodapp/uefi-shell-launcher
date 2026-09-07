# SPDX-License-Identifier: MIT
{
  lib,
  edk2,
  edk2-uefi-shell,
  pkgsBuildHost,
}:

# A small EDK2 application that boot-menu entries point at instead of a
# shell binary. It starts one of two shells from fixed paths on the ESP
# through the firmware's LoadImage, so Secure Boot policy decides what
# runs:
#
#   \EFI\uefi-shell\shell.efi           the reduced shell (pkgs.uefi-shell-launcher.uefi-shell),
#                                       signed; -nostartup is added while
#                                       Secure Boot is on.
#   \EFI\uefi-shell\shell-insecure.efi  the full shell (edk2-uefi-shell),
#                                       unsigned; with Secure Boot on the
#                                       launcher explains and returns to
#                                       the menu.
#
# Load option "insecure" selects the second. See the C source for the
# exact behaviour and messages.

edk2.mkDerivation "UefiShellLauncherPkg/UefiShellLauncherPkg.dsc" (finalAttrs: {
  pname = "uefi-shell-launcher";
  version = "0.1";

  # Same toolchain as nixpkgs' edk2-uefi-shell (uuid, nasm, python).
  inherit (edk2-uefi-shell) nativeBuildInputs;
  strictDeps = true;

  env.PYTHON_COMMAND = "${lib.getBin pkgsBuildHost.python3}/bin/python3";

  postPatch = ''
    cp -r ${./src}/UefiShellLauncherPkg UefiShellLauncherPkg
    chmod -R u+w UefiShellLauncherPkg
  '';

  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -D -m0644 Build/UefiShellLauncher/RELEASE*/*/UefiShellLauncher.efi \
      $out/uefi-shell-launcher.efi
    runHook postInstall
  '';

  passthru = {
    efi = "${finalAttrs.finalPackage}/uefi-shell-launcher.efi";
    # ESP paths the launcher is compiled against; the consumer (e.g. ch-boot-integrity)
    # places the shells there.
    espDir = "EFI/uefi-shell";
    shellPath = "EFI/uefi-shell/shell.efi";
    insecureShellPath = "EFI/uefi-shell/shell-insecure.efi";
    insecureOption = "insecure";
  };

  meta = {
    description = "Boot-menu launcher for the fleet's signed and unsigned UEFI shells";
    license = lib.licenses.mit;
    platforms = edk2-uefi-shell.meta.platforms;
  };
})
