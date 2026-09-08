# Testing

From the repository root:

```bash
nix flake check
```

Checks (x86_64-linux, checks partition):

- `smoke`: trivial dev-partition smoke check
- `launcher-vm`: boots OVMF's Secure Boot build twice from a FAT disk
  whose BOOTX64.EFI is the signed launcher, next to the signed reduced
  shell and the unsigned full shell, and drives the serial console
  with `tests/launcher-vm-drive.py`. With Secure Boot enforced: the
  launcher's explanation appears, Enter is sent only after the prompt,
  the reduced shell starts, `startup.nsh` does not run and `mm` is not
  recognized. With Secure Boot off: the explanation appears, the full
  shell starts and shows its own `startup.nsh` countdown, the script
  runs and `mm` exists. The transcripts land in the check output.

Gotchas: the check runs QEMU under TCG (no KVM in the sandbox), so each
boot takes tens of seconds; the driver's per-scenario timeout is
generous for that reason. Secure Boot enforcement comes from a
`virt-fw-vars`-generated variable store, not from OVMF's own enroll
application, so no key-enrollment boot is needed.
