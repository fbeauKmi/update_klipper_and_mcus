#!/usr/bin/env python3
# 
# Tool to request the bootloader on MCU connected via usb-serial port
#
# see https://www.klipper3d.org/Bootloader_Entry.html#python-with-flash_usb
# 
# This file may be distributed under the terms of the GNU GPLv3 license.

import sys
# use klipper flash_usb module
from pathlib import Path
sys.path.append(str(Path.home()) + "/klipper/scripts") 
import flash_usb as u

u.enter_bootloader(sys.argv[1])
