#!/bin/bash
#
# This script aims to automate (as much as is possible) performing a new linux install
# in tandem with mdadm software raid since most installers lack that option
#
# YMMV

# get os ID {neon, debian etc)
function get_os_id() {
  if [[ ${ID} != "neon" && ${ID} != "ubuntu" && ${ID} != "debian" ]]; then
      error_exit "${err}${ID} OS found and is currently unsupported" 1
  fi
  msg "${info} detected OS ${ID} so let us proceed..."
}

# takes two parms: string to display and int as exit code
function error_exit() {
  printf "%s" "${1}"
  exit "${2}"
}

function msg() {
  printf "%s" "${1}"
}

init_vars() {
  # set color codes for text
  local color_red='\033[31m'
  local color_green='\033[32m'
  local color_reset='\033[0m'
  local color_yellow='\033[33m'

  info="[i]"
  err="[${color_red}!${color_reset}]"
  ok="[${color_green}+${color_reset}]"
  warn="[${color_yellow}W${color_reset}]"
  _="[-]"

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

# main thread
function main() {
  init_vars
  msg "$info raidConfig script, v0.4"
  msg "${_}"
  msg "$info raidConfig script, v0.4"

}

main "$@"
