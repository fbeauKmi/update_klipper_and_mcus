#!/bin/bash

# Define an associative arrays "flash_actions", "klipper_section", "mcu_version", "config_name"
declare -A flash_actions
declare -A klipper_section
declare -A mcu_version
declare -A config_name
declare -A is_klipper_fw
# Define an indexed array "mcu_order" to store the order of MCUs in mcus.ini
mcu_order=()

# Define a function to initialize the flash_actions array from the config file
function load_mcus_config() {
  filename=${CONFIG:-$ukam_config/mcus.ini}
  if [[ -f "$filename" ]]; then
    file_content=$(tr '\r' '\n' <"$filename")

    while IFS==: read -r key value; do
      key=$(xargs <<<"$key")
      value=$(xargs <<<"$value")
      case "$key" in
      \[*\])
        section=${key#[}
        section=${section%]}

        # Check if section already exists
        for existing_section in "${mcu_order[@]}"; do
          [[ "$existing_section" == "$section" ]] &&
            error_exit "Duplicate section [$section] found in $filename"
        done

        # Store the order of MCUs in mcu_order array
        mcu_order+=("$section")
        # Set default values
        klipper_section["$section"]=$section
        config_name["$section"]=$section
        mcu_version["$section"]=unknown
        is_klipper_fw["$section"]=true
        ;;
      flash_command | quiet_command | action_command)
        # Make command quiet, except for stderr, when needed
        if [[ $key == quiet_command ]] || $QUIET; then
          value="$value >/dev/null"
        fi

        # append command to string
        if [ -n "${flash_actions["$section"]}" ]; then
          flash_actions["$section"]="${flash_actions["$section"]};$value"
        else
          flash_actions["$section"]="$value"
        fi
        ;;
      klipper_section)
        klipper_section["$section"]=$value
        is_klipper_fw["$section"]=false
        [[ "$value" =~ ^mcu\s* ]] && is_klipper_fw["$section"]=true
        ;;
      config_name)
        config_name["$section"]=$value
        ;;
      is_klipper_fw)
        case ${value,,} in
        true) value=true ;;
        false) value=false ;;
        *) error_exit "is_klipper_fw must be true|false" ;;
        esac
        is_klipper_fw["$section"]=$value
        ;;
      *)
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        error_exit "'$key' is not a valid key"
        ;;
      esac
    done <<<"$file_content"

    if [ ${#flash_actions[@]} == 0 ]; then
      error_exit "No mcu in $filename, check documentation"
    fi

    for mcu in "${mcu_order[@]}"; do
      if [[ -z "${flash_actions[$mcu]}" ]]; then
        error_exit "No action found for $mcu, check documentation"
      fi
    done

    return 0
  fi
  error_exit "$filename does not exist, unable to update"
}

# show config datas
function show_config() {
  if $VERBOSE; then
      echo -e "\n${BLUE}------- mcu datas -------${DEFAULT}"
      for mcu in "${mcu_order[@]}"; do
        echo -e "${RED}[$mcu]${DEFAULT}" \
          "\n ${GREEN}config_name:${DEFAULT} ${config_name[$mcu]}" \
          "\n ${GREEN}klipper_section:${DEFAULT} ${klipper_section[$mcu]}" \
          "\n ${GREEN}mcu_version:${DEFAULT} ${mcu_version[$mcu]}" \
          "\n ${GREEN}is_klipper_fw:${DEFAULT} ${is_klipper_fw[$mcu]}" \
          "\n ${GREEN}commands:${DEFAULT} ${flash_actions[$mcu]}\n"  
      done
      echo -e "${BLUE}------------------------------${DEFAULT}"
    fi
}

# Define a function to update the firmware on the MCUs
function update_mcus() {
  # Loop over the keys (MCUs) in the flash_actions array
  for mcu in "${mcu_order[@]}"; do
    # Initiate variables for current mcu
    SHOW_MENUCFG=$MENUCONFIG
    SHARED_CONFIG=false
    BUILD_FIRMWARE=${is_klipper_fw["$mcu"]}
    version="${mcu_version["$mcu"]}"
    def=y

    [ -n $version ] && mcu_str="$mcu [${klipper_section["$mcu"]}]" \
      || mcu_str="$mcu"

    if $BUILD_FIRMWARE; then
      # Check version
      if [[ "$version" == "$k_local_version" ]]; then
        echo "${WHITE}$mcu_str${MAGENTA} version is ${GREEN}$k_local_version"
        ! $FIRMWAREONLY && echo -e "${RED}Skip flash process!${DEFAULT}" \
          && continue
        def=n
      elif [ -n $version ]; then
        echo -e "$mcu_str version is ${GREEN}${version}" \
          "${DEFAULT} => ${GREEN}$k_local_version${DEFAULT}."
        [ "$version" \> $k_local_version ] && def=n \
          && echo -e "${RED}You gonna flash an older firmware !${DEFAULT}"
      fi
      
      # Set config_file in the scripts directory
      target=$(echo ${config_name["$mcu"]} | tr ' ' '_')
      [ "${config_name["$mcu"]}" != "$mcu" ] && SHARED_CONFIG=true
      config_path="$ukam_config/config/config.$target"
      config_file_str="KCONFIG_CONFIG=$config_path"
      # showmenu
      if [[ ! -f $config_path ]]; then
        $QUIET && error_exit "${1^} No config file for $mcu_str in " \
          "$ukam_config/config \nDon't use quiet mode on first " \
          "firmware update!"
        SHOW_MENUCFG=true
      fi
    else
      [ -n $version ] && echo -e "$mcu_str version is ${GREEN}${version}" \
      "${DEFAULT}"
    fi

    # Prompt the user whether to update this MCU
    if ! prompt "Update firmware of ${WHITE}$mcu_str${MAGENTA} ?" $def; then
      continue
    fi
    # Stop klipper before build firmware
    klipperservice stop

    # build firmware for Klipper
    if $BUILD_FIRMWARE; then
      # Change to the Klipper directory
      cd ~/klipper
      # Clean the previous build and configure for the selected MCU
      make clean $config_file_str
      # Open menuconfig if needed
      $SHOW_MENUCFG && make menuconfig $config_file_str

      # Check if forged ID is present in config file for shared config
      if $SHARED_CONFIG; then
        while grep -q -E "# CONFIG_USB_SERIAL_NUMBER_CHIPID|\
# CONFIG_CAN_UUID_USE_CHIPID" $config_path; do
          echo -e "${RED}Forged Serial/CanBus ID is incompatible with " \
            "config_name option.${DEFAULT}"
          if prompt "Change menuconfig now ?"; then
            make menuconfig $config_file_str
          else
            error_exit "Serial ID must not be forged with config_name option"
          fi
        done
      fi

      # Check CPU thread number (added by @roguyt to build faster)
      CPUS=$(grep -c ^processor /proc/cpuinfo)
      if $QUIET; then
        make -j $CPUS $config_file_str &>/dev/null
      else
        make -j $CPUS $config_file_str
      fi
    fi

    if ! $SHOW_MENUCFG || prompt "Errors? Press [Y] to flash $mcu_str"; then
      # Split the flash command string into separate commands and run each one
      IFS=";" read -ra commands <<<"${flash_actions["$mcu"]}"
      for command in "${commands[@]}"; do
        # Check if the command contains "make flash"
        if [[ "$command" == *"make flash"* ]]; then
          # Add KCONFIG_CONFIG=config/$mcu after "make flash"
          command="${command/make\ flash/make\ flash\ $config_file_str}"
        fi
        [[ ! "$command" =~ ">/dev/null" ]] && ! $QUIET &&
          echo "Command: $command"
        eval "$command"
      done
    fi
  done
  return 0
}
