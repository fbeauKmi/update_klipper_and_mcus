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
  if get_venv; then
    echo KLIPPER_VENV
    return 0
  fi

  local venv_dir="$HOME/klippy-env"
  if [ -d "$venv_dir" ]; then
    echo "$venv_dir/bin/python"
  else
    error_exit "virtual-env not found at $venv_dir"
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
  if $ERROR && ! prompt "${RED}An error occured !
Do you want to restart ${APP} anyway ?" n; then
   return 0
  fi
  echo -e "${YELLOW}${1^}$str Klipper service${DEFAULT}"
  sudo service klipper $1
  return 0
}

function update_klipper() {

  if [[ $k_local_version == $k_remote_version ]]; then
    echo -e "${APP} is up to date : ${GREEN}$k_local_version"
    echo "$k_repo $k_fullbranch${DEFAULT}"
  else
    if [[ "$k_local_version" == *"dirty"* ]]; then
      echo -e "${RED}${APP} repo is dirty, try to solve this before " \
        "update${DEFAULT}"
      echo "Conflict(s) to solve : "
      git -C ~/klipper status --short
      if ! prompt "Do you want to flash firmware on boards anyway ?" n; then
        TOUPDATE=false
        ERROR=true
      fi
    else
      echo "Current ${APP} version $k_local_version"
      echo "Next ${APP} version $k_remote_version"
      nb_commit=$(git rev-list HEAD..@{u} --count)
      echo "${nb_commit} commit(s) behind repo" 
      if ! $CHECK; then
        echo "Updating ${APP} from $k_repo $k_fullbranch"
        # Store previous version
        store_rollback_version

        git_output=$(git -C ~/klipper pull $git_option 2>&1) # Capture stdout
        exit_status=$?

        if [ $exit_status -ne 0 ] || echo "$git_output" | grep -q "error"; then
          echo -e "${RED}Git pull failed:${DEFAULT} $git_output"
          [ $nb_commit -eq "0" ] && [[ "$git_option" != "--rebase" ]] && 
            prompt "Do you want to rebase to update ${APP} ?" y &&
            git_output=$(git -C ~/klipper pull --rebase 2>&1)
          exit_status=$?
          ERROR=false
        fi
        [ $exit_status -eq 0 ] && k_local_version=$k_remote_version
      else
        echo -e "${APP} can be updated\n ${BLUE}$k_repo " \
          "$k_fullbranch${DEFAULT}"
      fi
    fi
  fi
}
