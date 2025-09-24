#!/bin/bash

# UKAM is a bash script to simplify klipper firmware updates.
#
# Copyright (C) 2024-2025 fboc (Frédéric Beaucamp)
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.

# Exit on error
set -E
trap 'handle_error $LINENO' ERR
# Get Current script fullpath
ukam_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# Config_path
ukam_config="${HOME}/printer_data/config/ukam"

#Load functions
source "$ukam_path/scripts/utils.sh"
source "$ukam_path/scripts/mcus.sh"
source "$ukam_path/scripts/klipper.sh"
source "$ukam_path/scripts/rollback.sh"
source "$ukam_path/scripts/moonraker.sh"

# Display versions
ukam_version() {
  git -C $ukam_path fetch -q
  git -C $ukam_path fetch --tags --force -q
  s_version=$(git -C $ukam_path describe --always --tags --long --dirty \
    2>/dev/null)
  s_remote=$(git -C $ukam_path describe "origin/$(git -C $ukam_path rev-parse \
    --abbrev-ref HEAD)" --always --tags --long 2>/dev/null)
  [[ ! $s_version = "" ]] && echo -e "  current version $s_version"
  [[ ! $s_version = "$s_remote"* ]] && ! $QUIET &&
    echo -e "  new version available $s_remote"
  return 0
}

function splash() {
  echo -e "${LIGHT_MAGENTA}
  ++${CYAN}      __  ____ __ ___    __  ___  ${LIGHT_MAGENTA}++
  | ${GREEN}     / / / / //_//   |  /  |/  /  ${LIGHT_MAGENTA} |
  | ${BLUE}    / / / / ,<  / /| | / /|_/ /   ${LIGHT_MAGENTA} |
  | ${MAGENTA}   / /_/ / /| |/ ___ |/ /  / /    ${LIGHT_MAGENTA} |
  | ${RED}   \____/_/ |_/_/  |_/_/  /_/     ${LIGHT_MAGENTA} |          
  |  — Update — Klipper — & — Mcus ——  |
  ++${WHITE}       v0.0.9 Infinite Idle       ${LIGHT_MAGENTA}++
  "
  ukam_version
}

# Define the main function
function main() {
  link_config
  get_klipper_vars
  load_mcus_config
  get_mcus_version
  show_config

  # Check for updates from the Git repo and prompt the user to update the MCUs
  if ! $FIRMWAREONLY; then
    :
    if $ROLLBACK; then
      echo -e "\n${BLUE}-- Rollback ${APP} updates --${DEFAULT}"
      show_rollback
      do_rollback
    else
      echo -e "\n${BLUE}-- Check and apply ${APP} updates --${DEFAULT}"
      update_klipper
    fi
  fi

  if $TOUPDATE; then
    echo -e "\n${BLUE}-- Update Mcus --${DEFAULT}"
    update_mcus          # call the update_mcus function
    klipperservice start # start the Klipper service
  fi

  if $ERROR; then
    echo -e "\n    ${RED}Unfortunately something went wrong ! :("
    echo -e "       Sorry, no bed engraving today.\n${DEFAULT}"

    exit 1
  fi

  echo -e "\n    ${GREEN}All operations done ! Bye !"
  echo -e "      Happy bed engraving ! ;)\n${DEFAULT}"

  exit 0
}

CHECK=false
FIRMWAREONLY=false
HELP=false
MENUCONFIG=false
QUIET=false
ROLLBACK=false
TOUPDATE=true
VERBOSE=false
git_option="--ff-only"
APP=unknown

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  -c | --checkonly)
    CHECK=true
    TOUPDATE=false
    ;;
  -b | --rebase) git_option="--rebase";;
  -f | --firmware) FIRMWAREONLY=true ;;
  -h | --help) HELP=true ;;
  -m | --menuconfig) MENUCONFIG=true ;;
  -q | --quiet) QUIET=true ;;
  -r | --rollback) ROLLBACK=true ;;
  -v | --verbose) VERBOSE=true ;;
  -* | --*) HELP=true ;;
  *)
    CONFIG=$1
    ;;
  esac
  shift
done

# Call usage function if --help or -h is specified
[[ $HELP == true ]] && usage && exit 0

splash
main
