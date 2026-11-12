# SPDX-License-Identifier: MIT
# Proves the launcher's decisions end to end in a VM. OVMF (the Secure
# Boot capable build) boots a FAT disk whose BOOTX64.EFI is the signed
# launcher, three times:
#
#   sb    Secure Boot enforced. The launcher must explain that the shell
#         starts without the memory manipulation commands and without
#         startup scripts, wait for a key, and start the reduced shell:
#         the disk's startup.nsh must NOT run and `mm` is not
#         recognized.
#   nosb  Secure Boot off. After the key press the full shell starts
#         with no options, shows the startup.nsh countdown, runs
#         startup.nsh, and `mm` exists.
#
# Secure Boot is enforced by enrolling a throwaway certificate as
# PK/KEK/db into the OVMF variable store (virt-fw-vars) and signing the
# launcher and the reduced shell with it; the full shell stays unsigned,
# as deployed.
{
  pkgs,
  launcher,
  shell,
  insecureShell,
}:
let
  ovmf = pkgs.OVMFFull;
in
pkgs.runCommand "uefi-shell-launcher-vm-check"
  {
    nativeBuildInputs = [
      pkgs.qemu_test
      pkgs.mtools
      pkgs.dosfstools
      pkgs.sbsigntool
      pkgs.openssl
      pkgs.python3
      pkgs.python3Packages.virt-firmware
    ];
  }
  ''
    # --- throwaway Secure Boot key, signed copies, variable stores ----------
    openssl req -new -x509 -newkey rsa:2048 -nodes -subj '/CN=launcher-vm db/' \
      -keyout db.key -out db.crt -days 30 >/dev/null 2>&1
    sbsign --key db.key --cert db.crt --output launcher-signed.efi ${launcher}/uefi-shell-launcher.efi
    sbsign --key db.key --cert db.crt --output shell-signed.efi ${shell}/shell.efi
    guid=6f0a3a5b-1c2d-4e5f-8a9b-0c1d2e3f4a5b
    virt-fw-vars --input ${ovmf.variables} --output vars-sb.fd --secure-boot \
      --set-pk "$guid" db.crt --add-kek "$guid" db.crt --add-db "$guid" db.crt
    install -m0644 ${ovmf.variables} vars-nosb.fd

    # --- FAT disk: the launcher as the default boot loader ------------------
    truncate -s 16M esp.img
    mkfs.vfat esp.img >/dev/null
    mmd -i esp.img ::/EFI ::/EFI/BOOT ::/EFI/uefi-shell
    mcopy -i esp.img launcher-signed.efi ::/EFI/BOOT/BOOTX64.EFI
    mcopy -i esp.img launcher-signed.efi ::/EFI/uefi-shell/uefi-shell-launcher.efi
    mcopy -i esp.img shell-signed.efi ::/EFI/uefi-shell/shell.efi
    mcopy -i esp.img ${insecureShell}/shell.efi ::/EFI/uefi-shell/shell-insecure.efi
    printf 'echo STARTUP_NSH_RAN\r\n' > startup.nsh
    mcopy -i esp.img startup.nsh ::/startup.nsh
    mcopy -i esp.img startup.nsh ::/EFI/BOOT/startup.nsh
    mcopy -i esp.img startup.nsh ::/EFI/uefi-shell/startup.nsh

    # --- one boot: firmware + disk + scripted serial session ----------------
    # The guest's serial console goes to a file (-serial file:) and the
    # driver injects keys over QMP (send-key). A bidirectional
    # unix-socket serial chardev does not flush OVMF's output reliably
    # until the peer disconnects, so the two directions are split. A real
    # VGA device gives the console a valid text-mode geometry (the EDK2
    # shell positions its prompt from the console mode; with no display
    # the row is degenerate and the prompt lands off-screen); -display
    # none keeps it headless, and send-key reaches the graphics console's
    # keyboard, which is OVMF's ConIn.
    run() { # name, vars, expect/send pairs...
      local name=$1 vars=$2
      shift 2
      cp "$vars" "$name.vars"
      cp esp.img "$name.img"
      rm -f "$name.out" "$name.qmp"
      qemu-system-x86_64 -machine q35 -accel tcg -m 1024 -nodefaults \
        -drive if=pflash,format=raw,readonly=on,file=${ovmf.firmware} \
        -drive if=pflash,format=raw,file="$name.vars" \
        -drive file="$name.img",format=raw,if=virtio \
        -device VGA -display none \
        -serial file:"$name.out" \
        -qmp unix:"$name.qmp",server=on,wait=off &
      local qemu_pid=$!
      python3 ${./launcher-vm-drive.py} "$name.out" "$name.qmp" "$name.log" 600 "$@" \
        || { echo "driver failed in $name"; cat "$name.log" 2>/dev/null; exit 1; }
      kill "$qemu_pid" 2>/dev/null || true
      wait "$qemu_pid" 2>/dev/null || true
      echo "=== $name ==="
      cat "$name.log"
    }
    must()    { grep -qF -- "$2" "$1.log" || { echo "$1: expected '$2'"; exit 1; }; }
    mustnot() { ! grep -qF -- "$2" "$1.log" || { echo "$1: unexpected '$2'"; exit 1; }; }

    # The launcher waits for a key in both states; the driver sends Enter
    # only once the prompt has appeared, which is the check that the
    # shell did not start before the key press.
    run sb vars-sb.fd \
      'Press any key to continue' '\r' 'Shell>' 'mm\r' 'Shell>' 'reset -s\r'
    must    sb 'Secure Boot is enabled'
    must    sb 'Startup scripts are also disabled'
    mustnot sb 'STARTUP_NSH_RAN'
    mustnot sb 'Press ESC'
    must    sb "'mm' is not recognized"

    run nosb vars-nosb.fd \
      'Press any key to continue' '\r' 'STARTUP_NSH_RAN' "" 'Shell>' 'mm\r' 'Shell>' 'reset -s\r'
    must    nosb 'Secure Boot is disabled'
    must    nosb 'Press ESC'
    mustnot nosb "'mm' is not recognized"

    mkdir -p "$out"
    cp sb.log nosb.log "$out/"
  ''
