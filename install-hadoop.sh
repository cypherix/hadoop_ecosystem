#!/bin/bash

# ===================================================================
# Hadoop, Hive and Pig Setup Script for WSL Ubuntu 20.04
# Author: Yogesh M
# GitHub: https://github.com/cypherix
# License: MIT
# Version: 1.0
# Buy Me A Coffee @ https://buymeacoffee.com/cypherix
# ===================================================================

# Exit on error, undefined variables, and pipe failures
set -euo pipefail


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get actual user even when running with sudo
get_actual_user() {
    if [ -n "${SUDO_USER:-}" ]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

# ===================================================================
# CONFIGURATION
# ===================================================================
HADOOP_VERSION="3.4.0"
HIVE_VERSION="4.0.0"
PIG_VERSION="0.10.0"
INSTALL_DIR="/home/$(get_actual_user)"
HADOOP_HOME="$INSTALL_DIR/hadoop-$HADOOP_VERSION"
HIVE_HOME="$INSTALL_DIR/apache-hive-$HIVE_VERSION-bin"
DATA_DIR="$INSTALL_DIR/hadoop_data"
JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
LOG_FILE="hadoop_hive_setup_$(date +%Y%m%d_%H%M%S).log"

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

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if user has sudo privileges
check_sudo() {
    if ! command_exists sudo; then
        error "sudo command not found. Please install sudo or run this script as root."
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        warning "This script requires sudo privileges."
        if ! sudo -v; then
            error "Failed to obtain sudo privileges. Exiting."
            exit 1
        fi
    fi
}


# Create backup of a file
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        info "Backup created: $backup"
    fi
}

# Check and create directory with proper permissions
ensure_directory() {
    local dir="$1"
    local owner="$2"
    
    if [ ! -d "$dir" ]; then
        info "Creating directory: $dir"
        mkdir -p "$dir"
    fi
    
    chown -R "$owner:$owner" "$dir"
    info "Directory permissions set for $dir"
}

# Check Java version
check_java() {
    info "Checking Java installation..."
    
    if ! command_exists java; then
        warning "Java not found. Installing OpenJDK 8..."
        sudo apt update -y
        sudo apt install -y openjdk-8-jdk
    fi
    
    # Verify Java version
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    if [[ "$java_version" == 1.8* ]]; then
        success "Java 8 is installed: $java_version"
    else
        warning "Java version is $java_version. This script is designed for Java 8."
        warning "You may encounter issues. Consider installing OpenJDK 8."
    fi
    
    # Ensure JAVA_HOME points to Java 8
    if [ ! -d "$JAVA_HOME" ]; then
        warning "JAVA_HOME directory not found: $JAVA_HOME"
        JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
        warning "Setting JAVA_HOME to $JAVA_HOME"
    fi
}

# Check for required disk space
check_disk_space() {
    local required_space=5000000  # ~5GB in KB
    local available_space=$(df -k "$INSTALL_DIR" | awk 'NR==2 {print $4}')
    
    if [ "$available_space" -lt "$required_space" ]; then
        error "Not enough disk space. Required: 5GB, Available: $(($available_space/1024))MB"
        exit 1
    else
        success "Sufficient disk space available: $(($available_space/1024))MB"
    fi
}

# WSL-specific checks and optimizations
wsl_checks() {
    info "Checking for WSL environment..."
    
    # Check if running in WSL
    if grep -q Microsoft /proc/version || grep -q microsoft /proc/version; then
        success "WSL detected, applying specific configurations..."
        
        # Create .wslconfig file if it doesn't exist with recommended settings
        if [ ! -f "$USER_HOME/.wslconfig" ]; then
            info "Creating WSL configuration file..."
            cat <<EOF > "$USER_HOME/.wslconfig"
[wsl2]
memory=4GB
processors=2
swap=2GB
EOF
            success "Created .wslconfig with recommended settings"
            warning "Consider restarting WSL for these settings to take effect: 'wsl --shutdown' from PowerShell"
        fi
        
        # Check for network issues specific to WSL
        if ! ping -c 1 8.8.8.8 &>/dev/null; then
            warning "Network connectivity issues detected in WSL"
            warning "If download issues occur, try: 'sudo service network-manager restart' or restart WSL"
        fi
    else
        info "Not running in WSL environment"
    fi
}

