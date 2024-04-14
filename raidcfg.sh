#!/bin/bash

# This script aims to automate the process of setting up a new Linux OS with mdadm software raid.

# Function to get the OS ID. Currently supporting 'neon', 'ubuntu' and 'debian'.
function get_os_id() {
    # If the file '/etc/os-release' does not exist, we exit with an error. Otherwise, we source it to get OS ID.
    if ! [ -f /etc/os-release ]; then
        error_exit "${err} Failed to detect compatible OS, '/etc/os-release' not found." 1
    else
        msg "${info} Checking OS compatibility..."
        . /etc/os-release
    fi
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
    green='\033[0;32m'
    nc='\033[0m'
    local yellow='\033[0;33m'

    info="[i]"
    err="[${red}!${nc}]"
    ok="[${green}+${nc}]"
    warn="[${yellow}W${nc}]"
    sp="[ ]"
    ask="[?]"
}
function check_install_reqs() {
    local _cmd
    local package_name=""
    local installation_status=0
    local _installs=0
    declare -A cmd_to_package=(["dpkg"]="dpkg" ["mdadm"]="mdadm")    # if later we add other os compatibility
    if ! command -v apt-get &>/dev/null; then                        # we can adjust packages here
        error_exit "${err} Command 'apt-get' not found but is required." 1
    fi
    for _cmd in "${!cmd_to_package[@]}"; do
        package_name="${cmd_to_package[$_cmd]}"
        if ! command -v "$_cmd" &>/dev/null; then
            msg "${warn} Missing '${_cmd}' command. Attempting install of package."
            if apt-get install -y "$package_name" >/dev/null 2>>error.log; then
                _installs=1
            else
                installation_status=1
                msg "${err} Failed to install package '${package_name}'."
                msg "${sp}"
            fi
        else
            msg "${ok} Shell command '${_cmd}' already installed."
            msg "${sp}"
        fi
    done
    if [[ ${installation_status} -eq 1 ]]; then
        if [[ ${_installs} -eq 1 ]]; then
            error_exit "${warn} Some packages were not installed successfully. See 'error.log' in ${PWD}" 1
        else
            error_exit "${err} An error occurred installing prerequisites. See 'error.log' in ${PWD}" 1
        fi
    elif [[ ${_installs} -eq 0 ]]; then
        msg "${info} All necessary packages were already installed."
    else
        msg "${info} All necessary packages have been successfully installed."
    fi
}


# This function scans the connected HDD devices and displays their count.
# shellcheck disable=SC2155
# The scan_drives function scans all attached HDD devices.
function scan_drives() {
    local dev_name
    local device
    local full_path
    drives_avail=()
    msg "${info} Scanning attached block storage devices... "
    for device in /sys/block/*; do
        dev_name=$(basename "${device}")
        if [ -d "$device/device" ]; then
            full_path="/dev/${dev_name}"
            # Check if the device is writable
            if [ -w "${full_path}" ]; then
                drives_avail+=("${full_path}")
            fi
            drives_avail+=("${full_path}")
        fi
    done
    msg "${info} ${#drives_avail[@]} drives detected."
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
    local _input=""
    local _count=0
    local _char

    stty erase '^?'

    trap 'error_exit "\n${sp}\n${err} Interrupt received from user." 255' SIGINT
    echo -n "${prompt}"
    while IFS= read -r -s -n 1 _char; do
        local ord
        ord=$(printf '%d' "'${_char}")  # Get ASCII numerical value of character

        if [[ ${single_key} == 1 ]]; then
            if [[ $ord -ge 32 && $ord -le 126 ]]; then
                _input+="${_char}"
                printf '%s\n' "${_char}"
                break
            fi
        fi

        [[ -z ${_char} ]] && {
            printf '\n'
            break
        }

        if [[ ${_char} == $'\177' ]]; then
            if [[ $_count -gt 0 ]]; then
                _count=$((_count - 1))
                _input="${_input%?}"
                printf "\b \b" # Move cursor back and clear last character
            fi
        else
            # Ignore up and down arrow keys
            if [[ $_char == $'\033' ]]; then
                read -r -s -n 2 -t 0.0001
            elif [[ $_count -lt $max_len && $ord -ge 32 && $ord -le 126 ]]; then
                printf "%s" "$_char" # Print character
                _input+="${_char}"
                _count=$((_count + 1))
            fi
        fi
    done

    eval "$input_var=\"$_input\""
}

# This is the main function which is responsible for managing the other functions and the main execution flow of the script.
# It first checks if the script is being run as root. If not, it exits with an error.
# After that, it initializes the variables, checks the OS compatibility, scans the HDDs,
# gets the user's is read character by character and stored in a variable.
# If the ins input about the drives to include in the array, checks them, and finally confirms the selection.
# The selection refers to the drives the user has chosen to include in the array.
function main() {
    local i
    init_vars
        if [ "$EUID" -ne 0 ]; then
            echo "${info} Needs root... attempting."
            msg "${sp}"
            # shellcheck disable=SC2093
            exec sudo "$0" "$@"
            error_exit "${err} Failed to gain root. Exiting." 1
        fi
        msg "${ok} Super cow powers activated!"
        msg "${sp}"
    msg "${info} Mdadm raid config script, v0.5"
    msg "${sp}"
    get_os_id
    msg "${sp}"
    check_install_reqs
    msg "${sp}"
    scan_drives
    msg "${sp}"
    msg "${info} Available devices: $(for i in "${!drives_avail[@]}";
                                        do printf "${green}%d${nc}) %s " "$((i + 1))" "${drives_avail[$i]}";
                                        done)"
    get_user_input 0 "${ask} Select drives (1-${#drives_avail[@]}) space-delimited to use: " response 10
    local chosen_drives=()
    for i in ${response}; do
        if ! [[ $i =~ ^[1-9]+$ ]] || ((i < 1 || i > ${#drives_avail[@]})); then
            error_exit "${err} Invalid input '${i}'. Only 1 to ${#drives_avail[@]} accepted." 2
        fi
        chosen_drives+=("${drives_avail[i - 1]}") # Subtract 1 because the array is 0-indexed
    done
    if [ -z "${chosen_drives[*]}" ]; then
        error_exit "${sp}\n${err} No selections made. Terminating." 1
    fi
    msg "${sp}"
    msg "${info} Confirm drive selection: ${chosen_drives[*]}"
    msg "${sp}"
    get_user_input 1 "${ask} Correct? y/n: " response
    if ! [[ ${response} == "y" ]]; then
        error_exit "${err} Rerun the script to start over." 1
    fi
    # Let's get to work...
    exit 0
}

main "$@"
