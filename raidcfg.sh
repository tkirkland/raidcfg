#!/bin/bash

# This script aims to automate the process of setting up a new Linux OS with mdadm software raid.

# Function to get the OS ID. Currently supporting 'neon', 'ubuntu' and 'debian'.
function get_os_id() {
    # If OS ID is not one of the supported ones, we exit with an error.
    if [[ ${ID} != "neon" && ${ID} != "ubuntu" && ${ID} != "debian" ]]; then
        error_exit "${err} '${ID}' OS found and is currently unsupported" 1
    fi
    msg "${ok} Detected OS '${ID}' is compatible so let us proceed..."
}

# Function to handle errors. Takes two parameters: the error message and the exit code.
function error_exit() {
    printf "%b\n" "$1"
    exit "${2}"
}

# This function displays a message.
function msg() {
    printf "%b\n" "$1"
}

# Function to initialize the variables.
function init_vars() {
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

    # If the file '/etc/os-release' does not exist, we exit with an error. Otherwise, we source it to get OS ID.
    if ! [ -f /etc/os-release ]; then
        error_exit "${err} unable to detect OS, '/etc/os-release' not found" 1
    else
        . /etc/os-release
    fi
}

# This function checks if the necessary packages are installed. If not, it displays a warning.
# In this implementation, it doesn't actually install missing packages. (ToDo)
function check_packages() {
    msg "${info}Checking if necessary packages are present..."
    local req_package=("mdadm" "dpkg" "util-linux") # for lsblk
    for ((i = 0; i < ${#req_package[@]}; i++)); do
        if [[ ! $(which "${req_package[$i]}") ]]; then
            # Display a warning because the package/command was not found.
            msg "${warn} Command '${req_package[$i]}' not found, will attempt to install..."
        fi
    done
}

# This function scans the connected HDD devices and displays their count.
function scan_drives() {
    msg "${info} Scanning attached HDD devices... "
    # Read the names of the block devices into an array 'drives'.
    mapfile -t drives < <(lsblk -d -o name | tail -n +2 | sort)
    local line
    for ((i = 0; i < ${#drives[@]}; i++)); do
        printf -v line "${green}%b${nc}) %s " $((i + 1)) "${drives[i]}"
        drives_avail+="${line}"
    done
    msg "${info} ${#drives[@]} drives detected."
}

# This function gets the user input with a few options: single-key execution, maximum length, and visibility of the input.
# The input is read character by character and stored in a variable.
# If the input is a backspace, it removes the last character from the input.
# If the input reached max length, no more characters are read.
# The variable holding the input is then returned by assigning it to the variable whose name is passed to the function.
function get_user_input() {
    local single_key="$1"
    local prompt="$2"
    local input_var="$3"
    local max_len="${4:-40}"
    local _input
    local _count=0
    local _char
    input_valid=0

    stty erase '^?'

    echo -n "${prompt}"
    while IFS= read -r -s -n 1 _char; do  #!FIX Single char input not echoing or being returned
        if [[ $single_key == 1 ]]; then
            _input+=$_char
            printf '\n'
        break
        fi
        [[ -z $_char ]] && {
            printf '\n'
            break
        }
        if [[ $_char == $'\177' ]]; then
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



    # Check if use^[a-zA-Z0-9 ]+$r input is valid, in this case, only alphanumeric

    if [[ ! "${_input}" =~  ^[a-zA-Z0-9][a-zA-Z0-9\ ]*$ ]]; then
    msg "Invalid entry... Only use alphanumeric characters."
    else
        # shellcheck disable=SC2001
        _input="$(echo "${_input}" | sed "s/'/'\\\\''/g; s/[\\\$\"()*;&|]/\\\\&/g")"
        eval "$input_var"="'$_input'"
    fi
}
# This is the main function which is responsible for managing the other functions and the main execution flow of the script.
# It first checks if the script is being run as root. If not, it exits with an error.
# After that, it initializes the variables, checks the OS compatibility, scans the HDDs,
# gets the user's is read character by character and stored in a variable.
# If the ins input about the drives to include in the array, checks them, and finally confirms the selection.
# The selection refers to the drives the user has chosen to include in the array.
function main() {
    if [[ $UID != 0 ]]; then
        error_exit "must be root" 1
    fi
    init_vars
    msg "${info} Mdadm raid config script, v0.5"
    msg "${sp}"
    msg "${sp} Checking OS compatibility..."
    get_os_id
    msg "${sp}"
    scan_drives
    msg "${sp}"
    msg "${info} Select drives (1-${#drives[@]}) space-delimited to use."
    get_user_input 0 "${ask} ${drives_avail}:" response 10

    local chosen_drives=()
    for i in ${response}; do
        if ! [[ $i =~ ^[1-9]+$ ]] || ((i < 1 || i > ${#drives[@]})); then
            error_exit "${err} Invalid value: ${i}. Only 1 to ${#drives[@]} is valid." 2
        fi
        chosen_drives+=("${drives[i - 1]}") # Subtract 1 because the array is 0-indexed
    done
    msg "${info} Confirm drive selection: ${chosen_drives[*]}"
    get_user_input 1 "${ask} Correct? y/n: " response
}

main "$@"