# Setup SSH for passwordless authentication
setup_ssh() {
    echo "[INFO] Setting up SSH for Hadoop..."

    # Ensure SSH is installed
    if ! command -v ssh >/dev/null 2>&1; then
        echo "[WARNING] SSH not found. Installing..."
        sudo apt update && sudo apt install -y openssh-server openssh-client 
    fi

    # Get the current user
    CURRENT_USER=$(get_actual_user)
    USER_HOME=$(eval echo ~$CURRENT_USER)

    # Ensure .ssh directory exists with correct permissions
    if [ ! -d "$USER_HOME/.ssh" ]; then
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        chown "$CURRENT_USER:$CURRENT_USER" "$USER_HOME/.ssh"
    fi

    # Generate SSH key if it doesn't exist
    if [ ! -f "$USER_HOME/.ssh/id_rsa" ]; then
        su - "$CURRENT_USER" -c "ssh-keygen -t rsa -N '' -f $USER_HOME/.ssh/id_rsa"
        cat "$USER_HOME/.ssh/id_rsa.pub" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        echo "[SUCCESS] SSH keys generated."
    else
        echo "[INFO] SSH keys already exist."
    fi

    # Restart SSH service
    sudo systemctl enable ssh
    # sudo systemctl restart ssh
    sleep 2

    # Test SSH connection
    if su - "$CURRENT_USER" -c "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 localhost echo 'SSH test successful'" &>/dev/null; then
        echo "[SUCCESS] SSH connection test successful."
    else
        echo "[ERROR] SSH connection failed! Check 'sudo systemctl status ssh'"
    fi
}


# Download and install software
download_and_install() {
    local name="$1"
    local version="$2"
    local url="$3"
    local archive="$4"
    local extract_dir="$5"
    local destination="$INSTALL_DIR/$(basename "$extract_dir")"
    
    info "Installing $name $version..."
    
    # Check if already installed
    if [ -d "$destination" ]; then
        warning "$name $version is already installed at $destination"
        read -p "Reinstall? (y/n): " -r choice
        if [[ ! $choice =~ ^[Yy]$ ]]; then
            info "Skipping $name installation"
            return 0
        fi
        info "Removing existing installation..."
        rm -rf "$destination"
    fi
    
    # Download with progress and retry
    cd "$INSTALL_DIR"
    info "Downloading $name $version..."
    
    local max_retries=3
    local retry=0
    local download_success=false
    
    while [ $retry -lt $max_retries ] && [ "$download_success" = false ]; do
        if wget --progress=bar:force:noscroll "$url" -O "$archive" 2>&1; then
            download_success=true
        else
            retry=$((retry+1))
            warning "Download failed. Retry $retry of $max_retries..."
            sleep 2
        fi
    done
    
    if [ "$download_success" = false ]; then
        error "Failed to download $name after $max_retries attempts."
        exit 1
    fi
    
    # Extract archive
    info "Extracting $name..."
    if tar -xzf "$archive"; then
        rm "$archive"
        success "$name extracted successfully"
    else
        error "Failed to extract $name"
        exit 1
    fi
    
    # Set permissions
    chown -R "$CURRENT_USER:$CURRENT_USER" "$destination"
    success "$name $version installation completed"
}
ensure_directory() {
    local dir="$1"
    local owner="$2"
    
    if [ ! -d "$dir" ]; then
        info "Creating directory: $dir"
        mkdir -p "$dir"
    fi
    
    chown -R "$owner:$owner" "$dir"
    info "Directory permissions set for $dir"
}
# Configure Hadoop
configure_hadoop() {
    local hadoop_user="$1"
    info "Configuring Hadoop..."
    
    # Backup original configuration files
    backup_file "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
    backup_file "$HADOOP_HOME/etc/hadoop/core-site.xml"
    backup_file "$HADOOP_HOME/etc/hadoop/hdfs-site.xml"
    
    # Set JAVA_HOME in hadoop-env.sh
    sed -i "s|# export JAVA_HOME=.*|export JAVA_HOME=$JAVA_HOME|" "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"

    add_variable_if_missing() {
    VAR_NAME=$1
    VAR_VALUE=$2
    if ! grep -q "^export $VAR_NAME=" "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"; then
        echo "export $VAR_NAME=\"$VAR_VALUE\"" >> "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"
        echo "✅ Added: $VAR_NAME=$VAR_VALUE"
    else
        echo "⚡ Skipping: $VAR_NAME already set"
    fi
}



# Add missing variables
add_variable_if_missing "HDFS_NAMENODE_USER" "$hadoop_user"
add_variable_if_missing "HDFS_DATANODE_USER" "$hadoop_user"
add_variable_if_missing "HDFS_SECONDARYNAMENODE_USER" "$hadoop_user"
add_variable_if_missing "YARN_RESOURCEMANAGER_USER" "$hadoop_user"
add_variable_if_missing "YARN_NODEMANAGER_USER" "$hadoop_user"

    # Create core-site.xml
    cat <<EOF > "$HADOOP_HOME/etc/hadoop/core-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>$DATA_DIR/tmp</value>
    </property>
    <property>
        <name>hadoop.proxyuser.$hadoop_user.hosts</name>
        <value>localhost</value>
    </property>
    <property>
        <name>hadoop.proxyuser.$hadoop_user.groups</name>
        <value>$hadoop_user</value>
    </property>
</configuration>
EOF
    
    # Create hdfs-site.xml
    cat <<EOF > "$HADOOP_HOME/etc/hadoop/hdfs-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://$DATA_DIR/name</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://$DATA_DIR/data</value>
    </property>
    <property>
        <name>dfs.permissions.enabled</name>
        <value>false</value>
        <description>Disable permissions checking (for testing only)</description>
    </property>
</configuration>
EOF

    # Create mapred-site.xml
    cp "$HADOOP_HOME/etc/hadoop/mapred-site.xml.template" "$HADOOP_HOME/etc/hadoop/mapred-site.xml" 2>/dev/null || :
    cat <<EOF > "$HADOOP_HOME/etc/hadoop/mapred-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
</configuration>
EOF

    # Create yarn-site.xml
    cat <<EOF > "$HADOOP_HOME/etc/hadoop/yarn-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
</configuration>
EOF
    ensure_directory "$HADOOP_HOME/logs" "$(get_actual_user)"
    chmod 755 "$HADOOP_HOME/logs"
    success "Hadoop configuration completed"
}

