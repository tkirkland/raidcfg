#!/bin/bash

# This script aims to automate the process of setting up a new Linux OS with mdadm software raid.

# Function to get the OS ID. Currently supporting 'neon', 'ubuntu' and 'debian'.
function get_os_id() {
    # If the file '/etc/os-release' does not exist, we exit with an error. Otherwise, we source it to get OS ID.
    if ! [ -f /etc/os-release ]; then
        error_exit "${err} Unable to detect compatible OS, '/etc/os-release' not found." 1
    else
        msg "${info} Checking OS compatibility..."
        . /etc/os-release
    fi
    # If OS ID is not one of the supported ones, we exit with an error.
    if [[ ${ID} != "neon" && ${ID} != "ubuntu" && ${ID} != "debian" ]]; then
        error_exit "${err} '${ID}' OS found but is currently unsupported." 1
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
    _bios=""
    chosen_drives=()
}

# shellcheck disable=SC2016
function check_install_reqs() {
: '
It utilizes an associative array `cmd_to_package` with command-to-package mappings.
In this array, each key (e.g. ["dpkg"]) represents a system command to check, and
each value (e.g. "dpkg") is the corresponding package to install if the command
is not present in the system.

Example of array:
["dpkg"]="dpkg" - Here, "dpkg" is the command to check and the package to install.
["mdadm"]="mdadm" - "mdadm" is the command to check and the package to install.
["gdisk"]="sgdisk" - "gdisk" is the command to check and "sgdisk" is the package to install.
'
    local _cmd
    local package_name=""
    local installation_status=0
    local _installs=0
    declare -A cmd_to_package=(["dpkg"]="dpkg" ["mdadm"]="mdadm" ["sgdisk"]="gdisk")    # if later we add other os compatibility
    if ! command -v apt-get &>/dev/null; then                                           # we can adjust packages here
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
function scan_drives() {   # !! Broken after adding check for removable drives
    drives_avail=()
    local dev
    local device
    # List all block devices, ignoring USB devices
    for dev in /sys/block/*/device; do
        if [[ "$(udevadm info --query=property --path="${dev}" | grep ID_BUS)" != *usb* ]]; then
            # Extract the device name
            device="/dev/$(basename "$(dirname "${dev}")")"
            # Check if the device is writable
            if [ -w "${device}" ]; then
                # Append the device to the array
                drives_avail+=("${device}")
            fi
        fi
    done
    if [ ${#drives_avail[@]} -lt 1 ]; then
        error_exit "${err} No drives detected. Cannot continue in this state." 3
    else
        msg "${info} ${#drives_avail[@]} writable drives detected."
    fi
}

####################
# `get_user_input` is a function to gather user input from the command line and validate it.
#
# @param 1 {string} prompt
#       The message that is displayed to the user asking for their input.
#
# @param 2 {string} _acceptable_input
#       A regular expression pattern that the user's input is validated against.
#       The function refutes input that does not match this pattern.
#
# @param 3 {string} _return_value_var
#       The name of the variable where the gathered user input will be stored.
#
# @param 4 {boolean} single_key
#       A flag that determines whether the function should return after the first printable
#       ASCII character is entered. If `single_key` is set to true (1), the function will return
#       once the first key is pressed. Otherwise, the function will return once Enter is pressed or
#       the maximum length is reached.
#
# @param 5 {number} max_len
#       The maximum length that the user's input can be.
#       If not set, the `max_len` parameter defaults to a length of 40 characters.
#
function get_user_input() {         #!! FIXME : I broke the input routine again
    local _input=""
    local _count=0
    local _char
    local prompt="$1"
    local _acceptable_input="$2"
    local _return_var_name="$3"
    local single_key="$4"
    local max_len="${5:-40}"

    stty erase '^?'

    trap 'error_exit "\n${sp}\n${err} Interrupt received from user." 255' SIGINT
    printf "%b " "${prompt}"
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
            if [[ ${_count} -gt 0 ]]; then
                _count=$((_count - 1))
                _input="${_input%?}"
                printf "\b \b" # Move cursor back and clear last character
            fi
        else
            # Ignore up and down arrow keys
            if [[ $_char == $'\033' ]]; then
                read -r -s -n 2 -t 0.0001
            elif [[ $_count -lt ${max_len} && ${ord} -ge 32 && ${ord} -le 126 ]]; then
                printf "%s" "$_char" # Print character
                _input+="${_char}"
                _count=$((_count + 1))
            fi
        fi
    done
    if ! [[ ${_input} =~ ${_acceptable_input} ]]; then
        error_exit "${sp}\n${err} '${_input}' is invalid input. Terminating." 5
    else
        eval "$_return_var_name=\"$_input\""
    fi
}

get_device_sizes() {
    local drive
    local size
    local size_in_gb
    for drive in "${chosen_drives[@]}"
    do
        echo "Getting size for device: ${drive}"
        # Get device size using kernel methods.
        if [ -e "/sys/block/${drive##*/}/size" ]; then
            size=$(cat "/sys/block/${drive##*/}/size")
            # Convert to GB (Each block is 512 bytes)
            size_in_gb=$(echo "$size/2/1024/1024" | bc)
            echo "Size of ${drive}: $size_in_gb GB (Approx)"
        # As a fallback, use sgdisk if available.
        elif command -v sgdisk > /dev/null; then
            size_in_gb=$(sgdisk -p "${drive}" | grep 'Disk size' | awk '{ print $3 " " $4 }')
            echo "Size of ${drive}: $size_in_gb"
        else
            echo "Cannot determine size for ${drive}."
        fi
    done
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
    msg "${info} Available devices: $(for i in "${!drives_avail[@]}"; do printf "${green}%d${nc}) %s " "$((i + 1))" "${drives_avail[$i]}"
    done)"
    get_user_input "${ask} Select drives (1-${#drives_avail[@]}) space-delimited to use:" "[0-${#drives_avail[@]}]" response 0 10
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
    get_user_input "${ask} Correct? y/n:" "[yYnN]" response 1
    if [[ ${response} =~ [nN] ]]; then
        error_exit "${sp}\n${err} Drive selection not confirmed. Terminating." 3
    fi
    msg "${sp}\n${err} ${red}WARNING:${nc} A wrong choice could mean non-bootable OS!"
    msg "${sp}\n${info} System detected as $(if [[ ${_bios} -eq 0 ]]; then msg "BIOS/Legacy";
        else msg "UEFI"; fi) mode. Does this system support (${green}b${nc})oth legacy & UEFI, (${green}l${nc})egacy only, or (${green}U${nc})EFI"
            get_user_input "${sp} only?\n${ask} Choice? b/l/u" "[bBlLuU]" response 1
            msg "${info} Partitioning will be configured for a $(if [[ ${response} =~ [bB] ]]; then msg "BIOS and UEFI" && _bios="b";
                                                                elif [[ ${response} =~ [lL] ]]; then msg "legacy"; _bios="l";
                                                                else msg "UEFI" && _bios="u"; fi) configuration."
    # We're now ready to find drive sizes
    get_device_sizes
}

main "$@"
