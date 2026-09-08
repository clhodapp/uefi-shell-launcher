/** @file
  UEFI shell launcher.

  A single boot-menu entry points at this application instead of at a
  shell binary. It starts one of two EDK2 shell builds that live next to
  it on the boot partition, chosen by the firmware's Secure Boot state:

    shell.efi           built with NO_SHELL_PROFILES: no raw memory,
                        I/O, PCI, or firmware-variable writers. Signed
                        with the platform's Secure Boot db key.
    shell-insecure.efi  the full shell (mm, hexedit, setvar, dmpstore,
                        bcfg, ...). Deliberately unsigned, so the
                        firmware refuses it while Secure Boot is on.

  With Secure Boot enabled the launcher explains that the shell starts
  without those commands and without startup scripts (-nostartup), and
  that disabling Secure Boot in firmware setup is the way to get them;
  a key press starts shell.efi. With Secure Boot disabled it explains
  that the full shell starts, with the shell's own startup.nsh prompt
  (ESC within its countdown skips the script); a key press starts
  shell-insecure.efi with no options.

  The launcher never verifies or loads image bytes itself. Both shells
  are started through the firmware's LoadImage/StartImage on a file
  device path, so the firmware's Secure Boot policy decides what runs.

  SPDX-License-Identifier: MIT
**/

#include <Uefi.h>
#include <Guid/GlobalVariable.h>
#include <Library/BaseLib.h>
#include <Library/DevicePathLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/LoadedImage.h>

#define SHELL_PATH           L"\\EFI\\uefi-shell\\shell.efi"
#define INSECURE_SHELL_PATH  L"\\EFI\\uefi-shell\\shell-insecure.efi"

STATIC CHAR16  mNoStartupOptions[] = L"-nostartup";

/**
  Whether the firmware reports Secure Boot as enforced.

  A missing or unreadable SecureBoot variable counts as disabled; the
  firmware's LoadImage still has the final say.
**/
STATIC
BOOLEAN
SecureBootEnabled (
  VOID
  )
{
  UINT8       Value;
  UINTN       Size;
  EFI_STATUS  Status;

  Value  = 0;
  Size   = sizeof (Value);
  Status = gRT->GetVariable (
                  EFI_SECURE_BOOT_MODE_NAME,
                  &gEfiGlobalVariableGuid,
                  NULL,
                  &Size,
                  &Value
                  );
  return !EFI_ERROR (Status) && (Value == 1);
}

/**
  Discard pending input, then block until one key is pressed.

  @return The key pressed (UnicodeChar is 0 for non-printing keys).
**/
STATIC
EFI_INPUT_KEY
WaitForAnyKey (
  VOID
  )
{
  EFI_INPUT_KEY  Key;
  UINTN          Index;

  while (gST->ConIn->ReadKeyStroke (gST->ConIn, &Key) == EFI_SUCCESS) {
  }

  gBS->WaitForEvent (1, &gST->ConIn->WaitForKey, &Index);
  if (EFI_ERROR (gST->ConIn->ReadKeyStroke (gST->ConIn, &Key))) {
    Key.ScanCode    = 0;
    Key.UnicodeChar = 0;
  }

  return Key;
}

/**
  Load and start an image from the launcher's own filesystem.

  @param ImageHandle   The launcher's image handle (parent of the child).
  @param DeviceHandle  Handle of the filesystem the launcher was read from.
  @param Path          Absolute file path on that filesystem.
  @param Options       Load options handed to the child, or NULL for none.
**/
STATIC
EFI_STATUS
StartFromBootPartition (
  IN EFI_HANDLE    ImageHandle,
  IN EFI_HANDLE    DeviceHandle,
  IN CONST CHAR16  *Path,
  IN CHAR16        *Options  OPTIONAL
  )
{
  EFI_DEVICE_PATH_PROTOCOL   *DevicePath;
  EFI_HANDLE                 Child;
  EFI_LOADED_IMAGE_PROTOCOL  *ChildImage;
  EFI_STATUS                 Status;

  DevicePath = FileDevicePath (DeviceHandle, Path);
  if (DevicePath == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }

  Child  = NULL;
  Status = gBS->LoadImage (FALSE, ImageHandle, DevicePath, NULL, 0, &Child);
  FreePool (DevicePath);
  if (EFI_ERROR (Status)) {
    return Status;
  }

  Status = gBS->HandleProtocol (
                  Child,
                  &gEfiLoadedImageProtocolGuid,
                  (VOID **)&ChildImage
                  );
  if (EFI_ERROR (Status)) {
    gBS->UnloadImage (Child);
    return Status;
  }

  if (Options != NULL) {
    ChildImage->LoadOptions     = Options;
    ChildImage->LoadOptionsSize = (UINT32)StrSize (Options);
  }

  return gBS->StartImage (Child, NULL, NULL);
}

EFI_STATUS
EFIAPI
UefiMain (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_LOADED_IMAGE_PROTOCOL  *Self;
  EFI_STATUS                 Status;
  CONST CHAR16               *Path;
  CHAR16                     *Options;

  Status = gBS->HandleProtocol (
                  ImageHandle,
                  &gEfiLoadedImageProtocolGuid,
                  (VOID **)&Self
                  );
  if (EFI_ERROR (Status)) {
    Print (L"uefi-shell-launcher: cannot find own loaded image: %r\n", Status);
    return Status;
  }

  if (SecureBootEnabled ()) {
    Print (
      L"\n"
      L"Secure Boot is enabled.\n"
      L"\n"
      L"Starting the UEFI Shell without the memory manipulation commands (mm,\n"
      L"hexedit, setvar, dmpstore, bcfg, ...) and without startup scripts\n"
      L"(-nostartup). Those commands can defeat Secure Boot from inside the\n"
      L"shell, so the build that has them is deliberately left unsigned and the\n"
      L"firmware will not load it while Secure Boot is enabled. If you need them,\n"
      L"disable Secure Boot in firmware setup, boot, and choose this entry again.\n"
      L"\n"
      L"Press any key to continue.\n"
      );
    WaitForAnyKey ();
    Path    = SHELL_PATH;
    Options = mNoStartupOptions;
  } else {
    Print (
      L"\n"
      L"Secure Boot is disabled.\n"
      L"\n"
      L"Starting the full UEFI Shell (memory manipulation commands available).\n"
      L"Startup scripts are enabled: a startup.nsh on an attached volume runs\n"
      L"unless you press ESC at the shell's own countdown.\n"
      L"\n"
      L"Press any key to continue.\n"
      );
    WaitForAnyKey ();
    Path    = INSECURE_SHELL_PATH;
    Options = NULL;
  }

  Status = StartFromBootPartition (ImageHandle, Self->DeviceHandle, Path, Options);
  if (EFI_ERROR (Status)) {
    Print (L"\nFailed to start %s: %r\n", Path, Status);
    Print (L"Press any key to return to the boot menu.\n");
    WaitForAnyKey ();
  }

  return Status;
}