# Configure Hive
configure_hive() {
    info "Configuring Hive..."
    
    # Create Hive configuration directory if it doesn't exist
    if [ ! -d "$HIVE_HOME/conf" ]; then
        mkdir -p "$HIVE_HOME/conf"
    fi
    
    # Copy template if it exists
    if [ -f "$HIVE_HOME/conf/hive-default.xml.template" ]; then
        cp "$HIVE_HOME/conf/hive-default.xml.template" "$HIVE_HOME/conf/hive-site.xml"
    fi
    
    # Create or overwrite hive-site.xml
    cat <<EOF > "$HIVE_HOME/conf/hive-site.xml"
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:derby:;databaseName=$HIVE_HOME/metastore_db;create=true</value>
        <description>JDBC connect string for a JDBC metastore</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>org.apache.derby.jdbc.EmbeddedDriver</value>
        <description>Driver class name for a JDBC metastore</description>
    </property>
    <property>
        <name>hive.metastore.warehouse.dir</name>
        <value>/user/hive/warehouse</value>
        <description>location of default database for the warehouse</description>
    </property>
    <property>
        <name>hive.exec.scratchdir</name>
        <value>/tmp/hive</value>
        <description>HDFS scratch directory for Hive jobs</description>
    </property>
    <property>
        <name>hive.metastore.schema.verification</name>
        <value>false</value>
        <description>Disable schema verification to prevent issues with schema versions</description>
    </property>
    <property>
        <name>hive.server2.authentication</name>
        <value>NONE</value>
    </property>
    <property>
        <name>hive.server2.enable.doAs</name>
        <value>true</value>
    </property>
</configuration>
EOF

    success "Hive configuration completed"
}

# Format HDFS
format_hdfs() {
    info "Formatting HDFS NameNode..."
    
    # Check if namenode directory is empty to prevent accidental re-formatting
    if [ -d "$DATA_DIR/name" ] && [ "$(ls -A "$DATA_DIR/name" 2>/dev/null)" ]; then
        warning "NameNode directory already contains data"
        read -p "Format anyway? This will ERASE all HDFS data (y/n): " -r choice
        if [[ ! $choice =~ ^[Yy]$ ]]; then
            info "Skipping HDFS format"
            return 0
        fi
    fi
    
    # Format the namenode
    if su - "$CURRENT_USER" -c "export JAVA_HOME=$JAVA_HOME && $HADOOP_HOME/bin/hdfs namenode -format -force" >> "$LOG_FILE" 2>&1; then
        success "HDFS formatted successfully"
    else
        error "HDFS format failed. Check $LOG_FILE for details."
        exit 1
    fi
}

