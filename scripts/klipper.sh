#!/bin/bash

# Check if the Klipper service is running and save the result in
# "klipperstate"
klipperstate=$(systemctl is-active klipper >/dev/null 2>&1 && echo true ||
  echo false)

#init usefull informations
k_branch=""
k_fullbranch=""
k_remote_version=""
k_local_version=""
k_repo=""

#Load klipper repo informations
function get_klipper_vars() {
  k_branch=$(git -C ~/klipper rev-parse --abbrev-ref HEAD)
  k_fullbranch=$(git -C ~/klipper rev-parse --abbrev-ref \
    --symbolic-full-name @{u})
  k_remote_version=$(git -C ~/klipper fetch -q &&
    git -C ~/klipper describe "origin/$k_branch" --tags --always --long)
  k_local_version=$(git -C ~/klipper describe --tags --always --long --dirty)
  k_repo=$(git -C ~/klipper remote get-url origin)
}

# Check if Klipper venv exists
function find_klipper_venv() {
  local venv_dir="$HOME/klippy-env"
  if [ -d "$venv_dir" ]; then
    echo "$venv_dir/bin/python"
  else
    error_exit "Klipper virtual-env not found at $venv_dir"
  fi
}

# Define a function to start or stop the Klipper service
function klipperservice {
  # Check if the Klipper service is running and save the result in
  # "klipperrunning"
  klipperrunning=$(systemctl is-active klipper >/dev/null 2>&1 &&
    echo true || echo false)

  ! $klipperstate && return 0
  [[ "$1" = "start" ]] && str="ing" && $klipperrunning && return 0
  [[ "$1" = "stop" ]] && str="ping" && ! $klipperrunning && return 0
  klipperrunning=false
  echo -e "${RED}${1^}$str Klipper service${DEFAULT}"
  sudo service klipper $1
  return 0
}

function update_klipper() {

  if [[ $k_local_version == $k_remote_version ]]; then
    echo -e "Klipper is up to date : ${GREEN}$k_local_version"
    echo "$k_repo $k_fullbranch${DEFAULT}"
  else
    if [[ "$k_local_version" == *"dirty"* ]]; then
      echo -e "${RED}Klipper repo is dirty, try to solve this before " \
        "update${DEFAULT}"
      echo "Conflict(s) to solve : "
      git -C ~/klipper status --short
      TOUPDATE=false
    else
      echo "Current Klipper version $k_local_version"
      echo "Next Klipper version $k_remote_version"
      echo "$(git -C ~/klipper shortlog HEAD..origin/master |
        grep -E '^[ ]+\w+' |
        wc -l) commit(s)  behind repo"
      if ! $CHECK; then
        echo "Updating Klipper from $k_repo $k_fullbranch"
        # Store previous version
        store_rollback_version

        git_output=$(git -C ~/klipper pull --ff-only) # Capture stdout
        k_local_version=$k_remote_version
      else
        echo -e "Klipper can be updated\n ${BLUE}$k_repo " \
          "$k_fullbranch${DEFAULT}"
      fi
    fi
  fi
}
