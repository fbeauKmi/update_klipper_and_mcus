#!/usr/bin/env python3
#
# Tool to request the bootloader on MCU connected via UART port (not for usb-serial)
#
# This file may be distributed under the terms of the GNU GPLv3 license.

import sys, serial

ser = serial.Serial(sys.argv[1], int(sys.argv[2]), timeout=1)
# see https://www.klipper3d.org/Bootloader_Entry.html#physical-serial
ser.write(str.encode("~ \x1c Request Serial Bootloader!! ~"))