# Start Hadoop services
start_hadoop() {
    info "Starting Hadoop services..."
    
    # Stop any running services first
    stop_hadoop > /dev/null 2>&1 || true

    export JAVA_HOME="$JAVA_HOME"
    
    # Start HDFS
    if "$HADOOP_HOME/sbin/start-dfs.sh" >> "$LOG_FILE" 2>&1; then
        success "HDFS services started"
    else
        error "Failed to start HDFS services. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Start YARN
    if "$HADOOP_HOME/sbin/start-yarn.sh" >> "$LOG_FILE" 2>&1; then
        success "YARN services started"
    else
        warning "Failed to start YARN services. YARN may not be needed for basic Hive usage."
    fi
    
    # Verify services are running
    info "Verifying Hadoop processes..."
    sleep 5
    running_processes=$(jps | grep -E 'NameNode|DataNode|ResourceManager|NodeManager' | wc -l)
    
    if [ "$running_processes" -ge 2 ]; then
        success "Hadoop services are running"
        jps | grep -v Jps
    else
        warning "Some Hadoop services may not be running. Check with 'jps' command."
    fi
}


# Stop Hadoop services
stop_hadoop() {
    info "Stopping Hadoop services..."
    
    export JAVA_HOME="$JAVA_HOME"
    
    # Stop YARN
    "$HADOOP_HOME/sbin/stop-yarn.sh" >> "$LOG_FILE" 2>&1 || true
    
    # Stop HDFS
    "$HADOOP_HOME/sbin/stop-dfs.sh" >> "$LOG_FILE" 2>&1 || true
    
    success "Hadoop services stopped"
}

# Initialize Hive
initialize_hive() {
    info "Initializing Hive..."
    info "Checking if HDFS is running..."
    if ! jps | grep -q NameNode; then
        error "HDFS is not running. Start Hadoop before setting up Hive."
        exit 1
    fi
    
    # Create Hive directories in HDFS
    su - "$CURRENT_USER" -c "
        export JAVA_HOME=$JAVA_HOME
        export HADOOP_HOME=$HADOOP_HOME
        export PATH=\$PATH:\$HADOOP_HOME/bin
        
        # Check if HDFS is accessible
        if ! hdfs dfs -ls / &>/dev/null; then
            echo 'Error: HDFS is not accessible. Make sure Hadoop services are running.'
            exit 1
        fi
        
        hdfs dfs -mkdir -p /tmp
        hdfs dfs -chmod g+w /tmp
        hdfs dfs -mkdir -p /user/hive/warehouse
        hdfs dfs -chmod g+w /user/hive/warehouse
    " >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        error "Failed to create Hive directories in HDFS. Check $LOG_FILE for details."
        exit 1
    fi
    
    # Check if the Hive metastore already exists
    if [ -d "$HIVE_HOME/metastore_db" ]; then
        warning "Existing Hive metastore found. Deleting it..."
        rm -rf "$HIVE_HOME/metastore_db"
        success "Old Hive metastore removed."
    fi

    # Initialize Hive metastore
    info "Initializing Hive metastore..."
    if su - "$CURRENT_USER" -c "
        export JAVA_HOME=$JAVA_HOME
        export HADOOP_HOME=$HADOOP_HOME
        export HIVE_HOME=$HIVE_HOME
        export PATH=\$PATH:\$HADOOP_HOME/bin:\$HIVE_HOME/bin
        
        $HIVE_HOME/bin/schematool -dbType derby -initSchema
    " >> "$LOG_FILE" 2>&1; then
        success "Hive metastore initialized"
    else
        error "Failed to initialize Hive metastore. Check $LOG_FILE for details."
        exit 1
    fi
}

# Start Hive services
start_hive() {
    info "Starting Hive services..."
    
    # Start Hive Metastore
    su - "$CURRENT_USER" -c "
        export JAVA_HOME=$JAVA_HOME
        export HADOOP_HOME=$HADOOP_HOME
        export HIVE_HOME=$HIVE_HOME
        export PATH=\$PATH:\$HADOOP_HOME/bin:\$HIVE_HOME/bin
        
        nohup $HIVE_HOME/bin/hive --service metastore > $USER_HOME/hive-metastore.log 2>&1 &
    "
    
    # Start HiveServer2
    su - "$CURRENT_USER" -c "
        export JAVA_HOME=$JAVA_HOME
        export HADOOP_HOME=$HADOOP_HOME
        export HIVE_HOME=$HIVE_HOME
        export PATH=\$PATH:\$HADOOP_HOME/bin:\$HIVE_HOME/bin
        
        nohup $HIVE_HOME/bin/hiveserver2 > $USER_HOME/hiveserver2.log 2>&1 &
    "
    
    sleep 5
    
    # Check if Hive processes are running
    hive_pids=$(pgrep -f "org.apache.hadoop.hive")
    if [ -n "$hive_pids" ]; then
        success "Hive services started"
    else
        warning "Hive services may not have started properly. Check logs in $USER_HOME/hive-*.log"
    fi
}

