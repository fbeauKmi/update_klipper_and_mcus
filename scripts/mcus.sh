#!/bin/bash

# Define an associative arrays "flash_actions", "mcu_info"
declare -A flash_actions
declare -A mcu_info
declare -A mcu_version
# Define an indexed array "mcu_order" to store the order of MCUs in mcus.ini
mcu_order=()

# Define a function to initialize the flash_actions array from the config file
function load_mcus_config() {
  filename=${CONFIG:-$ukam_config/mcus.ini}
  if [[ -f "$filename" ]]; then
    file_content=$(tr '\r' '\n' <"$filename")

    while IFS==: read -r key value; do
      if [[ $key == \[*] ]]; then
        section=${key#[}
        section=${section%]}

        # Check if section already exists
        if [[ " ${mcu_order[@]} " =~ " ${section} " ]]; then
          error_exit "Duplicate section [$section] found in $filename"
        fi

        # Store the order of MCUs in mcu_order array
        mcu_order+=("$section")
      elif [[ $key == flash_command ||
        $key == quiet_command ||
        $key == action_command ]]; then

        # Make command quiet, except for stderr, when needed
        if [[ $key == quiet_command ]] && $QUIET; then
          value="$value >/dev/null"
        fi

        # append command to string
        if [ -n "${flash_actions["$section"]}" ]; then
          flash_actions["$section"]="${flash_actions["$section"]};$value"
        else
          flash_actions["$section"]="$value"
        fi
      elif [[ $key == klipper_section ]]; then
        mcu_info["$section"]=$(echo $value)
      fi
    done <<<"$file_content"

    for mcu in "${mcu_order[@]}"; do
      if [ ! -n "${mcu_info["$mcu"]}" ]; then
        mcu_info["$mcu"]=$(echo $mcu)
      fi
    done

    if $VERBOSE; then
      echo "MCU order: ${mcu_order[@]}"
      for mcu in "${mcu_order[@]}"; do
        echo "$mcu: ${flash_actions[$mcu]}"
      done
    fi

    if [ ${#flash_actions[@]} == 0 ]; then
      error_exit "No mcu in $filename, check documentation"
    fi
    return 0
  fi
  error_exit "$filename does not exist, unable to update"
}

# Define a function to update the firmware on the MCUs
function update_mcus() {
  # Loop over the keys (MCUs) in the flash_actions array
  for mcu in "${mcu_order[@]}"; do
    def=y
    if [ -n "${mcu_version["$mcu"]}" ]; then
      mcu_str="$mcu [${mcu_info["$mcu"]}]"
      if [[ ${mcu_version["$mcu"]} == $k_local_version ]]; then
        if $FIRMWAREONLY; then
          echo "${WHITE}$mcu_str${MAGENTA} version is ${GREEN}$k_local_version"
          def=n
        else
          echo -e "$mcu_str version is ${GREEN}$k_local_version${DEFAULT}. " \
            "${RED}Skip flash process!${DEFAULT}"
          continue
        fi
      else
        echo -e "$mcu_str version is ${GREEN}${mcu_version["$mcu"]}" \
          "${DEFAULT} => ${GREEN}$k_local_version${DEFAULT}."
        if [ ${mcu_version["$mcu"]} \> $k_local_version ]; then
          def=n
          echo -e "${RED}You gonna flash an older firmware !${DEFAULT}"
        fi
      fi
    else
      mcu_str="$mcu"
    fi
    # Prompt the user whether to update this MCU
    if ! prompt "Update firmware of ${WHITE}$mcu_str${MAGENTA} ?" $def; then
      continue
    fi
    klipperservice stop
    # Check if the config folder exists
    if [ ! -d "$ukam_config/config" ]; then
      # If it doesn't exist, create it
      mkdir -p "$ukam_config/config"
      echo "Config folder created at: $ukam_config/config"
    fi

    # Initiate menuconfig check for current mcu
    TMP_MENUCONFIG=$MENUCONFIG
    # Set config_file in the scripts directory
    target=$(echo $mcu | tr ' ' '_')
    config_path="$ukam_config/config/config.$target"
    config_file_str="KCONFIG_CONFIG=$config_path"
    if [[ ! -f "$config_path" ]]; then
      $QUIET && error_exit "${1^} No config file for $mcu_str in " \
        "$ukam_config/config \nDon't use quiet mode on first " \
        "firmware update!"
      TEMP_MENUCONFIG=true
    fi

    # Change to the Klipper directory
    cd ~/klipper

    # Clean the previous build and configure for the selected MCU
    make clean $config_file_str
    # Open menuconfig if needed
    if $TMP_MENUCONFIG; then
      make menuconfig $config_file_str
    fi

    # Check CPU thread number (added by @roguyt to build faster)
    CPUS=$(grep -c ^processor /proc/cpuinfo)
    if $QUIET; then
      make -j $CPUS $config_file_str &>/dev/null
    else
      make -j $CPUS $config_file_str
    fi

    FLASHMCU=true
    $TMP_MENUCONFIG && ! prompt "Errors? Press [Y] to flash $mcu_str" &&
      FLASHMCU=false

    if $FLASHMCU; then
      # Split the flash command string into separate commands and run each one
      IFS=";" read -ra commands <<<"${flash_actions["$mcu"]}"
      for command in "${commands[@]}"; do
        # Check if the command contains "make flash"
        if [[ "$command" == *"make flash"* ]]; then
          # Add KCONFIG_CONFIG=config/$mcu after "make flash"
          command="${command/make\ flash/make\ flash\ $config_file_str}"
        fi
        if [[ "$command" =~ [[:space:]]*enter_bootloader ]]; then
          # Execute enter_bootloader directly
          $command
        else
          echo "Command: $command"
          eval "$command"
        fi
      done
    fi
  done
  return 0
}
