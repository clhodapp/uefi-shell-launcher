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
2. A signed launcher that a single boot-menu entry points at. It reads
   the Secure Boot state, explains what it is about to start, waits for
   a key, and then starts the reduced shell with `-nostartup` (Secure
   Boot on) or the unsigned stock shell with no options (Secure Boot
   off, where the countdown of the stock shell handles `startup.nsh`). The
   launcher loads only through the firmware's `LoadImage`, so the
   firmware's policy, not the launcher's, is what keeps the stock shell
   out under Secure Boot.

Deployment is a consumer's concern: copy the three binaries to the
boot partition at the compiled-in paths, sign the two signable ones,
and write one Type 1 entry. A NixOS consumer typically does all of
that inside its boot loader's install hook, reading the paths from the
package's `passthru`.

Non-goals: no changes to the EDK2 shell sources, no in-launcher
verification of anything, no attempt to make the launcher itself a
menu.
