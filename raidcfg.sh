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
    # set color codes for text, we like uniformity w/ color
    red='\033[0;31m'
    green='\033[0;32m'
    nc='\033[0m'
    yellow='\033[0;33m'

    info="[i]"
    err="[${red}!${nc}]"
    ok="[${green}+${nc}]"
    warn="[${yellow}W${nc}]"
    sp="[ ]"
    ask="[?]"

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
    for ((i = 0; i < ${#req_package[@]}; i++)); do
        if [[ ! $(which "${req_package[$i]}") ]]; then
            msg "$warn Command '${req_package[$i]}' not found, will attempt to install..."
            # todo: build install packages code
        else
            # todo: msg package is installed
            :
        fi
    done
}

scan_drives() {   # enum through connected blk storage, return count
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
    for ((i = 0; i < ${#drives[@]}; i++)); do
        printf -v line "${green}%b${nc}) %s " $((i + 1)) "${drives[i]}"
        local drive_selection+="${line}"
    done

    msg "${info} Select drives to include in the array (enter: n n n): ${drive_selection}"  # !FIXME: needs new mapfile var
                                                                                            # TODO: Do we even have have input routine?
                                                                                            # TODO: Hell no!  Make input function
    for i in "${drive_selection[@]}"; do
        # is char[i] a valid int?
        if ! [[ $i =~ ^[1-9]+$ ]]; then
            error_exit "${err} ${i} is not a number. Enter only positive whole numbers from 1 to N." 2
        fi
        # Check if idx is within the valid range
        if ((i < 1 || i > ${#drives[@]})); then
            error_exit "$err Invalid value entered. Valid range is 1 - ${#drives[@]}..." 2
        fi
    done

    # if were to this point. let's confirm user input before the heaving lifting
    msg "$info Confirm drive selection: ${drive_selection}"
    # TODO: Hell no!  Make input function
    # TODO: Show selected drives to use & get confirmation

}

main "$@"
