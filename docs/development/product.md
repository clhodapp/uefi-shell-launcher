# Product

The UEFI shell launcher exists so that a Secure Boot machine can keep a
UEFI shell on its boot menu without signing a binary that defeats
Secure Boot. The stock EDK2 shell's Debug1 and Install1 profiles write
raw memory, I/O ports, PCI configuration space, firmware variables and
the boot order; a db-signed copy of it is a trusted primitive for
patching image verification out of a running firmware.

The design has two pieces:

1. A reduced shell (`NO_SHELL_PROFILES`) with none of those commands,
   which is signed.
2. A signed launcher that boot-menu entries point at. It starts the
   reduced shell (adding `-nostartup` while Secure Boot is on), or,
   with the `insecure` load option, the unsigned stock shell. The
   launcher loads only through the firmware's `LoadImage`, so under
   Secure Boot the stock shell is refused by the firmware and the
   launcher explains what to do instead of failing silently.

Deployment is a consumer's concern: copy the three binaries to the
boot partition at the compiled-in paths, sign the two signable ones,
and write two Type 1 entries. The intended consumer in this workspace
is ch-boot-integrity's `boot-integrity.os-trust.uefiShell` option,
which does all of that inside its install hook.

Non-goals: no changes to the EDK2 shell sources, no in-launcher
verification of anything, no attempt to make the launcher itself a
menu.
