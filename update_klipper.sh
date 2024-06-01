#!/bin/bash

usage() {
  cat << EOF
Usage: $0 [<mcus.ini>] [-h]

Klipper Firmware Updater script. Update Klipper repo and mcu firmwares

Optional args: <config_file> Specify the config file to use. Default is 'mcus.ini'
  -c, --checkonly            Check if Klipper is up to date only.
  -f, --firmware             Do not merge repo, update firmware only
  -r, --rollback             Rollback to previous installed version
  -q, --quiet                Quiet mode, proceed all if needed tasks, !SKIP MENUCONFIG! 
  -v, --verbose              For debug purpose, display parsed config
  -h, --help                 Display this help message and exit
EOF
}

# Define an associative arrays "flash_actions", "make_options" to hold flash commands for different MCUs
declare -A flash_actions
# Define an indexed array "mcu_order" to store the order of MCUs in mcus.ini
mcu_order=()

# Get Current script fullpath
script_path=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
k_branch=$(git -C ~/klipper rev-parse --abbrev-ref HEAD)
k_fullbranch=$(git -C ~/klipper rev-parse --abbrev-ref --symbolic-full-name @{u})
k_remote_version=$( git -C ~/klipper fetch -q && git -C ~/klipper describe "origin/$k_branch" --tags --always --long)
k_local_version=$( git -C ~/klipper describe --tags --always --long --dirty)
k_repo=$(git -C ~/klipper remote get-url origin)
# Check if the Klipper service is running and save the result in "klipperrunning"
klipperrunning=$(systemctl is-active klipper >/dev/null 2>&1 && echo true || echo false)

# Define a function to initialize the flash_actions array from the config file
function init_array(){

  filename=${CONFIG:-$script_path/mcus.ini}
  if [[ -f "$filename" ]]; then
    file_content=$( tr '\r' '\n' < "$filename" )

    while IFS==: read -r key value; do
      if [[ $key == \[*] ]]; then
        section=${key#[}
        section=${section%]}
        
        # Store the order of MCUs in mcu_order array
        mcu_order+=("$section")
      elif [[ $key == flash_command || $key == quiet_command || $key == action_command ]]; then
        
        # Warn deprecated config
        if [[ $key == flash_command ]]; then
          echo -e "\e[1;31m flash_command is DEPRECATED, will be removed soon, use action_command or quiet_command instead \e[0m"
        fi
        
        # Make command quiet, except for stderr, when needed
        if [[ $key == quiet_command ]] && $QUIET ; then
          value="$value >/dev/null"
        fi

        # append command to string
        if [ -n "${flash_actions["$section"]}" ]; then
            flash_actions["$section"]="${flash_actions["$section"]};$value"
        else
            flash_actions["$section"]="$value"
        fi
      fi
    done <<< "$file_content"

    if $VERBOSE; then
      echo "MCU order: ${mcu_order[@]}"
      for mcu in "${mcu_order[@]}"; do
        echo "$mcu: ${flash_actions[$mcu]}"
      done
    fi


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

# Display versions
show_version () {
  cd $script_path
  git fetch -q
  s_version=$(git describe --always --tags --long --dirty 2>/dev/null)
  s_remote=$(git describe "origin/$(git rev-parse --abbrev-ref HEAD)" --always --tags --long 2>/dev/null)
  if [[ $s_version != "" ]] ; then
    echo -e "updater $s_version"
  fi
  if [[ "$s_version" != "$s_remote"* ]] && ! $QUIET; then
    echo -e "new version available $s_remote"
  fi
  return 0
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
        
        # Change to the Klipper directory
        cd ~/klipper

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
            # Split the flash command string into separate commands and run each one
            IFS=";" read -ra commands <<< "${flash_actions["$mcu"]}"
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
    echo -e "\e[1;34m! Some MCUs may require a power cycle to apply firmware. !\e[0m"
    return 0
}

# Define a function to start or stop the Klipper service
function klipperservice {
    if ($klipperrunning) || [[ "$1" = "start" ]] ; then
      if ! $klipperrunning ; then
        if prompt "Start Klipper service ?" ; then
          :
        else
          return 0
        fi
      fi 
      echo -e "\e[1;31m ${1^} Klipper service\e[0m"
      sudo service klipper $1
    fi
    return 0
}

# Define the main function
function main(){
    echo -e "\e[1;35m----------------------------"
    echo "|  Update Klipper & Mcus   |"
    echo -e "----------------------------"
    show_version
    echo -e "\e[0m"

    init_array

    # Check for updates from the Git repository and prompt the user whether to update the MCUs
    if $FIRMWAREONLY ; then : ; else 
      if  $ROLLBACK ; then
	        k_previous_version=$(cat $script_path/config/.previous_version)
          if [[ $k_previous_version == $k_local_version ]]; then
		        echo "Nothing to rollback"
          else
            echo "Current version Klipper $k_local_version"
            if [[ "$k_local_version" == *"dirty"* ]]; then
               echo "WARNING : Rollback a dirty repo will erase untracked files" 
            fi
            if prompt "Rollback to $k_previous_version ?"; then
               git -C ~/klipper reset --hard $k_previous_version
               TOUPDATE=true
            fi
          fi
      else
 
      echo -e "\e[1;34m Check for Klipper updates\e[0m" 
      
      if [[ $k_local_version == $k_remote_version ]] ; then
          echo  "Klipper is already up to date"
          echo "$k_repo $k_fullbranch"
          echo "$k_local_version"  
          echo  "Use this script with --firmware option to update MCUs anyway"
      else
        if [[ "$k_local_version" == *"dirty"* ]]; then
          echo "Your repo is dirty, try to solve this before update"
          echo "Conflict to solve : "
          git -C ~/klipper status --short
        else
          
          echo "$k_local_version -> $k_remote_version"
          echo "$(git -C ~/klipper shortlog HEAD..origin/master| grep -E '^[ ]+\w+' | wc -l) commit(s)  behind repo"
          if ! $CHECK ; then
            echo  "Updating Klipper from $k_repo $k_fullbranch" 
            # Store previous version
            echo "$k_local_version" > $script_path/config/.previous_version           
            git_output=$(git -C ~/klipper pull --ff-only) # Capture stdout
            TOUPDATE=true
          else
            echo  "Klipper can be updated from $k_repo $k_fullbranch"
            TOUPDATE=false
          fi
        fi
      fi
      fi
    fi
    if $TOUPDATE ; then
      if prompt "Do you want to update mcus now?"; then
        klipperservice stop # stop the Klipper service
        update_mcus # call the update_mcus function
        klipperservice start # start the Klipper service
      fi
    fi
    if ! $CHECK; then
      echo -e "\e[1;32mAll operations done ! Bye ! \e[0m"
      echo -e "\e[1;32mHappy bed engraving !\n\e[0m"
    fi
    exit 0
}

HELP=false; CHECK=false; FIRMWAREONLY=false; QUIET=false; TOUPDATE=false; ROLLBACK=false; VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--checkonly)    CHECK=true;;
    -f|--firmware) FIRMWAREONLY=true; TOUPDATE=true ;;
    -r|--rollback)  ROLLBACK=true;;
    -h|--help)     HELP=true  ;;
    -q|--quiet)    QUIET=true ;;
    -v|--verbose)  VERBOSE=true ;;
    -*|--*)       HELP=true ;;
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
