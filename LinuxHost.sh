#!/bin/bash

# Variables to store the checklist status
CHECKLIST=()

# Prompt for SSH username
read -p "Enter the SSH username used for Software: " ssh_user

# Function to check resource requirements
check_resources() {
    echo "Checking resource requirements..."

    # Check free memory using basic method
    free_memory=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    free_memory=$((free_memory / 1024)) # Convert to MB
    if [ $? -ne 0 ]; then
        echo "Failed to check free memory."
        CHECKLIST+=("Free memory check: Failed")
        return 1
    fi

    if [ $free_memory -ge 500 ]; then
        echo "Free memory: Passed ($free_memory MB available)"
        CHECKLIST+=("Free memory: Passed")
    else
        echo "Free memory: Failed ($free_memory MB available)"
        CHECKLIST+=("Free memory: Failed ($free_memory MB available)")
    fi

    # Check CPU using basic method
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/")
    if [ $? -ne 0 ]; then
        echo "Failed to check CPU idle percentage."
        CHECKLIST+=("CPU idle check: Failed")
        return 1
    fi

    cpu_free=$(echo "100 - $cpu_idle" | awk '{print $1}')
    if [ $? -ne 0 ]; then
        echo "Failed to calculate CPU free percentage."
        CHECKLIST+=("CPU free calculation: Failed")
        return 1
    fi

    cpu_cores=$(nproc)
    if [ $? -ne 0 ]; then
        echo "Failed to check CPU cores."
        CHECKLIST+=("CPU cores check: Failed")
        return 1
    fi

    echo "CPU Idle: $cpu_idle%"
    echo "CPU Free: $cpu_free%"

    if [ $cpu_cores -ge 2 ] && (( $(echo "$cpu_free >= 0.25" | bc -l) )); then
        echo "CPU: Passed ($cpu_cores cores, $cpu_free% free)"
        CHECKLIST+=("CPU: Passed")
    else
        echo "CPU: Failed ($cpu_cores cores, $cpu_free% free)")
        CHECKLIST+=("CPU: Failed ($cpu_cores cores, $cpu_free% free)")
    fi   

    # Check /home/ space using basic method
    home_free=$(df -m /home | awk 'NR==2 {print $4}')
    if [ $? -ne 0 ]; then
        echo "Failed to check /home/ space."
        CHECKLIST+=("/home/ space check: Failed")
        return 1
    fi

    if [ $home_free -gt 500 ]; then
        echo "/home/ space: Passed ($home_free MB available)"
        CHECKLIST+=("/home/ space: Passed")
    else
        echo "/home/ space: Failed ($home_free MB available)"
        CHECKLIST+=("/home/ space: Failed ($home_free MB available)")
    fi

    # Check /opt/ space using basic method
    opt_free=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ $? -ne 0 ]; then
        echo "Failed to check /opt/ space."
        CHECKLIST+=("/opt/ space check: Failed")
        return 1
    fi

    if [ $opt_free -gt 2000 ]; then
        echo "/opt/ space: Passed ($opt_free MB available)"
        CHECKLIST+=("/opt/ space: Passed")
    else
        echo "/opt/ space: Failed ($opt_free MB available)"
        CHECKLIST+=("/opt/ space: Failed ($opt_free MB available)")
    fi
}

