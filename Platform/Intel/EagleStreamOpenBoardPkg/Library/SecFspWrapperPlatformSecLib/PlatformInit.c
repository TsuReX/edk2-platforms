/** @file
  Sample to provide platform init function.

  @copyright
  Copyright (c) 2014 - 2021, Intel Corporation. All rights reserved.<BR>

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/


#include <PiPei.h>
#include <Library/DebugLib.h>
#include <Library/SerialPortLib.h>
#include <Library/SecBoardInitLib.h>
#include <Library/TestPointCheckLib.h>
#include <Library/IoLib.h>

/**
  Platform initialization.

  @param[in] FspHobList   HobList produced by FSP.
  @param[in] StartOfRange Start of temporary RAM.
  @param[in] EndOfRange   End of temporary RAM.
**/
VOID
EFIAPI
PlatformInit (
  IN VOID                 *FspHobList,
  IN VOID                 *StartOfRange,
  IN VOID                 *EndOfRange
  )
{
  //
  // Platform initialization
  // Enable Serial port here
  //
  if (PcdGetBool(PcdSecSerialPortDebugEnable)) {
    SerialPortInitialize ();
  }

  DEBUG ((DEBUG_INFO, "PrintPeiCoreEntryPointParam in PlatformInit\n"));
  DEBUG ((DEBUG_INFO, "FspHobList - 0x%x\n", FspHobList));
  DEBUG ((DEBUG_INFO, "StartOfRange - 0x%x\n", StartOfRange));
  DEBUG ((DEBUG_INFO, "EndOfRange - 0x%x\n", EndOfRange));

    while(1) {
	IoWrite8(0x80,0x11);
	IoWrite8(0x80,0x22);
	IoWrite8(0x80,0x33);
	IoWrite8(0x80,0x44);
    }
  BoardAfterTempRamInit ();

  TestPointTempMemoryFunction (StartOfRange, EndOfRange);
}
