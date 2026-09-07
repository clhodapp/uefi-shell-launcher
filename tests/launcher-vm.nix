# SPDX-License-Identifier: MIT
# Proves the launcher's decisions end to end in a VM. OVMF (the Secure
# Boot capable build) boots a FAT disk four times:
#
#   a-sb    the signed launcher is BOOTX64.EFI, Secure Boot enforced.
#           It must say it is disabling startup scripts, start the
#           reduced shell, and the disk's startup.nsh must NOT run.
#   a-nosb  same disk, Secure Boot off. The reduced shell starts with
#           startup scripts allowed, so startup.nsh runs.
#   b-sb    the signed reduced shell is BOOTX64.EFI and its startup.nsh
#           runs the launcher with "insecure", Secure Boot enforced. The
#           launcher must refuse with the explanation and return to the
#           menu (here: the calling shell) on a key press.
#   b-nosb  same disk, Secure Boot off. The launcher must start the
#           full shell, where `mm` exists.
#
# In every run `mm` is typed at the resulting prompt: the reduced shell
# reports it as not recognized, the full shell does not. Secure Boot is
# enforced by enrolling a throwaway certificate as PK/KEK/db into the
# OVMF variable store (virt-fw-vars) and signing the launcher and the
# reduced shell with it; the full shell stays unsigned, as deployed.
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

    # --- FAT disks ----------------------------------------------------------
    mkimg() { # image, BOOTX64 source, startup.nsh content
      truncate -s 16M "$1"
      mkfs.vfat "$1" >/dev/null
      mmd -i "$1" ::/EFI ::/EFI/BOOT ::/EFI/uefi-shell
      mcopy -i "$1" "$2" ::/EFI/BOOT/BOOTX64.EFI
      mcopy -i "$1" launcher-signed.efi ::/EFI/uefi-shell/uefi-shell-launcher.efi
      mcopy -i "$1" shell-signed.efi ::/EFI/uefi-shell/shell.efi
      mcopy -i "$1" ${insecureShell}/shell.efi ::/EFI/uefi-shell/shell-insecure.efi
      printf '%s\r\n' "$3" > startup.nsh
      mcopy -i "$1" startup.nsh ::/startup.nsh
      mcopy -i "$1" startup.nsh ::/EFI/BOOT/startup.nsh
      mcopy -i "$1" startup.nsh ::/EFI/uefi-shell/startup.nsh
    }
    mkimg a.img launcher-signed.efi 'echo STARTUP_NSH_RAN'
    # The full shell finds this same startup.nsh (its default PATH covers
    # \efi\boot and \), so a flag file keeps it from re-running the
    # launcher after the launcher started it.
    mkimg b.img shell-signed.efi 'if exist fs0:\launched.flag then
      echo LAUNCHER_ALREADY_RAN
      goto done
    endif
    echo flag > fs0:\launched.flag
    echo RUNNING_LAUNCHER_INSECURE
    \EFI\uefi-shell\uefi-shell-launcher.efi insecure
    :done'

    # --- one boot: firmware + disk + scripted serial session ----------------
    run() { # name, image, vars, expect/send pairs...
      local name=$1 img=$2 vars=$3
      shift 3
      # Private copies: the guest writes to both (flag file, variables).
      cp "$vars" "$name.vars"
      cp "$img" "$name.img"
      qemu-system-x86_64 -machine q35 -accel tcg -m 1024 -nodefaults \
        -drive if=pflash,format=raw,readonly=on,file=${ovmf.firmware} \
        -drive if=pflash,format=raw,file="$name.vars" \
        -drive file="$name.img",format=raw,if=virtio \
        -display none \
        -chardev socket,id=ser,path="$name.sock",server=on,wait=off \
        -serial chardev:ser &
      local qemu_pid=$!
      python3 ${./launcher-vm-drive.py} "$name.sock" "$name.log" 600 "$@" \
        || { echo "driver failed in $name"; cat "$name.log"; exit 1; }
      kill "$qemu_pid" 2>/dev/null || true
      wait "$qemu_pid" 2>/dev/null || true
      echo "=== $name ==="
      cat "$name.log"
    }
    must()    { grep -qF -- "$2" "$1.log" || { echo "$1: expected '$2'"; exit 1; }; }
    mustnot() { ! grep -qF -- "$2" "$1.log" || { echo "$1: unexpected '$2'"; exit 1; }; }

    run a-sb a.img vars-sb.fd \
      'startup scripts' "" 'Shell>' 'mm\r' 'Shell>' 'reset -s\r'
    must    a-sb 'Secure Boot is enabled. Starting the UEFI Shell with startup scripts'
    mustnot a-sb 'STARTUP_NSH_RAN'
    must    a-sb "'mm' is not recognized"

    run a-nosb a.img vars-nosb.fd \
      'STARTUP_NSH_RAN' "" 'Shell>' 'mm\r' 'Shell>' 'reset -s\r'
    mustnot a-nosb 'Secure Boot is enabled'
    must    a-nosb "'mm' is not recognized"

    run b-sb b.img vars-sb.fd \
      'Press any key to return to the boot menu' '\r' 'Shell>' 'mm\r' 'Shell>' 'reset -s\r'
    must    b-sb 'RUNNING_LAUNCHER_INSECURE'
    must    b-sb 'deliberately'
    must    b-sb "'mm' is not recognized"

    run b-nosb b.img vars-nosb.fd \
      'Secure Boot is disabled' "" 'Shell>' 'mm\r' 'Shell>' 'reset -s\r'
    mustnot b-nosb "'mm' is not recognized"

    mkdir -p "$out"
    cp a-sb.log a-nosb.log b-sb.log b-nosb.log "$out/"
  ''
