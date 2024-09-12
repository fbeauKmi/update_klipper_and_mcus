![UKAM_Banner](./images/banner.png)
# **UKAM : Update Klipper And Mcus** all-at-once.

This is small bash script to update klipper and mcus (main, rpi, can, pico, ... ) and **keep trace of config file for the next update !**

## Table of Contents 
- [Disclaimer](#disclaimer)<!-- omit in toc -->
- [What UKAM does ?](#what-ukam-does-)
- [Installation](#installation)
  - [Method 1 : Manual](#method-1-)
  - [Method 2 : git clone](#method-2-)
- [Update UKAM with Moonraker](#update-ukam-with-moonraker)
- [Usage](#usage)
- [Edit mcus.ini](#edit-mcusini)
  - [mcus.ini examples](#mcusini-examples-more-to-come-)
    - [RPi microcontroller](#rpi-microcontroller)
    - [Serial connection, UART](#serial-connection-uart)
    - [Mainboard , USB\_to\_CAN bridge mode (Katapult required)](#mainboard--usb_to_can-bridge-mode-katapult-required)
    - [RP2040 based board](#rp2040-based-board)
    - [Mainboard : USB connection](#mainboard--usb-connection)
    - [Toolhead : CANbus (Katapult required)](#toolhead--canbus-katapult-required)
- [TODO](#todo)
- [Aknowledgments](#aknowledgments)
  

## Disclaimer
> [!WARNING] 
> **This script does not replace your brain. If you don't know how to flash your boards, just go away !**
>
> I admit that this warning is a little condescending. You can find many guides explaining how to flash your boards, I can't list them all. See below some links i used as reference to build the script.
>
> - Klipper Documentation
>   - [Building and flashing the micro-controller](https://www.klipper3d.org/Installation.html#building-and-flashing-the-micro-controller),
>   - [Building and installing Linux host micro-controller code](https://www.klipper3d.org/Beaglebone.html#building-and-installing-linux-host-micro-controller-code),
>   - [SDCard update](https://www.klipper3d.org/SDCard_Updates.html),
>   - [Bootloader entry](https://www.klipper3d.org/Bootloader_Entry.html),
> - [maz0R Canbus guide](https://maz0r.github.io/klipper_canbus/),
> - Manufacturers documentations, 
>  - ...
## What UKAM does ?
Update Klipper and apply firmware update for each mcu. Basically it runs:
```
git pull
service klipper stop
make clean
make menuconfig
make
<the_flash_command>
service klipper start
```

## Installation

>[!IMPORTANT] 
>If you use a previous version of this script, copy the configuration files from ``~/klipper/`` to ``~/<script_folder>/config/``

### Method 1 :
Copy ``ukam.sh`` and ``mcus.ini`` in a folder of your pi, ``~/ukam/`` sounds as a good choice. Let's call this folder ``~/<script_folder>`` in this Readme.

Ensure to make ``ukam.sh`` executable : 
```
chmod +x ~/<script_folder>/update_klipper.sh
```

> [!NOTE]
> This method does not track update of the script 

### Method 2 : 
```
cd ~
git clone https://github.com/fbeauKmi/update_klipper_and_mcus.git ukam
```

Copy and edit ``mcus.ini`` from examples folder to ``~/ukam/``

## Update UKAM with Moonraker

Paste the lines below in moonraker.conf
```
[update_manager update_klipper_and_mcus]
type: git_repo
primary_branch: main
path: ~/ukam
origin: https://github.com/fbeauKmi/update_klipper_and_mcus.git
is_system_service: False
```
## Usage

Run ``~/<script_folder>/ukam.sh`` in a terminal, you can use the following options.

### -h --help : to see usage

```
Usage: ukam.sh [<config_file>] [-h]

UKAM, a Klipper Firmware Updater script. Update Klipper repo and mcu firmwares

Optional args: <config_file> Specify the config file to use. Default is 'mcus.ini'
  -c, --checkonly            Check if Klipper is up-to-date only.
  -f, --firmware             Do not merge repo, update firmware only
  -r, --rollback             Rollback to the previous version (this script only)
  -q, --quiet                Quiet mode, proceed all if needed tasks, !SKIP MENUCONFIG! 
  -h, --help                 Display this help message and exit
```
### -c --checkonly
Check if Klipper is up-to-date, if not, it displays latest commits.
### -f --firmware : to force MCUs update
Skip Klipper update to repo or force Mcus update if Klipper is already up to date 
### -r --rollback
Rollback to the previous version saved by this script. It proceed a hard reset if the repo is dirty, untracked files will be erased, plugins will need to be reinstalled 
### -q --quiet : QUIET mode is Dangereous !

Quiet mode allows you to update all you configure without any interaction. Just run the script and all is done. But ....
- To use it, you need to run th script in interactive mode at least the first time.
- while features are modified/added/removed from menuconfig by klipper update, the config file is not updated. It may yield to a build issue.

## Edit mcus.ini

``mcus.ini`` contains : 
- sections : the name you give to your mcu between brackets (not necessarly the name in Klipper config)
- ``action_command`` : command executed after the firmware build, whatever you need to prepare, flash or switch off/on the mcu. You can separate command by ``;`` or use several action_command in a section, they are executed in order of appearance.
- ``quiet_command`` : same as action_command but without stdout in QUIET mode 

The flash command depends on you mcus and the way you choose to flash your board : dfu-util, make flash, flashtool, flash_sdcard, mount/cp/umount ... refer to your board documentation to choose the right command

> [!NOTE] About bootloader entry
> Helpers makes easier to enter bootloader,(Thanks to @beavis) : `bootloader_serial.py`, `bootloader_usb.py` or newer `enter_bootloader` can be used
> ```
> Usage: enter_bootloader -t <usb|serial|can> -d <serial> [-b baudrate] | -u <canbus_uuid>
>    -t     type of actual firmware connection (serial|usb|can)
>    -d     serial id, only for serial and usb ( /dev/ttyAMA0, /dev/serial/by-id/...)
>    -b     baudrate for serial default is 250000
>    -u     canbus_uuid (if set -t become optional)   
> ```

### mcus.ini examples (more to come) : 
#### RPi microcontroller 
```
# For Rpi
[RaspberryPi]
action_command: make flash
```
_source : [Klipper doc](https://www.klipper3d.org/RPi_microcontroller.html#building-the-micro-controller-code)_

#### Serial connection, UART

```
# For a MCU in usart, using flash_sdcard
# The second arg of flash_sdcard.sh is the cpu reference.
# A list of available values can be found here :
# https://github.com/Klipper3d/klipper/blob/master/scripts/spi_flash/board_defs.py

[octopus_uart]
flash_command: ./scripts/flash-sdcard.sh /dev/ttyAMA0 btt-octopus-f446-v1
```
_source : [Klipper doc](https://www.klipper3d.org/SDCard_Updates.html)_

```
# For mainboard using bootloader_serial helper 
[spider]
# spider on serial port (rpi gpio)
action_command: ~/ukam/bootloader_serial.py /dev/ttyAMA0 250000
action_command: ~/katapult/scripts/flashtool.py -d /dev/ttyAMA0 -b 250000
```
_source : [Klipper doc](https://www.klipper3d.org/Bootloader_Entry.html#physical-serial)_

#### Mainboard , USB_to_CAN bridge mode (Katapult required)

```
# For a MCU in USB to Can bridge using Katapult as bootloader
# You have to insert your Canbus_uuid and Usb serial below
[octopus_usb2can]
quiet_command: python3 ~/katapult/scripts/flashtool.py -i can0 -r -u <YOUR_CANBUS_UUID>; sleep 2
action_command: python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_stm32f446xx_<BOARD_ID>-if00

# using enter_bootoader function
[octopus_usb2can]
quiet_command: enter_bootloader -u <YOUR_CANBUS_UUID>
action_command: python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_stm32f446xx_<BOARD_ID>-if00
```
_source : [Roguyt_prepare_command branch ^^](../roguyt_prepare_command/mcus.ini)_

#### RP2040 based board

```
# For Pico RP2040
[pico]
#  No boot loader, need to manually enter in boot mode
action_command : sudo mount /dev/sda1 /mnt ; sudo cp out/klipper.uf2 /mnt ; sudo umount /mnt

[pico_bootloader]
# With katapult as bootloader
action_command : make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_rp2040_<BOARD_ID>-if00

[pico_bootloader]
# With katapult as bootloader
quiet_command : enter_bootloader -t usb -d /dev/serial/by-id/usb-Klipper_rp2040_<BOARD_ID>-if00
action_command : ~/katapult/scripts/flashtools.py -d /dev/serial/by-id/usb-Klipper_rp2040_<BOARD_ID>-if00

```
_source: Cannot remember_

#### Mainboard : USB connection

```
[catalyst]
# catalyst on usb-serial port (using bootloader_usb.py)
action_command: ~/ukam/bootloader_usb.py /dev/serial/by-id/usb-Klipper_stm32f401xc_<board_serial>
quiet_command: sleep 1
action_command: ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/usb-katapult_stm32f401xc_<board_serial> -b 250000
```
_source : [Klipper doc](https://www.klipper3d.org/Bootloader_Entry.html#python-with-flash_usb)_

```
[catalyst]
# catalyst on usb-serial port (using make flash)
action_command: make flash FLASH_DEVICE=/dev/serial/by-id/usb-Klipper_stm32f401xc_<board_serial>
```
_source : [Klipper doc](https://www.klipper3d.org/RPi_microcontroller.html#building-the-micro-controller-code)_

#### Toolhead : CANbus (Katapult required)

```
[toolhead]
action_command: ~/katapult/scripts/flashtool.py -u <canbus_uuid>
```




## TODO
not to much, the script works. If you have any suggestions feel free to contact me on Voron discord @fboc
## Aknowledgments
Thanks to the Voron french community for supporting/tolerating me everyday ^^.
