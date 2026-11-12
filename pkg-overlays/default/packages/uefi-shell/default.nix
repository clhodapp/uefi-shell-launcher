# SPDX-License-Identifier: MIT
{ edk2-uefi-shell }:

# The EDK2 UEFI Shell built with NO_SHELL_PROFILES: only the Level 1, 2
# and 3 command sets (file operations, scripting, environment). The
# Debug1 profile (mm, hexedit, setvar, dmpstore, dmem, pci, loadpcirom,
# dblk, ...), Driver1 (load, connect, ...), Install1 (bcfg) and the
# network profiles are absent, so the binary has no way to write raw
# memory, I/O ports, PCI configuration space or firmware variables.
# That is what makes it acceptable to sign with the Secure Boot db key;
# the stock edk2-uefi-shell must stay unsigned.
#
# ShellPkg.dsc builds two shells. Only the first, carrying the FILE_GUID
# of Shell.inf, honours NO_SHELL_PROFILES; nixpkgs installs the second
# ("all commands integrated", GUID EA4BB293-...), so the install step is
# replaced as well as the build flag.

edk2-uefi-shell.overrideAttrs (old: {
  pname = "uefi-shell";

  buildFlags = (old.buildFlags or [ ]) ++ [
    "-D"
    "NO_SHELL_PROFILES"
  ];

  installPhase = ''
    runHook preInstall
    install -D -m0644 \
      Build/Shell/RELEASE*/*/Shell_7C04A583-9E3E-4f1c-AD65-E05268D0B4D1.efi \
      $out/shell.efi
    runHook postInstall
  '';

  meta = old.meta // {
    description = "UEFI Shell from Tianocore EDK2, without the Debug1/Driver1/Install1/network command profiles";
  };
})
