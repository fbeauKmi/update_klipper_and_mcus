#!/bin/bash

usage() {
  cat <<EOF
Usage: $0 [<mcus.ini>] [-h]

UKAM: a Klipper Firmware Updater script. Update Klipper repo and mcu firmwares

Optional args: <config_file> Specify the config file to use. Default 'mcus.ini'
  -c, --checkonly   Check if Klipper is up to date only.
  -f, --firmware    Do not merge repo, update firmware only
  -m, --menuconfig  Show menuconfig for all Mcus (default is tonot show)
  -r, --rollback    Rollback to a previous version
  -q, --quiet       Quiet mode, proceed all if needed tasks, !SKIP MENUCONFIG! 
  -v, --verbose     For debug purpose, display parsed config
  -h, --help        Display this help message and exit
EOF
}

# Colors helpers
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[1;34m'
MAGENTA=$'\033[0;35m'
LIGHT_MAGENTA=$'\033[1;35m'
CYAN=$'\033[0;36m'
WHITE=$'\033[0;37m'
DEFAULT=$'\033[0m'

# Define a function to prompt the user with a y/n question
prompt() {
  local default="Yn"
  [ $# -eq 2 ] && [ ${2^} = "N" ] && default="yN"

  if $QUIET; then return 0; fi
  while true; do
    read -p "${MAGENTA}$1 [$default]: ${DEFAULT}" yn
    case $yn in
    [Yy]*) return 0 ;;
    "")
      [ $default = "yN" ] && return 1 # Return 1 if N, 0 if Y is default
      return 0
      ;; # Return 0 on Enter key press (Y as default)
    [Nn]*) return 1 ;;
    esac
  done
}

# Error function Exit script
function error_exit() {
  echo -e "${RED}!!Error: $*${DEFAULT}" >&2
  exit 1
}

# Function to enter bootloader mode
# Usage  : enter_bootloader -t [type:usb|serial|can] -d [serial]
#                           -u [canbus_uuid] -b [baudrate]
function enter_bootloader() {
  local type=""
  local serial=""
  local baudrate=""

  # Parse command-line options
  while getopts ":t:d:b:u:" opt; do
    case $opt in
    u)
      type='can'
      serial="$OPTARG"
      ;;
    t) type=$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]') ;;
    d) serial="$OPTARG" ;;
    b) baudrate="$OPTARG" ;;
    \?) error_exit "Invalid option -$OPTARG. Usage: enter_bootloader -t " \
      "<usb|serial|can> -d <serial> [-b baudrate] | -u <canbus_uuid>" ;;
    :) error_exit "Option -$OPTARG requires an argument. Usage: " \
      "enter_bootloader -t <usb|serial> -d <serial> [-b baudrate] | " \
      "-u <canbus_uuid>" ;;
    esac
  done

  # Check if required arguments are provided
  if [[ -z "$type" ]]; then
    error_exit "Type argument is missing. Usage: enter_bootloader " \
      "-t <usb|serial> -d <serial> [-b baudrate]"
  fi

  if [[ -z "$serial" ]]; then
    error_exit "Serial argument is missing. Usage: enter_bootloader " \
      "-t <usb|serial> -d <serial> [-b baudrate] | -u <canbus_uuid>"
  fi

  venv=$(find_klipper_venv)

  case "$type" in
  usb)
    cd ~/klipper/scripts
    $venv -c "import flash_usb as u; u.enter_bootloader('$serial')"
    sleep 2
    ;;
  serial)
    echo "Entering serial bootloader mode for $serial"
    baudrate=${baudrate:-250000}
    $venv -c "
import sys, serial
try:
    with serial.Serial('$serial', int($baudrate), timeout=1) as ser:
        ser.write(b'~ \x1c Request Serial Bootloader!! ~')
except serial.SerialException as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
    sleep 2
    ;;
  can)
    echo "Entering CAN bootloader mode for $serial"
    if [[ -f ~/katapult/scripts/flashtool.py ]]; then
      ~/katapult/scripts/flashtool.py -r -u $serial
      sleep 2
    else
      error_exit "flashtool.py not found"
    fi
    ;;
  *)
    error_exit "Unknown bootloader type: $type"
    ;;
  esac
}

function link_config {
  if [ ! -d $ukam_config ]; then
    mkdir $ukam_config
    echo -e "\n${DEFAULT}New config folder ${ukam_config}"
    ln -s $ukam_path/config $ukam_config/config
    if [ -e $ukam_path/mcus.ini ]; then
      echo -e "${DEFAULT}Moving mcus.ini to ${ukam_config}\n"
      mv $ukam_path/mcus.ini $ukam_config
    else
      echo -e "${DEFAULT}Copying  sample mcus.ini to ${ukam_config}\n"
      cp $ukam_path/examples/mcus.ini $ukam_config
    fi
  fi
}
