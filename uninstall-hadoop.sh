#!/bin/bash

# ===================================================================
# Hadoop, Hive, and Pig Uninstallation Script for WSL Ubuntu 20.04
# Author: Yogesh M
# GitHub: https://github.com/cypherix
# License: MIT
# Version: 1.1
# Buy Me A Coffee @ https://buymeacoffee.com/cypherix
# ===================================================================

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ===================================================================
# CONFIGURATION
# ===================================================================
readonly HADOOP_VERSION="3.4.0"
readonly HIVE_VERSION="4.0.0"
readonly PIG_VERSION="0.10.0"
readonly JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
readonly LOG_FILE="hadoop_hive_uninstall_$(date +%Y%m%d_%H%M%S).log"

# Get actual user even when running with sudo
get_actual_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

readonly CURRENT_USER=$(get_actual_user)
readonly USER_HOME=$(eval echo ~"$CURRENT_USER")
readonly INSTALL_DIR="$USER_HOME"
readonly HADOOP_HOME="$INSTALL_DIR/hadoop-$HADOOP_VERSION"
readonly HIVE_HOME="$INSTALL_DIR/apache-hive-$HIVE_VERSION-bin"
readonly PIG_HOME="$INSTALL_DIR/pig-$PIG_VERSION"
readonly DATA_DIR="$INSTALL_DIR/hadoop_data"

# ===================================================================
# FUNCTIONS
# ===================================================================

# Log messages to console and log file
log() {
    local message="$1"
    local level="${2:-INFO}"
    local color="${3:-$NC}"
    
    # Format timestamp
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Echo to console with color
    echo -e "${color}[${level}] ${timestamp} - ${message}${NC}"
    
    # Log to file without color codes
    echo "[${level}] ${timestamp} - ${message}" >> "$LOG_FILE"
}

info() {
    log "$1" "INFO" "$BLUE"
}

success() {
    log "$1" "SUCCESS" "$GREEN"
}

warning() {
    log "$1" "WARNING" "$YELLOW"
}

error() {
    log "$1" "ERROR" "$RED"
}

# Check if a directory exists before attempting to remove it
safe_remove_dir() {
    local dir="$1"
    local name="$2"
    
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        success "$name installation removed from $dir"
    else
        warning "$name installation not found at $dir"
    fi
}

# Stop Hadoop services
stop_hadoop() {
    info "Stopping Hadoop services..."
    
    if [[ ! -d "$HADOOP_HOME" ]]; then
        warning "Hadoop installation not found at $HADOOP_HOME, skipping service stop"
        return
    fi
    
    export JAVA_HOME="$JAVA_HOME"
    
    # Stop YARN
    if [[ -x "$HADOOP_HOME/sbin/stop-yarn.sh" ]]; then
        "$HADOOP_HOME/sbin/stop-yarn.sh" >> "$LOG_FILE" 2>&1 || warning "Failed to stop YARN"
    fi
    
    # Stop HDFS
    if [[ -x "$HADOOP_HOME/sbin/stop-dfs.sh" ]]; then
        "$HADOOP_HOME/sbin/stop-dfs.sh" >> "$LOG_FILE" 2>&1 || warning "Failed to stop HDFS"
    fi
    
    success "Hadoop services stopped"
}

# Remove Hadoop installation
remove_hadoop() {
    info "Removing Hadoop installation..."
    safe_remove_dir "$HADOOP_HOME" "Hadoop"
}

# Remove Hive installation
remove_hive() {
    info "Removing Hive installation..."
    safe_remove_dir "$HIVE_HOME" "Hive"
}

# Remove Pig installation
remove_pig() {
    info "Removing Pig installation..."
    safe_remove_dir "$PIG_HOME" "Pig"
}

# Remove data directories
remove_data_directories() {
    info "Removing Hadoop data directories..."
    safe_remove_dir "$DATA_DIR" "Hadoop data directories"
}