#check pig installation
verify_pig_installation() {
    info "Verifying Pig installation..."
    
    # Check if Pig executable exists
    if [ ! -f "$INSTALL_DIR/pig-$PIG_VERSION/bin/pig" ]; then
        error "Pig executable not found in expected location"
        return 1
    fi
    
    # Try to get Pig version
    local pig_version_output
    pig_version_output=$("$INSTALL_DIR/pig-$PIG_VERSION/bin/pig" -version 2>&1)
    
    if [ $? -eq 0 ]; then
        success "Pig $PIG_VERSION installed successfully"
        echo "$pig_version_output"
        return 0
    else
        error "Unable to verify Pig installation"
        return 1
    fi
}


# Setup environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Create backup of .bashrc
    backup_file "$USER_HOME/.bashrc"
    
    # Add environment variables to .bashrc if not already present
    if ! grep -q "HADOOP_HOME=$HADOOP_HOME" "$USER_HOME/.bashrc"; then
        cat <<EOL >> "$USER_HOME/.bashrc"

# Hadoop and Hive environment variables
export HADOOP_HOME=$HADOOP_HOME
export HIVE_HOME=$HIVE_HOME
export JAVA_HOME=$JAVA_HOME
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$HIVE_HOME/bin
EOL
        success "Environment variables added to .bashrc"
    else
        info "Environment variables already present in .bashrc"
    fi
    
    # Create convenient aliases for common operations
    if ! grep -q "# Hadoop and Hive aliases" "$USER_HOME/.bashrc"; then
        cat <<EOL >> "$USER_HOME/.bashrc"

# Hadoop and Hive aliases
alias hstart='$HADOOP_HOME/sbin/start-dfs.sh && $HADOOP_HOME/sbin/start-yarn.sh'
alias hstop='$HADOOP_HOME/sbin/stop-yarn.sh && $HADOOP_HOME/sbin/stop-dfs.sh'
alias hstatus='jps | grep -v Jps'
EOL
        success "Convenient aliases added to .bashrc"
    fi
info "Setting up Pig environment variables..."
cat <<EOL >> "$USER_HOME/.bashrc"

# Pig environment variables
export PIG_HOME=$INSTALL_DIR/pig-$PIG_VERSION
export PATH=\$PATH:\$PIG_HOME/bin
EOL
source "$USER_HOME/.bashrc"
success "Pig environment variables added!"

    
    # Source .bashrc to make variables available immediately
    source "$USER_HOME/.bashrc" 2>/dev/null || true
}

