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
    local req_package=("mdadm" "dpkg" "util-linux") # for lsblk
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
    mapfile -t drives < <(lsblk -d -o name | tail -n +2 | sort)     # todo: better way that lsblk?
    msg "${info} Total drives detected: ${#drives[@]}"
}

get_user_input() {          #todo: tweak to allow for single key w/o enter
    local max_len="$1"
    local prompt="$2"
    local input_var="$3"
    local _input
    local _count=0

    stty erase '^?'

    echo -n "${prompt}"
    while IFS= read -r -s -n 1 _char; do
        [[ -z $_char ]] && {
                         printf '\n'             # Enter - finish input
                                      break
        }
        if [[ $_char == $'\177' ]]; then # Backspace was pressed
            if [[ $_count -gt 0 ]]; then
                _count=$((_count - 1))
                _input="${_input%?}"
                printf "\b \b" # Move cursor back and clear last character
            fi
        else
            if [[ $_count -lt $max_len ]]; then
                printf "%s" "$_char" # Print character
                _input+=$_char
                _count=$((_count + 1))
            fi
        fi
    done
    _input="${_input//\'/\'\\\'\'}"  # escape single quote chars
    eval "$input_var"="'$_input'"
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
        # build a string containing sorted drive/blk devices
    local line
    for ((i = 0; i < ${#drives[@]}; i++)); do
        printf -v line "${green}%b${nc}) %s " $((i + 1)) "${drives[i]}"
        local drives_avail+="${line}"
    done

    msg "${info} Select drives to include in the array:"
    get_user_input 10 "${ask} ${drives_avail}- Input choice as N N N: " response

    chosen_drives=() # Array to store the chosen drives
    for i in ${response}; do
        # Check if 'i' is a valid positive integer and within the valid range
        if ! [[ $i =~ ^[1-9]+$ ]] || ((i < 1 || i > ${#drives[@]})); then
            error_exit "${err} Invalid value: ${i}. Enter only positive whole numbers from 1 to ${#drives[@]}." 2
        fi
        # Add the chosen drive to the chosen_drives array
        chosen_drives+=("${drives[i - 1]}") # Subtract 1 because the array is 0-indexed
    done

    # if were to this point. let's confirm user input before the heaving lifting
    msg "$info Confirm drive selection: ${chosen_drives[*]}"    # !look into alternative device scan, to get path.  Do we need to? or just prepend
                                                                # !/dev/? can a blk dev exist outside /dev?
    msg "$ask Correct? y/n"
}

main "$@"
