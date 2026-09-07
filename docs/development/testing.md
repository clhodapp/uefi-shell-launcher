# Testing

From the repository root:

```bash
nix flake check
```

Checks (x86_64-linux, checks partition):

- `smoke`: trivial dev-partition smoke check
- `launcher-vm`: boots OVMF's Secure Boot build four times from a FAT
  disk holding the signed launcher, the signed reduced shell and the
  unsigned full shell, and drives the serial console with
  `tests/launcher-vm-drive.py`. Scenarios: the safe entry with Secure
  Boot enforced (launcher announces `-nostartup`, `startup.nsh` does
  not run, `mm` is not recognized) and not enforced (`startup.nsh`
  runs); the insecure entry with Secure Boot enforced (refusal text,
  key press returns) and not enforced (full shell starts, `mm`
  exists). The transcripts land in the check output.

Gotchas: the check runs QEMU under TCG (no KVM in the sandbox), so each
boot takes tens of seconds; the driver's per-scenario timeout is
generous for that reason. Secure Boot enforcement comes from a
`virt-fw-vars`-generated variable store, not from OVMF's own enroll
application, so no key-enrollment boot is needed.
