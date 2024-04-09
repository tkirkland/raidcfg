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
    local red='\033[0;31m'
    local green='\033[0;32m'
    local nc='\033[0m'
    local yellow='\033[0;33m'

    info="[i]"
    err="[${red}!${nc}]"
    ok="[${green}+${nc}]"
    warn="[${yellow}W${nc}]"
    sp="[ ]"
    ask="[?]"
}

function check_install_reqs() {
    local cmd=""
    local package_name=""
    local installation_status=0
    declare -A cmd_to_package=(["lsblk"]="util-linux" ["dpkg"]="dpkg" ["mdadm"]="mdadm")    # if later we add other os compatibility
    msg "${sp}"
    if ! command -v apt-get &>/dev/null; then                                               # we can adjust packages here
        error_exit "${err} 'apt-get' command not found. This script requires 'apt-get' to be installed." 1
    fi
    for cmd in "${!cmd_to_package[@]}"; do
        package_name="${cmd_to_package[$cmd]}"
        if ! command -v "$cmd" &>/dev/null; then
            msg "${warn} Missing '${cmd}' command. Attempting install of package."
            if ! apt-get install -y "$package_name" >/dev/null 2>>error.log; then
                installation_status=1
                msg "${err} Failed to install package '${package_name}'."
                msg "${sp}"
            fi
        else
            msg "${info} Shell command '${cmd}' found."
            msg "${sp}"
        fi
    done
    if ! [[ ${installation_status} ]]; then
        error_exit "${err} An error occurred installing prerequisites. See \'error.log\' in ${PWD}" 1
    fi
    msg "${ok} No reported errors during package install."
}

# This function scans the connected HDD devices and displays their count.
function scan_drives() {
    msg "${info} Scanning attached HDD devices... "
    # Read the names of the block devices into an array 'drives'.
    mapfile -t drives < <(lsblk -d -o name | tail -n +2 | sort)
    local line
    for ((i = 0; i < ${#drives[@]}; i++)); do
        printf -v line "[%b]) %s " $((i + 1)) "${drives[i]}"
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

    stty erase '^?'

    echo -n "${prompt}"
    while IFS= read -r -s -n 1 _char; do
        if [[ ${single_key} == 1 ]]; then
            _input+=${_char}
            printf '%s\n' "${_char}"
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

    if [[ ! ${_input} =~ ^[a-zA-Z0-9][a-zA-Z0-9\ ]*$ ]]; then
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
    init_vars
    if [ "$EUID" -ne 0 ]; then
        echo "${info} Needs root... attempting."
        msg "${sp}"
        # shellcheck disable=SC2093
        exec sudo "$0" "$@"
        error_exit "${err} Failed to gain root. Exiting." 1
    fi
    # If the file '/etc/os-release' does not exist, we exit with an error. Otherwise, we source it to get OS ID.
    if ! [ -f /etc/os-release ]; then
        error_exit "${err} Failed to detect compatible OS, '/etc/os-release' not found." 1
    else
        . /etc/os-release
    fi
    msg "${ok} Super cow powers activated!"
    msg "${sp}"
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
            error_exit "${err} Invalid value: ${i}. Only 1 to ${#drives[@]} accepted." 2
        fi
        chosen_drives+=("${drives[i - 1]}") # Subtract 1 because the array is 0-indexed
    done
    msg "${sp}"
    msg "${info} Confirm drive selection: ${chosen_drives[*]}"
    msg "${sp}"
    get_user_input 1 "${ask} Correct? y/n: " response
    if ! [[ ${response} == "y" ]]; then
        error_exit "${err} Rerun the script to start over." 1
    fi
    # Let's get to work...
    check_install_reqs
    exit 0
}

main "$@"
