#!/bin/bash

function moonraker_query() {
  local key=$2
  local object=$(echo "$1" | sed 's/ /%20/g')
  moonraker_object=http://127.0.0.1:7125/
  eval "$key=\$( curl -s \"$moonraker_object$object\" )"
  [[ ! $(echo ${!key} | grep -o '"result":') == '"result":' ]] && return 1
  return 0
}

function parse_json() {
  local value=$(echo "$json" | grep -o "\"$1\":[ ]*\"[^\"]*" | cut -d'"' -f4)
  # Use eval to assign the value to the variable name passed as $3
  [[ -z "$value" ]] && return 1
  eval "$2=\"$value\""
  return 0
}

function list_mcus() {
  local -n result=$1 # Use nameref for indirect reference
  local pattern=$( IFS='|'; echo "${klipper_section[*]}" ) # build pattern
  IFS=';'
  # Use mapfile to read the output of grep and sed directly into an array
  mapfile -t result < <(echo "$json" | grep -oP '"(mcu|'$pattern')"' | sed 's/"//g')

  [[ ${#result[@]} -eq 0 ]] && return 1
  return 0
}

function get_mcus_version() {
  # Check if printer info is available
  if ! moonraker_query printer/info json; then
    echo -e "${RED}Failed to query Moonraker. Unable to collect Klipper " \
    "infos on mcus${DEFAULT}"
    return 0
  fi

  parse_json state printer_state
  # Abort if printer is startup or error
  if [[ $printer_state =~ ^(startup)$ ]]; then
    echo -e "${RED}Klippy state: ${printer_state}.${DEFAULT} Unable to " \
    "collect mcus firmware version"
    return 0
  fi

  # Check printer state
  if ! moonraker_query printer/objects/query?print_stats json; then
    echo -e "${RED}Klippy state: ${printer_state}.${DEFAULT} Unable to " \
    "collect mcus firmware version"
    return 0
  fi  
  parse_json state klipper_state
  if [[ $klipper_state =~ ^(printing|paused)$ ]]; then
    error_exit "Printer is not ready (${klipper_state}) ! YOU MUST NOT " \
    "UPDATE MCUS PRINTING !"
    return 0
  fi

  # Get MCU list and versions
  moonraker_query printer/objects/list json
  if ! list_mcus mcus; then
    echo -e "${RED}Klippy state: ${printer_state}.${DEFAULT} Unable " \
                "to list mcus"
    return 0
  fi

  for mcu in "${mcus[@]}"; do
    moonraker_query "printer/objects/query?$mcu" json
    if ! parse_json mcu_version tmp; then
      echo -e "${RED}Klippy state: ${printer_state}.${DEFAULT} Unable to " \
      "collect ${mcu} firmware version"
      return 0
    fi

    for cmcu in "${mcu_order[@]}"; do
      if [[ $mcu == ${klipper_section["$cmcu"]} ]]; then
        mcu_version["$cmcu"]=$tmp
      fi
    done
  done

  return 0
}