# Create a script to check status and manage services
create_management_script() {
    info "Creating management script..."
    
    MGMT_SCRIPT="$USER_HOME/manage-hadoop-hive.sh"
    
    cat <<EOF > "$MGMT_SCRIPT"
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Environment settings
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HIVE_HOME=$HIVE_HOME
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$HIVE_HOME/bin

# Function to check status
status() {
    echo -e "${BLUE}Checking Hadoop and Hive services...${NC}"
    
    # Check HDFS status
    echo -e "${YELLOW}HDFS Status:${NC}"
    if jps | grep -q NameNode; then
        echo -e "${GREEN}NameNode is running${NC}"
    else
        echo -e "${RED}NameNode is not running${NC}"
    fi
    
    if jps | grep -q DataNode; then
        echo -e "${GREEN}DataNode is running${NC}"
    else
        echo -e "${RED}DataNode is not running${NC}"
    fi
    
    # Check YARN status
    echo -e "${YELLOW}YARN Status:${NC}"
    if jps | grep -q ResourceManager; then
        echo -e "${GREEN}ResourceManager is running${NC}"
    else
        echo -e "${RED}ResourceManager is not running${NC}"
    fi
    
    if jps | grep -q NodeManager; then
        echo -e "${GREEN}NodeManager is running${NC}"
    else
        echo -e "${RED}NodeManager is not running${NC}"
    fi
    
    # Check Hive status
    echo -e "${YELLOW}Hive Status:${NC}"
    if pgrep -f "org.apache.hadoop.hive.metastore" > /dev/null; then
        echo -e "${GREEN}Hive Metastore is running${NC}"
    else
        echo -e "${RED}Hive Metastore is not running${NC}"
    fi
    
    if pgrep -f "org.apache.hive.service.server.HiveServer2" > /dev/null; then
        echo -e "${GREEN}HiveServer2 is running${NC}"
    else
        echo -e "${RED}HiveServer2 is not running${NC}"
    fi
    
    # List all Java processes
    echo -e "${YELLOW}All Java processes:${NC}"
    jps
}

# Function to start all services
start_all() {
    echo -e "${BLUE}Starting Hadoop and Hive services...${NC}"
    
    # Start Hadoop
    echo -e "${YELLOW}Starting HDFS...${NC}"
    $HADOOP_HOME/sbin/start-dfs.sh
    
    echo -e "${YELLOW}Starting YARN...${NC}"
    $HADOOP_HOME/sbin/start-yarn.sh
    
    # Start Hive services
    echo -e "${YELLOW}Starting Hive Metastore...${NC}"
    nohup $HIVE_HOME/bin/hive --service metastore > $USER_HOME/hive-metastore.log 2>&1 &
    
    echo -e "${YELLOW}Starting HiveServer2...${NC}"
    nohup $HIVE_HOME/bin/hiveserver2 > $USER_HOME/hiveserver2.log 2>&1 &
    
    echo -e "${GREEN}All services started${NC}"
    sleep 2
    status
}

# Function to stop all services
stop_all() {
    echo -e "${BLUE}Stopping Hadoop and Hive services...${NC}"
    
    # Stop Hive services first
    echo -e "${YELLOW}Stopping Hive services...${NC}"
    pkill -f "org.apache.hadoop.hive" || echo -e "${RED}No Hive processes found${NC}"
    
    # Stop Hadoop services
    echo -e "${YELLOW}Stopping YARN...${NC}"
    $HADOOP_HOME/sbin/stop-yarn.sh
    
    echo -e "${YELLOW}Stopping HDFS...${NC}"
    $HADOOP_HOME/sbin/stop-dfs.sh
    
    echo -e "${GREEN}All services stopped${NC}"
}

# Function to display help
show_help() {
    echo -e "${BLUE}Hadoop & Hive Management Script${NC}"
    echo "Usage: \$0 [command]"
    echo ""
    echo "Commands:"
    echo "  start    - Start Hadoop and Hive services"
    echo "  stop     - Stop Hadoop and Hive services"
    echo "  status   - Check the status of all services"
    echo "  restart  - Restart all services"
    echo "  help     - Show this help message"
}

# Main logic
case "\$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 5
        start_all
        ;;
    status)
        status
        ;;
    *)
        show_help
        ;;
esac
EOF
    
    # Make the script executable
    chmod +x "$MGMT_SCRIPT"
    chown "$CURRENT_USER:$CURRENT_USER" "$MGMT_SCRIPT"
    
    success "Management script created: $MGMT_SCRIPT"
    info "You can manage services with: $MGMT_SCRIPT [start|stop|restart|status]"
}

