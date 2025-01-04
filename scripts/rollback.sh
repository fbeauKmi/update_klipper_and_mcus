#!/bin/bash

rollback_repo=""
rollback_version=""
DO_ROLLBACK=false

#Define function to get previous install version
function get_rollback {
  count=0
  filename="$1"
  if [[ -f "$filename" ]]; then
    while IFS= read -r value || [[ -n "$value" ]]; do
      [ $count -eq 0 ] && rollback_version="$value"
      [ $count -eq 1 ] && rollback_repo="$value" && break
      count=$(($count + 1))
    done <"$filename"
  fi
  return 0
}

function show_rollback {

  get_rollback $ukam_config/config/.previous_version

  echo "Local version $k_local_version"
  if [[ $rollback_version != "" &&
    $rollback_version != $k_local_version ]]; then
    if [[ $rollback_repo == "" ||
      $rollback_repo == "$k_repo $k_fullbranch" ]]; then
      echo "Known rollback version $rollback_version"
      DO_ROLLBACK=true
    else
      echo "Version $rollback_version belongs to another repo/branch"
      echo -e "${GREEN}$rollback_repo${DEFAULT}"
    fi
  fi
  if ! $DO_ROLLBACK; then
    echo "No rollback available"
  fi
}

function do_rollback() {
  QUIET=false
  TOUPDATE=false
  if $DO_ROLLBACK; then
    if [[ "$k_local_version" == *"dirty"* ]]; then
      echo -e "${RED}WARNING : Rollback a dirty repo will erase " \
        "untracked files.${DEFAULT}"
    fi
    if ! prompt "Rollback to $rollback_version ?"; then
      DO_ROLLBACK=false
    fi
  fi
  while ! $DO_ROLLBACK; do
    nb_rollback=""
    while [[ ! "$nb_rollback" =~ ^[0-9]+$ ]]; do
      read -p "${MAGENTA}Number of commits to rollback or [A] to \
abort ? ${DEFAULT}" nb_rollback
      if [[ "${nb_rollback^^}" == "A" ]]; then
        echo "Rollback aborted"
        return 0
      fi
    done
    rollback_version=$(git -C ~/klipper describe HEAD~$nb_rollback \
      --tags --always --long)
    if prompt "Rollback to $rollback_version ?"; then
      DO_ROLLBACK=true
    fi
  done
  if $DO_ROLLBACK; then
    git -C ~/klipper reset --hard $rollback_version
    k_local_version=$rollback_version
    TOUPDATE=true
  else
    echo "Rollback aborted"
    return 0
  fi
}

function store_rollback_version() {
  echo -e "$k_local_version\n$k_repo $k_fullbranch" \
    >$ukam_config/config/.previous_version
}