# Function to check if user is in sudoers list
check_sudoers() {
    echo "Checking sudoers configuration..."

    # Check if the user exists
    if ! id "$ssh_user" &>/dev/null; then
        echo "User $ssh_user does not exist."
        CHECKLIST+=("User existence check: Failed")
        return 1
    fi

    sudo_group=$(id -nG "$ssh_user" | grep -w "sudo")
    if [ $? -ne 0 ]; then
        echo "Failed to check if user is in sudo group."
        CHECKLIST+=("Sudo group check: Failed")
        return 1
    fi

    if [ -z "$sudo_group" ]; then
        echo "User $ssh_user is not in the sudo group."
        CHECKLIST+=("User sudo group membership: Failed")
    else
        echo "User $ssh_user is in the sudo group."
        CHECKLIST+=("User sudo group membership: Passed")
    fi

    # Update sudoers file
    sudoers_entry="$ssh_user ALL=(ALL) NOPASSWD:/opt/.ch-tools/*/*/*, /opt/.ch-tools/*/*, /bin/mkdir, /bin/echo, /bin/chmod 755 /opt/.ch-tools/*, /bin/chmod 755 /home/$ssh_user/chcmd, /bin/chmod -R 755 /opt/.ch-tools, /bin/chmod -R 755 /home/$ssh_user/.ch-tools, /bin/chown $ssh_user\: /opt/.ch-tools/*, /bin/chown -R $ssh_user\: /home/$ssh_user/chcmd, /bin/chown -R $ssh_user\: /opt/.ch-tools, /bin/chown -R $ssh_user\: /home/$ssh_user/.ch-tools"

    if ! sudo grep -qF "$sudoers_entry" /etc/sudoers; then
        echo "Adding sudoers entry..."
        echo "$sudoers_entry" | sudo EDITOR='tee -a' visudo
        if [ $? -eq 0 ]; then
            echo "Sudoers entry added successfully."
            CHECKLIST+=("Sudoers entry: Passed")
        else
            echo "Failed to add sudoers entry."
            CHECKLIST+=("Sudoers entry: Failed")
        fi
    else
        echo "Sudoers entry already exists."
        CHECKLIST+=("Sudoers entry: Passed")
    fi

    # Disable requiretty for the user
    if ! sudo grep -q "Defaults:$ssh_user    !requiretty" /etc/sudoers; then
        echo "Disabling requiretty for $ssh_user..."
        echo "Defaults:$ssh_user    !requiretty" | sudo EDITOR='tee -a' visudo
        if [ $? -eq 0 ]; then
            echo "requiretty disabled for $ssh_user."
            CHECKLIST+=("requiretty disable: Passed")
        else
            echo "Failed to disable requiretty for $ssh_user."
            CHECKLIST+=("requiretty disable: Failed")
        fi
    else
        echo "requiretty is already disabled for $ssh_user."
        CHECKLIST+=("requiretty disable: Passed")
    fi
}

# Function to check if SSHD is running
check_sshd() {
    echo "Checking if SSHD is running..."
    sshd_status=$(ps ax | grep -v grep | grep sshd)
    if [ -z "$sshd_status" ]; then
        echo "SSHD is not running."
        CHECKLIST+=("SSHD running check: Failed")
    else
        echo "SSHD is running."
        CHECKLIST+=("SSHD running check: Passed")
    fi
}

# Function to ensure port 443 is open
check_port_443() {
    echo "Checking if port 443 is open..."

    # Check if port 443 is open
    if ss -tuln | grep -q ':443 '; then
        echo "Port 443 is open."
        CHECKLIST+=("Port 443 open check: Passed")
    else
        echo "Port 443 is not open. Enabling port 443..."

        # Check if iptables is available
        if command -v iptables &> /dev/null; then
            sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
            sudo iptables-save > /etc/iptables/rules.v4
            if [ $? -eq 0 ]; then
                echo "Port 443 has been enabled."
                CHECKLIST+=("Port 443 enable: Passed")
            else
                echo "Failed to enable port 443."
                CHECKLIST+=("Port 443 enable: Failed")
            fi
        else
            echo "iptables is not available. Cannot enable port 443."
            CHECKLIST+=("Port 443 enable: Failed (iptables not available)")
        fi
    fi

    # Ensure iptables rules are persistent
    if command -v iptables &> /dev/null; then
        sudo iptables-save > /etc/iptables/rules.v4
        if [ $? -eq 0 ]; then
            echo "Firewall rules saved."
            CHECKLIST+=("Firewall rules save: Passed")
        else
            echo "Failed to save firewall rules."
            CHECKLIST+=("Firewall rules save: Failed")
        fi
    else
        CHECKLIST+=("Firewall rules save: Failed (iptables not available)")
    fi
}

# Main script execution
check_resources
check_sudoers
check_sshd
check_port_443

# Display checklist
echo "Checklist for requirements:"
for item in "${CHECKLIST[@]}"; do
    echo "- $item"
done
