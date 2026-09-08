# UEFI Shell Launcher

A boot-menu entry for the UEFI shell on a Secure Boot machine, without
signing a Secure Boot bypass.

The stock EDK2 shell includes commands that write raw memory (`mm`,
`hexedit -m`), I/O ports and PCI configuration space (`mm`), firmware
variables (`setvar`, `dmpstore -l`) and the boot order (`bcfg`). A copy
of that shell signed with a db-trusted key therefore hands anyone at the
keyboard pre-boot code execution the platform considers trusted, which
is why Microsoft does not sign it under its UEFI CA. This repository
splits the shell in two and puts a small signed stub in front:

- **`uefi-shell`** is the EDK2 shell built with `NO_SHELL_PROFILES`:
  only the Level 1, 2 and 3 command sets (file operations, scripting,
  environment). The Debug1, Driver1, Install1 and network profiles are
  absent, so nothing in the binary writes memory, ports, PCI space or
  firmware variables. That is what makes it acceptable to sign.
- **`uefi-shell-launcher`** is a UEFI application that a single
  boot-menu entry points at. It reads the firmware's Secure Boot state,
  explains what it is about to do, waits for a key, and starts one of
  two shells from fixed paths on its own filesystem through the
  firmware's `LoadImage`, so the firmware's Secure Boot policy decides
  what runs; the launcher verifies nothing itself and never touches
  image bytes.

| Secure Boot | What the launcher says | What starts after the key press |
|---|---|---|
| on | The shell starts without the memory manipulation commands and without startup scripts; disable Secure Boot in firmware setup if you need them. | `shell.efi` (reduced, signed) with `-nostartup`, so a `startup.nsh` on an attached volume cannot run automatically. |
| off | The full shell starts, with startup scripts enabled; the shell's own countdown lets you press ESC to skip `startup.nsh`. | `shell-insecure.efi` (the stock `edk2-uefi-shell`, unsigned) with no options. |

Choosing the entry changes no Secure Boot state. If the unsigned shell
is ever reached with Secure Boot on (a firmware that misreports the
`SecureBoot` variable), `LoadImage` refuses it and the launcher prints
the error and waits for a key before returning to the menu.

## Layout on the boot partition

The launcher is compiled against these paths, relative to the root of
the filesystem it was loaded from (the ESP, or an XBOOTLDR partition
when systemd-boot loads the entry from there):

```
EFI/uefi-shell/uefi-shell-launcher.efi   signed
EFI/uefi-shell/shell.efi                 the reduced shell, signed
EFI/uefi-shell/shell-insecure.efi        nixpkgs' edk2-uefi-shell, unsigned on purpose
```

systemd-boot Type 1 entry:

```
title    UEFI Shell
efi      /EFI/uefi-shell/uefi-shell-launcher.efi
sort-key o_uefi-shell
```

## Using it

Build (Nix): `nix build .#uefi-shell-launcher` and `nix build
.#uefi-shell`. The outputs are `uefi-shell-launcher.efi` and
`shell.efi`. Sign both with your db key; copy the stock shell from
`nixpkgs#edk2-uefi-shell` unsigned.

From a flake, `overlays.packages` is a plain nixpkgs overlay that adds
`pkgs.uefi-shell-launcher.uefi-shell-launcher` and
`pkgs.uefi-shell-launcher.uefi-shell`. Each derivation carries
`passthru.efi`, the path of its binary.

## What this does and does not protect

With the full shell unsigned, a signed launcher and reduced shell add
no pre-boot capability beyond running signed images with
attacker-chosen arguments and reading or writing files on any
filesystem the firmware can mount. Under Secure Boot that is what any
signed boot loader already permits. The residual risk is a
memory-corruption bug in the shell itself; the reduced build has a
smaller surface but was not written to be hostile-input safe.

Disabling Secure Boot to get the full shell is gated by the firmware
setup password, nothing here. If your disk encryption is bound to
Secure Boot state (a TPM policy over PCR 7), that toggle also withholds
the disk key, which is the intended coupling.

## Verification

`nix flake check` boots OVMF's Secure Boot build in QEMU twice, with
Secure Boot enforced and not, driving the serial console: it checks the
launcher's messages, that nothing starts before the key press, that
`startup.nsh` runs only when Secure Boot is off, and that `mm` exists
only in the shell started without Secure Boot. Secure Boot is enforced
by enrolling a throwaway certificate as PK, KEK and db with
`virt-fw-vars` and signing the two signable binaries with it.

## Licensing

MIT (see `LICENSE`). The launcher is original code built against
EDK2's BSD-2-Clause-Patent libraries; the reduced shell is an
unmodified EDK2 build with a different profile selection.
