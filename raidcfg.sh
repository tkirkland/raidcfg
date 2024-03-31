#!/bin/bash
#
# This script aims to automate (as much as is possible) performing a new linux install
# in tandem with mdadm software raid since most installers lack that option
#
# YMMV

# get os ID {neon, debian etc)
function get_os_id() {
  if [[ ${ID} != "neon" && ${ID} != "ubuntu" && ${ID} != "debian" ]]; then
      error_exit "${err} '${ID}' OS found and is currently unsupported" 1
  fi
  msg "${ok} Detected OS '${ID}' so let us proceed..."
}

# takes two params: string to display and int as exit code
function error_exit() {
  printf "%b\n" "${1}"
  exit "${2}"
}

function msg() {
  printf "%b\n" "${1}"
}

init_vars() {
  # set color codes for text
  red='\033[0;31m'
  green='\033[0;32m'
  nc='\033[0m'
  yellow='\033[0;33m'

  info="[i]"
  err="[${red}!${nc}]"
  ok="[${green}+${nc}]"
  warn="[${yellow}W${nc}]"
  sp="[ ]"

 if ! [ -f /etc/os-release ]; then
    error_exit "${err} unable to detect OS, '/etc/os-release' not found" 1
  else
    . /etc/os-release
  fi
}

function check_packages() {
  # install req packages if needed
  msg "${info}Checking if necessary packages are present..."
  local req_package=("mdadm" "dpkg")
  for (( i = 0; i < ${#req_package[@]}; i++ )); do
    if [[ ! $(which "${req_package[$i]}") ]]; then
         msg "$warn Command '${req_package[$i]}' not found, will attempt to install..."
    fi
  done
}

scan_drives() {
  msg "${info} Scanning attached HDD devices..."
  mapfile -t drives < <(lsblk -d -o name | tail -n +2 | sort)
  msg "${info} Total drives detected: ${#drives[@]}"
}

# main thread
function main() {
  if [[ $UID != 0 ]]; then
    error_exit "script needs root" 1
  fi
  init_vars
  msg "$info Mdadm raid config script, v0.4"
  msg "${sp}"
  msg "${sp} Checking OS compatibility..."
  get_os_id
  msg "${sp}"
  scan_drives
  msg "${sp}"
  local line
  for ((i=0; i<${#drives[@]}; i++)); do
    printf -v line "${green}%b${nc}) %s " $((i + 1)) "${drives[i]}"
    local prompt+="$line"
  done
  msg "[?] Select drives to include in the array (enter: n n n): ${drive_selection}"

  for i in "${drive_selection[@]}"; do
    # is char[idx] a valid int?
    if ! [[ $i =~ ^[0-9]+$ ]]; then
      echo "Error: $idx is not a number"
      exit 1
    fi

    # Check if idx is within the valid range
    if (( i < 1 || idx > ${#drives[@]} )); then
        echo "Error: $idx is not a valid selection"
        exit 1
    fi

  done
}

main "$@"