# Show installation summary
show_summary() {
    # Clear screen for a clean display
    clear

    # Function to create a centered header
    print_centered() {
        local text="$1"
        local color="${2:-\033[0m}"
        local width=80
        printf "${color}"
        printf "%*s\n" $width | tr ' ' '='
        printf "%*s\n" $(((${#text}+width)/2)) "$text"
        printf "%*s\n" $width | tr ' ' '='
        printf "\033[0m"
    }

    # Color definitions
    local HEADER_COLOR='\033[1;34m'  # Bold Blue
    local SUCCESS_COLOR='\033[1;32m' # Bold Green
    local WARN_COLOR='\033[1;33m'    # Bold Yellow
    local INFO_COLOR='\033[1;36m'    # Bold Cyan
    local RESET_COLOR='\033[0m'

  
    echo -e "${HEADER_COLOR}"
    cat <<'EOF'
            ╔════════════════════════╗
            ║    AUTHOR: YOGESH M    ║
            ╚════════════════════════╝
 ██░ ██  ▄▄▄       ▓█████▄  ▒█████   ▒█████  ██▓███   
▓██░ ██▒▒████▄     ▒██▀ ██▌▒██▒  ██▒▒██▒  ██▒▓██░  ██▒
▒██▀▀██░▒██  ▀█▄   ░██   █▌▒██░  ██▒▒██░  ██▒▓██░ ██▓▒
░▓█ ░██ ░██▄▄▄▄██  ░▓█▄   ▌▒██   ██░▒██   ██░▒██▄█▓▒ ▒
░▓█▒░██▓ ▓█   ▓██▒░▒████▓ ░ ████▓▒░░ ████▓▒░▒██▒ ░  ░
 ▒ ░░▒░▒ ▒▒   ▓▒█░ ▒▒▓  ▓▒░ ▒░▒░▒░ ░ ▒░▒░▒░ ▒▓▒░ ░  ░
 ▒ ░▒░ ░  ▒   ▒▒ ░ ░ ▒  ▒░  ░ ▒ ▒░   ░ ▒ ▒░ ░░▒░ ░  ░
 ░  ░░ ░  ░   ▒    ░ ░  ░░ ░ ░ ░ ▒  ░ ░ ░ ▒  ░░░ ░  ░
 ░  ░  ░      ░  ░   ░        ░ ░      ░ ░    ░     
                 ░  Big Data Ecosystem Setup       
EOF
    echo -e "${RESET_COLOR}"

    # Installation Overview
    print_centered "🎉 Installation Complete 🎉" "${SUCCESS_COLOR}"
    echo ""

    # Detailed Installation Information
    echo -e "${INFO_COLOR}📦 Software Versions:${RESET_COLOR}"
    printf "  %-20s: ${SUCCESS_COLOR}%s${RESET_COLOR}\n" "Hadoop" "$HADOOP_VERSION"
    printf "  %-20s: ${SUCCESS_COLOR}%s${RESET_COLOR}\n" "Hive" "$HIVE_VERSION"
    printf "  %-20s: ${SUCCESS_COLOR}%s${RESET_COLOR}\n" "Pig" "$PIG_VERSION"
    printf "  %-20s: ${SUCCESS_COLOR}%s${RESET_COLOR}\n" "Java" "$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')"
    echo ""

    # Paths and Locations
    echo -e "${INFO_COLOR}📂 Installation Paths:${RESET_COLOR}"
    printf "  %-20s: %s\n" "Install Directory" "$INSTALL_DIR"
    printf "  %-20s: %s\n" "Data Directory" "$DATA_DIR"
    printf "  %-20s: %s\n" "Log File" "$LOG_FILE"
    echo ""

    # Service Management
    print_centered "🛠️ Service Management 🛠️" "${WARN_COLOR}"
    echo -e "\n${INFO_COLOR}Quick Commands:${RESET_COLOR}"
    echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Start Services:   ${HEADER_COLOR}~/manage-hadoop-hive.sh start${RESET_COLOR}"
    echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Stop Services:    ${HEADER_COLOR}~/manage-hadoop-hive.sh stop${RESET_COLOR}"
    echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Check Status:     ${HEADER_COLOR}~/manage-hadoop-hive.sh status${RESET_COLOR}"
    echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Restart Services: ${HEADER_COLOR}~/manage-hadoop-hive.sh restart${RESET_COLOR}"
    echo ""

    # Pig Specific Section
    print_centered "🐷 Pig Information 🐷" "${INFO_COLOR}"
    echo -e "\n${INFO_COLOR}Pig Details:${RESET_COLOR}"
    
    # Try to get Pig version
    local pig_version_info
    if pig_version_info=$("$INSTALL_DIR/pig-$PIG_VERSION/bin/pig" -version 2>&1); then
        echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Version:        ${SUCCESS_COLOR}$PIG_VERSION${RESET_COLOR}"
        echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Installation:   ${SUCCESS_COLOR}Successful${RESET_COLOR}"
        echo -e "  ${SUCCESS_COLOR}→${RESET_COLOR} Home Directory: ${HEADER_COLOR}$INSTALL_DIR/pig-$PIG_VERSION${RESET_COLOR}"
        
        # Provide some basic Pig usage information
        echo -e "\n${WARN_COLOR}Pig Quick Start:${RESET_COLOR}"
        echo -e "  • Launch Pig interactive mode: ${INFO_COLOR}pig${RESET_COLOR}"
        echo -e "  • Run a Pig script: ${INFO_COLOR}pig -f your_script.pig${RESET_COLOR}"
        echo -e "  • Execute Pig in local mode: ${INFO_COLOR}pig -x local${RESET_COLOR}"
    else
        echo -e "  ${WARN_COLOR}→ Pig Installation Status: Verification Failed${RESET_COLOR}"
    fi
    echo ""
    # Recommended Next Steps
    print_centered "🚀 Next Steps 🚀" "${SUCCESS_COLOR}"
    echo -e "\n${WARN_COLOR}Recommended Actions:${RESET_COLOR}"
    echo -e "  1. ${INFO_COLOR}Reload Environment:${RESET_COLOR}   source ~/.bashrc"
    echo -e "  2. ${INFO_COLOR}Verify Services:${RESET_COLOR}      ~/manage-hadoop-hive.sh status"
    echo -e "  3. ${INFO_COLOR}First Test:${RESET_COLOR}           Run example Hive/Hadoop scripts"
    echo ""

    # Troubleshooting Section
    print_centered "🔍 Troubleshooting 🔍" "${WARN_COLOR}"
    echo -e "\n${WARN_COLOR}Debugging Resources:${RESET_COLOR}"
    echo -e "  • Main Log File:     ${HEADER_COLOR}$LOG_FILE${RESET_COLOR}"
    echo -e "  • Hadoop Logs:       ${HEADER_COLOR}$HADOOP_HOME/logs/${RESET_COLOR}"
    echo -e "  • Hive Logs:         ${HEADER_COLOR}$HIVE_HOME/logs/${RESET_COLOR}"
    echo ""

    # Final Information and Credits
    print_centered "💡 Additional Information 💡" "${INFO_COLOR}"
    echo -e "\n${SUCCESS_COLOR}Created by:${RESET_COLOR} Yogesh M"
    echo -e "${SUCCESS_COLOR}GitHub:${RESET_COLOR}     https://github.com/cypherix"
    echo -e "${SUCCESS_COLOR}Support:${RESET_COLOR}    https://buymeacoffee.com/cypherix"
    echo ""

    # Closing Motivational Message
    print_centered "🎊 Big Data Awaits Your Exploration! 🎊" "${HEADER_COLOR}"
}

main() {
    # Print welcome message
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE} Hadoop, Hive, and Pig Setup Script for WSL Ubuntu 20.04${NC}"
    echo -e "${YELLOW}💻 Author:  Yogesh M${NC}"
    echo -e "${YELLOW}📌 GitHub:  ${BLUE}https://github.com/cypherix${NC}"
    echo -e "${YELLOW}🔖 License:  ${GREEN}MIT${NC}"
    echo -e "${YELLOW}📌 Version:  ${GREEN}1.0${NC}"
    echo -e "${YELLOW}☕ Support:  ${GREEN}https://buymeacoffee.com/cypherix${NC}"
    echo -e "${BLUE}======================================================${NC}"

    # Initialize log file
    echo "# Hadoop,Hive and PigSetup Log - $(date)" > "$LOG_FILE"
    
    # Get current user
    CURRENT_USER=$(get_actual_user)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    # # Run setup steps
    # check_sudo
    check_disk_space
    wsl_checks
    check_java
    setup_environment
    setup_ssh
    
    # Install Hadoop
    download_and_install "Hadoop" "$HADOOP_VERSION" \
        "https://downloads.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz" \
        "hadoop-$HADOOP_VERSION.tar.gz" \
        "hadoop-$HADOOP_VERSION"
    
    # Configure Hadoop
    ensure_directory "$DATA_DIR" "$CURRENT_USER"
    ensure_directory "$DATA_DIR/name" "$CURRENT_USER"
    ensure_directory "$DATA_DIR/data" "$CURRENT_USER"
    ensure_directory "$DATA_DIR/tmp" "$CURRENT_USER"
    configure_hadoop "$CURRENT_USER"
    format_hdfs
    start_hadoop
    
    # Install Hive
    download_and_install "Hive" "$HIVE_VERSION" \
        "https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/apache-hive-$HIVE_VERSION-bin.tar.gz" \
        "apache-hive-$HIVE_VERSION-bin.tar.gz" \
        "apache-hive-$HIVE_VERSION-bin"
    
    # Configure and start Hive
    configure_hive
    initialize_hive
    start_hive
    
    #Install Pig
    download_and_install "Pig" "$PIG_VERSION" \
        "https://archive.apache.org/dist/pig/pig-$PIG_VERSION/pig-$PIG_VERSION.tar.gz" \
        "pig-$PIG_VERSION.tar.gz" \
        "pig-$PIG_VERSION"
    verify_pig_installation
    
    #create_management_script
    
    # Show summary
    show_summary
}
main
exit 0