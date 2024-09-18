#!/bin/bash

# update_klipper_and_mcus (UKAM) is a bash script to simplify klipper firmware updates.
#
# Copyright (C) 2024 Frédéric Beaucamp
#
# This program is free software: you can redistribute it and/or modify it under the terms 
# of the GNU General Public License as published by the Free Software Foundation, either 
# version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program.
# If not, see http://www.gnu.org/licenses/.

# Exit on error
set -e 
# Get Current script fullpath
script_path=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

#Load functions
source "$script_path/scripts/utils.sh"
source "$script_path/scripts/mcus.sh"
source "$script_path/scripts/klipper.sh"
source "$script_path/scripts/rollback.sh"
source "$script_path/scripts/moonraker.sh"

# Display versions
ukam_version () {
  git -C $script_path fetch -q
  s_version=$(git -C $script_path describe --always --tags --long --dirty 2>/dev/null)
  s_remote=$(git -C $script_path describe "origin/$(git rev-parse --abbrev-ref HEAD)" --always --tags --long 2>/dev/null)
  if [[ $s_version != "" ]] ; then
    echo -e "  current version $s_version"
  fi
  if [[ "$s_version" != "$s_remote"* ]] && ! $QUIET; then
    echo -e "  new version available $s_remote"
  fi
  return 0
}

function splash(){
    echo -e "${LIGHT_MAGENTA}"
    echo "   ++————————————————————————————————++ "
    echo "  ||    _   _ _   __  ___  ___  ___   ||"
    echo "  ||   | | | | | / / / _ \ |  \/  |   ||"
    echo "  ||   | | | | |/ / / /_\ \| .  . |   ||"
    echo "  ||   | | | |    \ |  _  || |\/| |   ||"
    echo "  ||   | |_| | |\  \| | | || |  | |   ||"
    echo "  ||    \___/\_| \_/\_| |_/\_|  |_/   ||"
    echo "  ||                                  ||"
    echo "  ++ — Update — Klipper — & — Mcus —— ++"
    echo "   ++————————————————————————————————++ "
    ukam_version
}

# Define the main function
function main(){
    
    get_klipper_vars
    load_mcus_config

    # Check for updates from the Git repository and prompt the user whether to update the MCUs
    if ! $FIRMWAREONLY ; then :
      if  $ROLLBACK ; then
        echo -e "\n${BLUE}-- Rollback Klipper updates --${DEFAULT}"
        show_rollback
        do_rollback
      else
        echo -e "\n${BLUE}-- Check and apply Klipper updates --${DEFAULT}" 
        update_klipper
      fi
    fi
    
    if $TOUPDATE ; then
      echo -e "\n${BLUE}-- Update Mcus --${DEFAULT}" 
      get_mcus_version
      update_mcus # call the update_mcus function
      klipperservice start # start the Klipper service
    fi
    echo -e "\n    ${GREEN}All operations done ! Bye !"
    echo -e "       Happy bed engraving !\n${DEFAULT}"
    
    exit 0
}

CHECK=false; DO_ROLLBACK=false; FIRMWAREONLY=false; HELP=false
MENUCONFIG=false; QUIET=false; ROLLBACK=false; TOUPDATE=true
VERBOSE=false


# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--checkonly)  CHECK=true; TOUPDATE=false ;;
    -f|--firmware)   FIRMWAREONLY=true ;;
    -h|--help)       HELP=true ;;
    -m|--menuconfig) MENUCONFIG=true ;;
    -q|--quiet)      QUIET=true ;;
    -r|--rollback)   ROLLBACK=true ;;
    -v|--verbose)    VERBOSE=true ;;
    -*|--*)          HELP=true ;;
    *)
      CONFIG=$1
     esac
  shift
done

# Call usage function if --help or -h is specified
if [[ $HELP == true ]]; then
  usage
  exit 0
fi

splash
main
