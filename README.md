This script automates the installation and configuration of Apache Hadoop and Apache Hive on WSL Ubuntu 20.04. It's designed to provide a smooth setup experience with comprehensive error handling and user-friendly features.
## Overview

This script sets up:

- Apache Hadoop 3.3.4
- Apache Hive 4.0.0
- Required dependencies and configurations
- Helper scripts for management

The installation is optimized for WSL (Windows Subsystem for Linux) Ubuntu 20.04, with specific configurations to ensure compatibility and performance in this environment.

## Prerequisites

- WSL Ubuntu 20.04 installed
- Sudo privileges
- At least 5GB of free disk space
- Internet connection for downloading packages

## Installation

### Quick Start

1. Download the script:
    
    ```bash
    wget https://raw.githubusercontent.com/yourusername/hadoop-hive-setup/main/install-hadoop.sh
    ```
    
2. Make it executable:
    
    ```bash
    chmod +x install-hadoop.sh
    ```
    
3. Run with sudo:
    
    ```bash
    sudo ./install-hadoop.sh
    ```
    

### What Gets Installed

- Java OpenJDK 8
- SSH server
- Apache Hadoop 3.3.4
- Apache Hive 4.0.0
- Configuration files
- Environment variables in `.bashrc`
- Helper scripts for management and testing

### Installation Directory Structure

```
/opt/
├── hadoop-3.3.4/
├── apache-hive-4.0.0-bin/
└── hadoop_data/
    ├── name/    # NameNode data
    ├── data/    # DataNode data
    └── tmp/     # Temporary files
```

## Configuration

### Environment Variables

The script adds the following to your `.bashrc`:

```bash
# Hadoop and Hive environment variables
export HADOOP_HOME=/opt/hadoop-3.3.4
export HIVE_HOME=/opt/apache-hive-4.0.0-bin
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HIVE_HOME/bin
```

### Hadoop Configuration

Key configurations set by the script:

- Single-node setup (replication factor: 1)
- HDFS configured at `hdfs://localhost:9000`
- Permissions disabled for testing purposes
- YARN configured for MapReduce jobs

### Hive Configuration

- Derby database for metastore
- Warehouse directory: `/user/hive/warehouse`
- Schema verification disabled for compatibility

### WSL-Specific Settings

The script creates a `.wslconfig` file with recommended settings:

```
[wsl2]
memory=4GB
processors=2
swap=2GB
```

## Management

### Management Script

The installation creates a management script at `~/manage-hadoop-hive.sh` with the following commands:

```bash
# Check status of all services
~/manage-hadoop-hive.sh status

# Start all services
~/manage-hadoop-hive.sh start

# Stop all services
~/manage-hadoop-hive.sh stop

# Restart all services
~/manage-hadoop-hive.sh restart
```

### Convenience Aliases

The script adds these aliases to your `.bashrc`:

```bash
alias hstart='$HADOOP_HOME/sbin/start-dfs.sh && $HADOOP_HOME/sbin/start-yarn.sh'
alias hstop='$HADOOP_HOME/sbin/stop-yarn.sh && $HADOOP_HOME/sbin/stop-dfs.sh'
alias hstatus='jps | grep -v Jps'
```

## Examples

### Sample Data and Scripts

The installation creates example files in `~/hadoop-hive-examples/`:

- `test-hive.sh`: Creates a sample table and runs a query
- Sample CSV data with employee records
- HQL script for creating a table and loading data

### Running the Example

```bash
# Make sure Hadoop and Hive services are running
~/manage-hadoop-hive.sh status

# If needed, start the services
~/manage-hadoop-hive.sh start

# Run the example
~/hadoop-hive-examples/test-hive.sh
```

## Troubleshooting

### Log Files

- Installation log: `hadoop_hive_setup_YYYYMMDD_HHMMSS.log` in the current directory
- Hive logs: `~/hive-metastore.log` and `~/hiveserver2.log`
- Hadoop logs: `/opt/hadoop-3.3.4/logs/`

### Common Issues

1. **SSH Connection Issues**:
    
    ```bash
    sudo service ssh restart
    ssh localhost
    ```
    
2. **Java Version Problems**:
    
    ```bash
    java -version
    sudo update-alternatives --config java
    ```
    
3. **Permission Problems**:
    
    ```bash
    sudo chown -R $USER:$USER /opt/hadoop-3.3.4
    sudo chown -R $USER:$USER /opt/apache-hive-4.0.0-bin
    sudo chown -R $USER:$USER /opt/hadoop_data
    ```
    
4. **HDFS Not Starting**:
    
    ```bash
    # Check logs
    cat /opt/hadoop-3.3.4/logs/hadoop-*-namenode-*.log
    
    # Reformat namenode (caution: erases data)
    hdfs namenode -format
    ```
    
5. **WSL Network Issues**: From PowerShell (as Administrator):
    
    ```
    wsl --shutdown
    wsl
    ```
    

## Advanced Configuration

### Modifying Hadoop Settings

Key configuration files:

- `/opt/hadoop-3.3.4/etc/hadoop/core-site.xml`
- `/opt/hadoop-3.3.4/etc/hadoop/hdfs-site.xml`
- `/opt/hadoop-3.3.4/etc/hadoop/mapred-site.xml`
- `/opt/hadoop-3.3.4/etc/hadoop/yarn-site.xml`

### Modifying Hive Settings

- `/opt/apache-hive-4.0.0-bin/conf/hive-site.xml`

### Increasing Resources

For larger datasets, edit your `.wslconfig` file in Windows user directory:

```
[wsl2]
memory=8GB
processors=4
swap=4GB
```

### Securing Your Installation

The default installation is optimized for learning and testing. For production:

1. Enable Hadoop security settings:
    
    ```xml
    <property>
      <name>dfs.permissions.enabled</name>
      <value>true</value>
    </property>
    ```
    
2. Configure proper user permissions in HDFS
    
3. Set up proper authentication for Hive
    

## License

This script is provided under the [MIT License](https://claude.ai/chat/LICENSE).

## Acknowledgments

- Apache Hadoop team
- Apache Hive team
- WSL team at Microsoft

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
