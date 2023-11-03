#!/bin/bash

usage() {
  cat << EOF
Usage: $0 [<config_file>] [-h]

Klipper Firmware Updater script. Update Klipper repo and mcu firmwares

Optional args: <config_file> Specify the config file to use. Default is 'mcus.ini'
  -f, --firmware             Do not merge repo, update firmware only
  -q, --quiet                Quiet mode, proceed all if needed tasks, !SKIP MENUCONFIG! 
  -h, --help                 Display this help message and exit
EOF
}

# Define an associative arrays "flash_actions", "make_options" to hold flash commands for different MCUs
declare -A preflash_actions
declare -A flash_actions
declare -A make_options
# Define an indexed array "mcu_order" to store the order of MCUs in mcus.ini
mcu_order=()

script_path=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Define a function to initialize the flash_actions array from the config file
function init_array(){

  filename=${CONFIG:-$script_path/mcus.ini}
  if [[ -f "$filename" ]]; then

    while IFS==: read -r key value; do
      if [[ $key == \[*] ]]; then
        section=${key#[}
        section=${section%]}
        # Store the order of MCUs in mcu_order array
        mcu_order+=("$section")
      elif [[ $key == flash_command ]]; then
        if [ -n "${flash_actions[$section]}" ]; then
            flash_actions[$section]="${flash_actions[$section]};$value"
        else
            flash_actions[$section]="$value"
        fi
      elif [[ $key == make_options ]]; then
        make_options[$section]="$value"
      elif [[ $key == preflash_command ]]; then
        if [ -n "${preflash_actions[$section]}" ]; then
	    preflash_actions[$section]="${preflash_actions[$section]};$value"
	else
	    preflash_actions[$section]="$value"
	fi
      fi
    done < $filename
    if [ ${#flash_actions[@]} == 0 ]; then
	echo "No mcu in $filename"
	exit 1
    fi
    return 0
  fi
  echo  "$filename does not exist, unable to update"
  exit 1
}

# Define a function to prompt the user with a yes/no question and return their answer
prompt () {
    if $QUIET ; then return 0 ; fi
    while true; do
        read -p $'\e[35m'"$* [Y/n]: "$'\e[0m' yn
        case $yn in
            [Yy]*) return 0  ;;
            "")    return 0  ;;  # Return 0 on Enter key press (Y as default)
            [Nn]*) return 1  ;;
        esac
    done
}

# Define a function to update the firmware on the MCUs
update_mcus () {
    # Loop over the keys (MCUs) in the flash_actions array
    for mcu in "${mcu_order[@]}"
    do
        # Prompt the user whether to update this MCU
        if prompt "Update $mcu ?" ; then
            :
        else
            continue
        fi
        # Check if the config folder exists
        if [ ! -d "$script_path/config" ]; then
            # If it doesn't exist, create it
            mkdir -p "$script_path/config"
            echo "Config folder created at: $script_path/config"
        fi
        
        # Set config_file in the scripts directory 
        config_file_str="KCONFIG_CONFIG=$script_path/config/config.$mcu"
        
        # Clean the previous build and configure for the selected MCU
        make clean $config_file_str
        if $QUIET ; then   
            if [ ! -f "$script_path/config/config.$mcu" ]; then
                echo -e "\e[1;31m ${1^} No config file for $mcu, \nDon't use quiet mode first !\nFimware update \e[0m"
                exit 0
            fi  
        else 
            make menuconfig $config_file_str 
        fi

        # Check CPU thread number (added by @roguyt to build faster)
        CPUS=`grep -c ^processor /proc/cpuinfo`
	if $QUIET ; then
	    make -j $CPUS $config_file_str &> /dev/null
	else
	    make -j $CPUS $config_file_str
	fi

        if prompt "No errors? Press [Y] to flash $mcu" ; then
	    # Split the preflash command string into separate commands and run each one
            IFS=";" read -ra commands <<< "${preflash_actions[$mcu]}"
            for command in "${commands[@]}"; do
                echo "Command: $command"
                eval "$command"
            done

            # Split the flash command string into separate commands and run each one
            IFS=";" read -ra commands <<< "${flash_actions[$mcu]}"
            for command in "${commands[@]}"; do
                 # Check if the command contains "make flash"
                if [[ "$command" == *"make flash"* ]]; then
                    # Add KCONFIG_CONFIG=config/$mcu after "make flash"
                    command="${command/make\ flash/make\ flash\ $config_file_str}"
                fi
                echo "Command: $command"
                eval "$command"
            done
        fi
    done
    # Prompt the user to power cycle the MCUs if necessary
    echo -e "\e[1;34m! Some MCUs need power cycle to apply firmware. !\e[0m"
}

# Define a function to start or stop the Klipper service
function klipperservice {
    if [[ "$klipperrunning" = "active" ]] || [[ "$1" = "start" ]] ; then
 	if [[ "$klipperrunning" = "inactive" ]]; then
	  if prompt "Start Klipper service ?" ; then
            :
	  else
	    return 0
          fi
	fi 
	echo -e "\e[1;31m ${1^} Klipper service\e[0m"
        sudo service klipper $1
    fi
}

# Check if the Klipper service is running and save the result in "klipperrunning"
klipperrunning=$(systemctl is-active klipper)

# Define the main function
function main(){
    echo -e "\e[1;35m----------------------------"
    echo "|  Update Klipper & Mcus   |"
    echo -e "----------------------------\e[0m"

    init_array

    # Change to the Klipper directory
    cd ~/klipper

    # Check for updates from the Git repository and prompt the user whether to update the MCUs
    if $FIRMWAREONLY ; then : ; else 
      echo -e "\e[1;34m Check for Klipper updates\e[0m" 
      git_output=$(git pull --ff-only) # Capture stdout
      if [[ $git_output == *"Already up to date"* ]]; then
          echo  "Klipper is already up to date"
	  echo  "Use this script with --firmware option to update MCUs anyway"
      else
	TOUPDATE=true
      fi
    fi
    if $TOUPDATE ; then
        if prompt "Do you want to update mcus now?"; then
          klipperservice stop # stop the Klipper service
          update_mcus # call the update_mcus function
          klipperservice start # start the Klipper service
        fi
    fi
    echo -e "\e[1;32mAll operations done ! Bye ! \e[0m"
    echo -e "\e[1;32mHappy bed engraving !\n\e[0m"
}

HELP=false; FIRMWAREONLY=false; QUIET=false; TOUPDATE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--firmware)  FIRMWAREONLY=true; TOUPDATE=true ;;
    -h|--help)     HELP=true  ;;
    -q|--quiet)    QUIET=true ;;
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

main
