#!/bin/bash

#########################################################################################################################
#
# Script: install
# Purpose: Install OSX-PROXMOX
# Source: https://luchina.com.br
#
#########################################################################################################################

# Exit on any error
set -e
set -o pipefail

# All installer logic lives inside this function so that when the script is
# executed via `curl … | bash`, bash has already parsed the whole body into
# memory before we call it. We can then invoke the function with stdin
# redirected from /dev/tty without bash trying to read the *script itself*
# from the terminal (which would cause an immediate hang).
_osx_proxmox_install() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi

    # Define log file
    local LOG_FILE="/root/install-osx-proxmox.log"

    # Function to log messages
    log_message() {
        echo "$1" | tee -a "$LOG_FILE"
    }

    # Function to check command success
    check_status() {
        if [ $? -ne 0 ]; then
            log_message "Error: $1"
            exit 1
        fi
    }

    # Clear screen
    clear

    # Clean up existing files
    log_message "Cleaning up existing files..."
    # cd away first so we don't delete our own CWD when the user ran this
    # script from inside a pre-existing /root/OSX-PROXMOX clone.
    cd /root
    [ -d "/root/OSX-PROXMOX" ] && rm -rf "/root/OSX-PROXMOX"

    # Ask before disabling enterprise/ceph repo files (may be needed for subscribed installations)
    if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ] || [ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ] || \
       [ -f "/etc/apt/sources.list.d/ceph.list" ] || [ -f "/etc/apt/sources.list.d/ceph.sources" ]; then
        log_message "Found Proxmox enterprise and/or Ceph repository files."
        if [ -t 0 ]; then
            read -p "Disable enterprise/ceph repositories? Files will be backed up with .disabled suffix. (y/N): " repo_choice
            if [[ "$repo_choice" == [yY] ]]; then
                for repo_file in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.sources \
                                 /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.sources; do
                    [ -f "$repo_file" ] && mv "$repo_file" "${repo_file}.disabled" && log_message "Disabled: $repo_file"
                done
            else
                log_message "Skipping enterprise/ceph repository removal per user choice."
            fi
        else
            log_message "Non-interactive mode: skipping enterprise/ceph repository removal."
        fi
    fi

    log_message "Preparing to install OSX-PROXMOX..."

    # Update package lists
    log_message "Updating package lists..."
    apt-get update >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "Initial apt-get update failed. Attempting to fix sources..."

        # Use main Debian mirror instead of country-specific
        sed -i 's/ftp\.[a-z]\{2\}\.debian\.org/ftp.debian.org/g' /etc/apt/sources.list

        log_message "Retrying apt-get update..."
        apt-get update >> "$LOG_FILE" 2>&1
        check_status "Failed to update package lists after source modification"
    fi

    # Install git
    log_message "Installing git..."
    apt-get install -y git >> "$LOG_FILE" 2>&1
    check_status "Failed to install git"

    # Clone repository
    log_message "Cloning OSX-PROXMOX repository..."
    git clone --recurse-submodules https://github.com/taylorelley/OSX-PROXMOX.git /root/OSX-PROXMOX >> "$LOG_FILE" 2>&1
    check_status "Failed to clone repository"

    # Ensure directory exists and setup is executable
    if [ -f "/root/OSX-PROXMOX/setup" ]; then
        chmod +x "/root/OSX-PROXMOX/setup"
        log_message "Running setup script..."
        /root/OSX-PROXMOX/setup 2>&1 | tee -a "$LOG_FILE"
        local setup_exit=${PIPESTATUS[0]}
        if [ "$setup_exit" -ne 0 ]; then
            log_message "Error: Failed to run setup script (exit code: $setup_exit)"
            exit 1
        fi
    else
        log_message "Error: Setup script not found in /root/OSX-PROXMOX"
        exit 1
    fi

    log_message "Installation completed successfully"
}

# When invoked via `curl … | bash`, the script's stdin is the curl pipe
# (EOF after delivery), which would make every `read` prompt return empty
# and silently accept defaults — including the main-menu exit in ./setup.
# If a controlling terminal is available, redirect the installer's stdin
# to it so all prompts (here and in ./setup) work interactively. Doing the
# redirect only on the function call — not via a top-level `exec < /dev/tty`
# — is important: a top-level exec would make bash try to read the rest of
# the script from the terminal, causing a hang.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    _osx_proxmox_install "$@" < /dev/tty
else
    _osx_proxmox_install "$@"
fi