# Remove environment variables from .bashrc
remove_environment_variables() {
    info "Removing environment variables from .bashrc..."
    
    local bashrc_file="$USER_HOME/.bashrc"
    
    if [[ -f "$bashrc_file" ]]; then
        # Create a backup of .bashrc
        cp "$bashrc_file" "${bashrc_file}.bak"
        
        # Remove Hadoop, Hive, and Pig related environment variables
        sed -i '/# Hadoop and Hive environment variables/,/export PATH=\$PATH:\$HADOOP_HOME\/bin:\$HADOOP_HOME\/sbin:\$HIVE_HOME\/bin/d' "$bashrc_file"
        sed -i '/# Pig environment variables/,/export PATH=\$PATH:\$PIG_HOME\/bin/d' "$bashrc_file"
        
        # Remove aliases
        sed -i '/# Hadoop and Hive aliases/,/alias hstatus/d' "$bashrc_file"
        
        success "Environment variables and aliases removed from .bashrc (backup created at ${bashrc_file}.bak)"
    else
        warning ".bashrc file not found at $bashrc_file"
    fi
}

# Remove management script
remove_management_script() {
    info "Removing management script..."
    
    local mgmt_script="$USER_HOME/manage-hadoop-hive.sh"
    
    if [[ -f "$mgmt_script" ]]; then
        rm -f "$mgmt_script"
        success "Management script removed from $mgmt_script"
    else
        warning "Management script not found at $mgmt_script"
    fi
}

print_summary() {
    echo -e "\n${GREEN}=== Uninstallation Summary ===${NC}"
    echo -e "${BLUE}Log file:${NC} $LOG_FILE"
    
    local removed_components=()
    [[ ! -d "$HADOOP_HOME" ]] && removed_components+=("Hadoop")
    [[ ! -d "$HIVE_HOME" ]] && removed_components+=("Hive")
    [[ ! -d "$PIG_HOME" ]] && removed_components+=("Pig")
    [[ ! -d "$DATA_DIR" ]] && removed_components+=("Data directories")
    
    if [[ ${#removed_components[@]} -gt 0 ]]; then
        echo -e "${GREEN}Successfully removed:${NC}"
        for component in "${removed_components[@]}"; do
            echo -e "  - $component"
        done
    fi
    
    echo -e "\n${YELLOW}To fully apply environment changes, please run:${NC}"
    echo -e "  source ~/.bashrc"
}

# Main function
main() {
    # Print welcome message
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE} Hadoop, Hive, and Pig Uninstallation Script for WSL Ubuntu 20.04${NC}"
    echo -e "${YELLOW}💻 Author:  Yogesh M${NC}"
    echo -e "${YELLOW}📌 GitHub:  ${BLUE}https://github.com/cypherix${NC}"
    echo -e "${YELLOW}🔖 License:  ${GREEN}MIT${NC}"
    echo -e "${YELLOW}📌 Version:  ${GREEN}1.1${NC}"
    echo -e "${YELLOW}☕ Support:  ${GREEN}https://buymeacoffee.com/cypherix${NC}"
    echo -e "${BLUE}======================================================${NC}"

    # Initialize log file
    echo "# Hadoop, Hive, and Pig Uninstallation Log - $(date)" > "$LOG_FILE"
    
    # Check if running as root
    if [[ $EUID -eq 0 && -z "${SUDO_USER:-}" ]]; then
        error "Please run this script with sudo, not as root directly"
        exit 1
    fi
    
    # Prompt for confirmation
    read -p "Are you sure you want to uninstall Hadoop, Hive, and Pig? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Uninstallation cancelled"
        exit 0
    fi
    
    # Stop Hadoop services
    stop_hadoop
    
    # Remove Hadoop installation
    remove_hadoop
    
    # Remove Hive installation
    remove_hive
    
    # Remove Pig installation
    remove_pig
    
    # Remove data directories
    remove_data_directories
    
    # Remove environment variables from .bashrc
    remove_environment_variables
    
    # Remove management script
    remove_management_script
    
    success "Uninstallation completed successfully!"
    
    # Print summary
    print_summary
}

# Call main function
main
exit 0