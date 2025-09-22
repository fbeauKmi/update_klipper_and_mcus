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
  if [[ "$k_local_version" == *"dirty"* ]]; then
    echo -e "${RED}WARNING : Rollback a dirty repo will erase" \
      "untracked files.${DEFAULT}"
  fi
  $DO_ROLLBACK && ! prompt "Rollback to $rollback_version ?"  &&  DO_ROLLBACK=false
  while ! $DO_ROLLBACK; do
    while [[ ! "$rollback_type" =~ ^[1-3]$ ]]; do
      echo -e "${MAGENTA}Select rollback type:${DEFAULT}"
      echo -e "${CYAN}  1)${DEFAULT} Rollback by number of commits"
      echo -e "${CYAN}  2)${DEFAULT} Rollback by version tag"
      echo -e "${CYAN}  3)${DEFAULT} Rollback by date"
      echo -e "${CYAN}  A)${DEFAULT} Abort rollback"
      read -p "Your choice ? " rollback_type
      if [[ "${rollback_type^^}" == "A" ]]; then
        echo "Rollback aborted"
        return 0
      fi
    done

    case $rollback_type in
      1)
          nb_rollback=""
          while [[ ! "$nb_rollback" =~ ^[0-9]+$ ]]; do
            read -p "${MAGENTA}Number of commits to rollback, [A] to \
abort ? ${DEFAULT}" nb_rollback
            if [[ "${nb_rollback^^}" == "A" ]]; then
              echo "Rollback aborted"
              return 0
            fi
          done
        ;;
      2)
          version=""
          tag=$(git -C ~/klipper describe --tags $(git -C ~/klipper rev-list --tags --max-count=1))
          while [[ ! "$version" =~ ^[0-9]+$ ]]; do
            read -p "${MAGENTA}Version tag to rollback (${tag}-???, only the last digits), [A] to \
abort ? ${DEFAULT}" version
            if [[ "${version^^}" == "A" ]]; then
              echo "Rollback aborted"
              return 0
            fi
            
            rollback_version=$(git -C ~/klipper rev-list $tag..HEAD | xargs git -C ~/klipper describe --tags --always | grep "$tag-$version")
            if ! git -C ~/klipper rev-parse "$rollback_version" >/dev/null 2>&1; then
              echo -e "${RED}Version $rollback_version not found${DEFAULT}"
              rollback_version=""
            fi
          done

          nb_rollback=$(git -C ~/klipper rev-list --count $rollback_version..HEAD)
        ;;
      3)
          rollback_hash=""
          rollback_date=""
          while [[ ! "$rollback_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; do
            read -p "${MAGENTA}Rollback to date (YYYY-MM-DD) , [A] to \
abort ? ${DEFAULT}" rollback_date
            if [[ "${nb_rollback^^}" == "A" ]]; then
              echo "Rollback aborted"
              return 0
            fi
          done
          
          rollback_hash=$(git -C ~/klipper rev-list -1 --before="$rollback_date" HEAD)
          if [[ "$rollback_hash" == "" ]]; then
            echo -e "${RED}No commit found before $rollback_date${DEFAULT}"
          else
            nb_rollback=$(git -C ~/klipper rev-list --count $rollback_hash..HEAD)
          fi
        ;;
    esac
    
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
