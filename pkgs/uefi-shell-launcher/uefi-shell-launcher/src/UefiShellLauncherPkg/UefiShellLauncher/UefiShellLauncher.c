/** @file
  UEFI shell launcher.

  Boot-menu entries point at this application instead of at a shell
  binary directly. It starts one of two EDK2 shell builds that live next
  to it on the EFI System Partition:

    shell.efi           built with NO_SHELL_PROFILES: no raw memory,
                        I/O, PCI, or firmware-variable writers. Signed
                        with the platform's Secure Boot db key.
    shell-insecure.efi  the full shell (mm, hexedit, setvar, dmpstore,
                        bcfg, ...). Deliberately unsigned, so the
                        firmware refuses it while Secure Boot is on.

  With no load options the launcher starts shell.efi; when Secure Boot
  is enabled it adds -nostartup so a startup.nsh on an attached volume
  cannot run automatically, and says so. With the load option
  "insecure" it starts shell-insecure.efi, or, when Secure Boot is
  enabled, explains that Secure Boot must be disabled in firmware setup
  first and returns to the boot menu.

  The launcher never verifies or loads image bytes itself. Both shells
  are started through the firmware's LoadImage/StartImage on a file
  device path, so the firmware's Secure Boot policy decides what runs.

  SPDX-License-Identifier: MIT
**/

#include <Uefi.h>
#include <Guid/GlobalVariable.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DevicePathLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/LoadedImage.h>

#define SHELL_PATH           L"\\EFI\\uefi-shell\\shell.efi"
#define INSECURE_SHELL_PATH  L"\\EFI\\uefi-shell\\shell-insecure.efi"
#define INSECURE_OPTION      L"insecure"

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
**/
STATIC
VOID
WaitForAnyKey (
  VOID
  )
{
  EFI_INPUT_KEY  Key;
  UINTN          Index;

  while (gST->ConIn->ReadKeyStroke (gST->ConIn, &Key) == EFI_SUCCESS) {
  }

  gBS->WaitForEvent (1, &gST->ConIn->WaitForKey, &Index);
  gST->ConIn->ReadKeyStroke (gST->ConIn, &Key);
}

/**
  Whether the launcher's own load options contain the word "insecure".

  systemd-boot passes an entry's `options` line as the load options.
  The buffer is copied so a non-terminated string cannot be overread.
**/
STATIC
BOOLEAN
InsecureModeRequested (
  IN EFI_LOADED_IMAGE_PROTOCOL  *Self
  )
{
  CHAR16   *Options;
  UINTN    Chars;
  BOOLEAN  Found;

  if ((Self->LoadOptions == NULL) || (Self->LoadOptionsSize < sizeof (CHAR16))) {
    return FALSE;
  }

  Chars   = Self->LoadOptionsSize / sizeof (CHAR16);
  Options = AllocateZeroPool ((Chars + 1) * sizeof (CHAR16));
  if (Options == NULL) {
    return FALSE;
  }

  CopyMem (Options, Self->LoadOptions, Chars * sizeof (CHAR16));
  Found = (StrStr (Options, INSECURE_OPTION) != NULL);
  FreePool (Options);
  return Found;
}

/**
  Load and start an image from the launcher's own filesystem.

  @param ImageHandle   The launcher's image handle (parent of the child).
  @param DeviceHandle  Handle of the filesystem the launcher was read from.
  @param Path          Absolute file path on that filesystem.
  @param Options       Load options handed to the child, or NULL.
**/
STATIC
EFI_STATUS
StartFromEsp (
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

  if (Options != NULL) {
    Status = gBS->HandleProtocol (
                    Child,
                    &gEfiLoadedImageProtocolGuid,
                    (VOID **)&ChildImage
                    );
    if (EFI_ERROR (Status)) {
      gBS->UnloadImage (Child);
      return Status;
    }

    ChildImage->LoadOptions     = Options;
    ChildImage->LoadOptionsSize = (UINT32)StrSize (Options);
  }

  return gBS->StartImage (Child, NULL, NULL);
}

STATIC
VOID
PrintInsecureRefusal (
  VOID
  )
{
  Print (
    L"\n"
    L"Secure Boot is enabled.\n"
    L"\n"
    L"This entry starts a build of the UEFI Shell that includes commands for\n"
    L"writing raw memory, I/O ports, PCI configuration space and firmware\n"
    L"variables (mm, hexedit, setvar, dmpstore, bcfg, ...). Such commands can\n"
    L"defeat Secure Boot from inside the shell, so that build is deliberately\n"
    L"left unsigned and the firmware refuses to load it while Secure Boot is\n"
    L"enabled.\n"
    L"\n"
    L"To use it, disable Secure Boot in firmware setup, boot, and choose this\n"
    L"entry again. Re-enable Secure Boot when you are finished.\n"
    L"\n"
    L"Press any key to return to the boot menu.\n"
    );
  WaitForAnyKey ();
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
  BOOLEAN                    Insecure;
  BOOLEAN                    SecureBoot;
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

  Insecure   = InsecureModeRequested (Self);
  SecureBoot = SecureBootEnabled ();
  Options    = NULL;

  if (Insecure) {
    if (SecureBoot) {
      PrintInsecureRefusal ();
      return EFI_SUCCESS;
    }

    Path = INSECURE_SHELL_PATH;
    Print (
      L"\nSecure Boot is disabled. Starting the UEFI Shell with memory\n"
      L"manipulation commands.\n\n"
      );
  } else {
    Path = SHELL_PATH;
    if (SecureBoot) {
      Options = mNoStartupOptions;
      Print (
        L"\nSecure Boot is enabled. Starting the UEFI Shell with startup scripts\n"
        L"disabled (-nostartup): a startup.nsh on an attached volume will not\n"
        L"run automatically.\n\n"
        );
      gBS->Stall (2 * 1000 * 1000);
    }
  }

  Status = StartFromEsp (ImageHandle, Self->DeviceHandle, Path, Options);
  if (EFI_ERROR (Status)) {
    Print (L"\nFailed to start %s: %r\n", Path, Status);
    if (Insecure && ((Status == EFI_SECURITY_VIOLATION) || (Status == EFI_ACCESS_DENIED))) {
      PrintInsecureRefusal ();
    } else {
      Print (L"Press any key to return to the boot menu.\n");
      WaitForAnyKey ();
    }
  }

  return Status;
}
