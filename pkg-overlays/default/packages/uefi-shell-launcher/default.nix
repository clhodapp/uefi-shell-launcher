# SPDX-License-Identifier: MIT
{
  lib,
  edk2,
  edk2-uefi-shell,
  pkgsBuildHost,
}:

# A small EDK2 application that a single boot-menu entry points at
# instead of a shell binary. It reads the Secure Boot state, explains
# what it is about to start, waits for a key, and starts one of two
# shells from fixed paths on its own filesystem through the firmware's
# LoadImage, so Secure Boot policy decides what runs:
#
#   \EFI\uefi-shell\shell.efi           the reduced shell (pkgs.uefi-shell-launcher.uefi-shell),
#                                       signed; started with -nostartup
#                                       while Secure Boot is on.
#   \EFI\uefi-shell\shell-insecure.efi  the full shell (edk2-uefi-shell),
#                                       unsigned; started with no options
#                                       while Secure Boot is off.
#
# See the C source for the exact behaviour and messages.

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
    # Boot-partition paths the launcher is compiled against; the
    # consumer places the shells there.
    espDir = "EFI/uefi-shell";
    shellPath = "EFI/uefi-shell/shell.efi";
    insecureShellPath = "EFI/uefi-shell/shell-insecure.efi";
  };

  meta = {
    description = "Boot-menu launcher for a signed reduced UEFI shell, or the unsigned full shell where Secure Boot is off";
    license = lib.licenses.mit;
    platforms = edk2-uefi-shell.meta.platforms;
  };
})
