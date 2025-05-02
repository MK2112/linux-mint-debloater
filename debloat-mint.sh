#!/bin/bash
# Version: 1.0.1

# Check for required dependencies
for dep in zenity timeshift ufw; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo -e "\033[1;31m[ERROR]\033[0m Required dependency '$dep' not installed. Please install, then re-run this script."
        exit 1
    fi
done

# Color codes
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

# Self-Update Helper
REPO_URL="https://raw.githubusercontent.com/MK2112/linux-mint-debloater/main/debloat-mint.sh"
LOCAL_SCRIPT="$0"

# Get version from script
get_version() {
    grep '^# Version:' "$1" | head -n1 | awk '{print $3}'
}

# Logging
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a debloat.log
}

# Color Functions
info()    { echo -e "${CYAN}[i] $1${RESET}"; log "INFO: $1"; }
success() { echo -e "${GREEN}[+] $1${RESET}"; log "SUCCESS: $1"; }
warn()    { echo -e "${YELLOW}[~] $1${RESET}"; log "WARN: $1"; }
error()   { echo -e "${RED}[-] $1${RESET}"; log "ERROR: $1"; }

LOCAL_VERSION=$(get_version "$LOCAL_SCRIPT")
REMOTE_VERSION=$(curl -fsSL "$REPO_URL" | grep '^# Version:' | head -n1 | awk '{print $3}')

if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    log "Update available: $LOCAL_VERSION -> $REMOTE_VERSION"
    zenity --question --title="Update Available" --text="A new version ($REMOTE_VERSION) is available.\nUpdate now?" --no-wrap
    if [ $? -eq 0 ]; then
        TMP_UPDATE="/tmp/debloat-mint.sh.update.$$"
        if curl -fsSL "$REPO_URL" -o "$TMP_UPDATE"; then
            # Optionally check if the update is valid (e.g., sanity check for bash header)
            if grep -q '^#!/bin/bash' "$TMP_UPDATE"; then
                cp "$LOCAL_SCRIPT" "$LOCAL_SCRIPT.bak"
                mv "$TMP_UPDATE" "$LOCAL_SCRIPT"
                chmod +x "$LOCAL_SCRIPT"
                log "Script updated to version $REMOTE_VERSION. Please re-run."
                zenity --info --title="Updated" --text="Script updated to $REMOTE_VERSION. Run chmod +x on the new file, then please re-run the script." --no-wrap
                exit 0
            else
                log "Update failed: Downloaded file is not a valid script."
                zenity --error --title="Update Failed" --text="Downloaded file is not a valid script." --no-wrap
                rm -f "$TMP_UPDATE"
            fi
        else
            log "Update failed: Could not download new version."
            zenity --error --title="Update Failed" --text="Could not download new version." --no-wrap
        fi
    else
        log "User chose not to update."
    fi
fi

# Checking privileges
if [ "$EUID" -ne 0 ]; then
	error "Please Run As Root."
  	return 1 2>/dev/null
	exit 1
fi

# Read config
read_config() {
    grep "^$1=" config.txt | cut -d'=' -f2- | tr -d '\r' 2>/dev/null
}

auto_mode=$(read_config "auto")
disable_online_accounts=$(read_config "options/disable_online_accounts")

if [ "$auto_mode" = "true" ]; then
	success "Running In Auto Mode."
	info "Using config.txt settings."
	echo
	create_snapshot=$(read_config "options/create_snapshot")
	debloat=$(read_config "options/debloat")
	portable_use=$(read_config "options/portable_use")
	disable_flatpak=$(read_config "options/disable_flatpak")
	optimize_boot=$(read_config "options/optimize_boot")
	disable_telemetry=$(read_config "options/disable_telemetry")
	configure_firewall=$(read_config "options/configure_firewall")
	harden_ssh=$(read_config "options/harden_ssh")
	update_system=$(read_config "options/update_system")
	install_programs=$(read_config "options/install_programs")
	reboot_system=$(read_config "options/reboot_system")
	remove_duplicates_path=$(read_config "options/remove_duplicates_path")
    services_to_disable=$(read_config "options/services_to_disable")
else
	success "Running In Manual Mode."
	warn "Change value of 'auto' to 'true' in config.txt to enable auto mode."
	echo
fi

# Create Snapshot
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Create Snapshot?" --no-wrap
    if [ $? = 0 ]; then
        create_snapshot="true"
    else
        create_snapshot="false"
    fi
fi

if [ "$create_snapshot" = "true" ]; then
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	timeshift --create --comments "LM Primer ::System Snapshot:: $timestamp" --tags D

	if [ $? -eq 0 ]; then
	  	success "Timeshift Snapshot Created Successfully."
	else
	  	error "Failed To Create Timeshift Snapshot."
	  	return 1 2>/dev/null
		exit 1
	fi
else
	warn "Skipped Snapshot Creation."
fi

# Debloat
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Debloat?" --no-wrap
    if [ $? = 0 ]; then
        debloat="true"
    else
        debloat="false"
    fi
fi

if [ "$debloat" = "true" ]; then
    log "Starting debloat process."
    # Purging these programs (delete from list if program should stay)
    programs=(
        mintwelcome            # Welcome screen
        redshift               # Screen Color adjustment tool for eye strain reduction
        libreoffice-core       # Core components of LibreOffice
        libreoffice-common     # Common files for LibreOffice
        transmission-gtk       # BitTorrent client
        hexchat                # Internet Relay Chat client
        baobab                 # Disk usage analyzer
        seahorse               # GNOME frontend for GnuPG
        thunderbird            # Email and news client
        rhythmbox              # Music player
        pix                    # Image viewer and browser
        simple-scan            # Scanning utility
        drawing                # Drawing application
        gnote                  # Note-taking application
        xreader                # Document viewer
        onboard                # On-screen keyboard
        celluloid              # Video player
        gnome-calendar         # Calendar application
        gnome-contacts         # Contacts manager
        gnome-logs             # Log viewer for the systemd 
        gnome-power-manager    # GNOME desktop Power management tool
        warpinator             # Tool for local network file sharing
    )

    for program in "${programs[@]}"; do
        log "Purging package: $program"
        sudo apt purge "$program" -y | tee -a debloat.log
        if [ $? -eq 0 ]; then
            log "Purged $program successfully."
        else
            log "Failed to purge $program."
        fi
    done

    # Check for orphaned packages
    orphans=$(apt autoremove --dry-run | grep '^  ' | awk '{print $1}')
    if [ -n "$orphans" ]; then
        log "Orphaned packages found: $orphans"
        zenity --question --title="Orphaned Packages" --text="Orphaned packages detected:\n$orphans\n\nRemove them now?" --no-wrap
        if [ $? -eq 0 ]; then
            log "Removing orphaned packages: $orphans"
            sudo apt autoremove -y | tee -a debloat.log
            sudo apt clean | tee -a debloat.log
            success "Orphaned packages removed."
        else
            warn "User chose not to remove orphaned packages."
        fi
    else
        log "No orphaned packages found after debloat."
        sudo apt clean | tee -a debloat.log
    fi
    success "System Debloated."
else
    warn "Skipped System Debloat."
fi

# Portable Optimization
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Prime For Portable Use?" --no-wrap
    if [ $? = 0 ]; then
        portable_use="true"
    else
        portable_use="false"
    fi
fi

if [ "$portable_use" = "true" ]; then
	# TLP, Powertop, ThermalD - Install
 	sudo apt update && sudo apt upgrade -y
	sudo apt install -y tlp powertop thermald
	
	# Thermald - Start
	sudo systemctl enable thermald
	sudo systemctl start thermald

	# TLP - Start
	sudo systemctl enable tlp
	sudo systemctl start tlp
	
	# Powertop - Auto Tune (if running on battery)
	if [ "$(cat /sys/class/power_supply/AC/online)" = "0" ]; then
	sudo powertop --auto-tune
fi

	# TLP - Configuration
	sudo sed -i \
 	-e 's/#TLP_ENABLE=0/TLP_ENABLE=1/' \
	-e 's/#TLP_DEFAULT_MODE=AC/TLP_DEFAULT_MODE=AC/' \
	-e 's/#TLP_PERSISTENT_DEFAULT=0/TLP_PERSISTENT_DEFAULT=0/' \
	-e 's/#CPU_SCALING_GOVERNOR_ON_AC=performance/CPU_SCALING_GOVERNOR_ON_AC=performance/' \
	-e 's/#CPU_SCALING_GOVERNOR_ON_BAT=powersave/CPU_SCALING_GOVERNOR_ON_BAT=powersave/' \
	-e 's/#CPU_ENERGY_PERF_POLICY_ON_AC=performance/CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance/' \
	-e 's/#CPU_ENERGY_PERF_POLICY_ON_BAT=powersave/CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power/' \
	-e 's/#CPU_MIN_PERF_ON_AC=0/CPU_MIN_PERF_ON_AC=0/' \
	-e 's/#CPU_MAX_PERF_ON_AC=100/CPU_MAX_PERF_ON_AC=100/' \
	-e 's/#CPU_MIN_PERF_ON_BAT=0/CPU_MIN_PERF_ON_BAT=0/' \
	-e 's/#CPU_MAX_PERF_ON_BAT=30/CPU_MAX_PERF_ON_BAT=60/' \
	-e 's/#DISK_DEVICES="sda"/DISK_DEVICES="sda"/' \
	-e 's/#DISK_APM_LEVEL_ON_AC="254 254"/DISK_APM_LEVEL_ON_AC="254 254"/' \
	-e 's/#DISK_APM_LEVEL_ON_BAT="128 128"/DISK_APM_LEVEL_ON_BAT="128 128"/' \
	-e 's/#WIFI_PWR_ON_AC=off/WIFI_PWR_ON_AC=off/' \
	-e 's/#WIFI_PWR_ON_BAT=on/WIFI_PWR_ON_BAT=on/' \
	-e 's/#WOL_DISABLE=Y/WOL_DISABLE=Y/' \
	-e 's/#SOUND_POWER_SAVE_ON_AC=0/SOUND_POWER_SAVE_ON_AC=0/' \
	-e 's/#SOUND_POWER_SAVE_ON_BAT=1/SOUND_POWER_SAVE_ON_BAT=1/' \
	-e 's/#RUNTIME_PM_ON_AC=on/RUNTIME_PM_ON_AC=on/' \
	-e 's/#RUNTIME_PM_ON_BAT=auto/RUNTIME_PM_ON_BAT=auto/' \
	/etc/tlp.conf

	# Disable Bluetooth on startup
	BT_CONF_FILE="/etc/bluetooth/main.conf"
	if [ ! -f "$BT_CONF_FILE" ]; then
		error "Bluetooth Config Error: $BT_CONF_FILE Does Not Exist."
		return 1 2>/dev/null
		exit 1
	else
		sed -i 's/^AutoEnable=true/AutoEnable=false/' "$BT_CONF_FILE"
	fi

	if grep -q "^AutoEnable=false" "$BT_CONF_FILE"; then
    	success "Successfully Updated $BT_CONF_FILE. AutoEnable Is Now Set To <False>."
	else
    	error "Updating $BT_CONF_FILE Failed. Check Manually."
	fi

	# Install and configure preload for faster application launch
	sudo apt install -y preload
	sudo systemctl enable preload && sudo systemctl start preload
	sudo apt autoremove -y && sudo apt clean
	success "Successfully Optimized For Portability."
else
	warn "Skipped Optimization For Portability."
fi

# Disable Flatpak
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Disable Flatpak?" --no-wrap
    if [ $? = 0 ]; then
        disable_flatpak="true"
    else
        disable_flatpak="false"
    fi
fi

if [ "$disable_flatpak" = "true" ]; then
	sudo apt purge flatpak
	sudo apt-mark hold flatpak
 	success "Disabled Flatpak."
else
	warn "Skipped Disabling Flatpak."
fi

# Boot Optimization
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Optimize Boot Time?" --no-wrap
    if [ $? = 0 ]; then
        optimize_boot="true"
    else
        optimize_boot="false"
    fi
fi

if [ "$optimize_boot" = "true" ]; then
	# Decrease GRUB timeout
	sudo sed -i 's/GRUB_TIMEOUT=10/GRUB_TIMEOUT=1/' /etc/default/grub
	# Disable GRUB submenu
	sudo sed -i 's/#GRUB_DISABLE_SUBMENU=y/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
	# Disable GRUB Boot Animations
	sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet nosplash"/' /etc/default/grub
	sudo update-grub

	# Reduce tty count used during boot
	sudo sed -i 's/^#NAutoVTs=6/NAutoVTs=2/' /etc/systemd/logind.conf
	# Services start 'more concurrently'
	sudo sed -i 's/#DefaultTimeoutStartSec=90s/DefaultTimeoutStartSec=40s/' /etc/systemd/system.conf
	sudo sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=40s/' /etc/systemd/system.conf
	# Systemd daemon-reload
	sudo systemctl daemon-reload
	
 	success "Boot Optimization Successful."
else
	warn "Skipped Boot Optimization."
fi

# Disable Online Accounts Integration
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Disable Online Accounts Integration?" --no-wrap
    if [ $? = 0 ]; then
        disable_online_accounts="true"
    else
        disable_online_accounts="false"
    fi
fi

if [ "$disable_online_accounts" = "true" ]; then
    info "Disabling GNOME Online Accounts and related integration..."
    # Remove gnome-online-accounts and related packages
    sudo apt purge -y gnome-online-accounts gnome-control-center-data
    # Remove autostart entry if present
    autostart_dir="/etc/xdg/autostart"
    if [ -f "$autostart_dir/gnome-online-accounts-panel.desktop" ]; then
        sudo rm "$autostart_dir/gnome-online-accounts-panel.desktop"
    fi
    # Kill any running goa-daemon
    pkill -f goa-daemon
    success "Online Accounts integration disabled."
else
    warn "Skipped disabling Online Accounts integration."
fi

# Disable Reporting and Telemetry
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Disable Reporting and Telemetry?" --no-wrap
    if [ $? = 0 ]; then
        disable_telemetry="true"
    else
        disable_telemetry="false"
    fi
fi

if [ "$disable_telemetry" = "true" ]; then
	firefox_config=$(find "/home/${SUDO_USER:-$USER}/.mozilla/firefox/" -name "*.default-release" -exec echo {}/prefs.js \;)
    	if [ -f "$firefox_config" ]; then
        	echo 'user_pref("toolkit.telemetry.enabled", false);' >> "$firefox_config"
        	echo 'user_pref("toolkit.telemetry.unified", false);' >> "$firefox_config"
			echo 'user_pref("browser.region.update.enabled", false);' >> "$firefox_config"
			echo 'user_pref("extensions.getAddons.recommended.url", "");' >> "$firefox_config"
        	echo 'user_pref("extensions.getAddons.cache.enabled", false);' >> "$firefox_config"
        	echo 'user_pref("datareporting.healthreport.uploadEnabled", false);' >> "$firefox_config"
        	echo 'user_pref("datareporting.policy.dataSubmissionEnabled", false);' >> "$firefox_config"
			echo 'user_pref("browser.newtabpage.activity-stream.telemetry", false);' >> "$firefox_config"
			echo 'user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);' >> "$firefox_config"
        	echo 'user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);' >> "$firefox_config"
    	else
        	warn "Firefox: Configuration file not found. Not installed or not used."
    	fi

    	thunderbird_config=$(find "/home/${SUDO_USER:-$USER}/.thunderbird/" -name "*.default-esr" -exec echo {}/prefs.js \;)
    	if [ -f "$thunderbird_config" ]; then
        	echo 'user_pref("datareporting.healthreport.uploadEnabled", false);' >> "$thunderbird_config"
        	echo 'user_pref("datareporting.policy.dataSubmissionEnabled", false);' >> "$thunderbird_config"
        	echo 'user_pref("mail.shell.checkDefaultClient", false);' >> "$thunderbird_config"
        	echo 'user_pref("mailnews.start_page.enabled", false);' >> "$thunderbird_config"
    	else
        	warn "Thunderbird: Configuration file not found. Not installed or not used."
    	fi

	chromium_config=$(find "/home/${SUDO_USER:-$USER}/.config/chromium/" -name "Default/Preferences")
	if [ -f "$chromium_config" ]; then
		sed -i 's/"metrics": {/"metrics": {"enabled": false,/' "$chromium_config"
		sed -i 's/"reporting": {/"reporting": {"enabled": false,/' "$chromium_config"
	else
		warn "Chromium: Configuration file not found. Not installed or not used."
	fi	

	# False by default, just making sure
	gsettings set org.gnome.desktop.privacy send-software-usage-stats false
	gsettings set org.gnome.desktop.privacy report-technical-problems false
else
	warn "Skipped Reporting and Telemetry."
fi

# Configure Firewall
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Configure and Enable Firewall?" --no-wrap
    if [ $? = 0 ]; then
        configure_firewall="true"
    else
        configure_firewall="false"
    fi
fi

if [ "$configure_firewall" = "true" ]; then
	if ! command -v ufw &> /dev/null; then
        sudo apt install -y ufw
    else
		sudo ufw --force reset
	fi
	
	# Default rules
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

	# Allow rules
	declare -A ufw_rules=(
		["CUPS (Printer)"]="631"
		["HTTP, HTTPS (TCP)"]="80,443/tcp"
		["HTTP, HTTPS (UDP)"]="80,443/udp"
		["IMAP (Mail)"]="143,993/tcp"
		["SMTP (Mail)"]="465,587/tcp"
		["OpenVPN (TCP)"]="943/tcp"
		["OpenVPN (UDP)"]="1194/udp"
		["SSH"]="22"
		["FTP"]="20,21/tcp"
	)

	for service in "${!ufw_rules[@]}"; do
		sudo ufw allow ${ufw_rules[$service]} || echo "Failed to allow $service (${ufw_rules[$service]})"
	done

    sudo ufw --force enable
    success "Firewall configured and enabled successfully."
else
    warn "Skipped Firewall configuration."
fi

# Harden SSH
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Harden SSH?" --no-wrap
    if [ $? = 0 ]; then
        harden_ssh="true"
    else
        harden_ssh="false"
    fi
fi

# Double confirmation, really make sure you know what you're doing
if [ "$harden_ssh" = "true" ]; then
    zenity --question --text="Are you sure? This will change your SSH configuration and port." --no-wrap
    if [ $? != 0 ]; then
        warn "SSH hardening cancelled by user."
        harden_ssh="false"
    fi
fi

if [ "$harden_ssh" = "true" ]; then
    # Backup SSH config
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
	# Move SSH to port 2222
    sudo sed -i '/^#Port 22/c\Port 2222' /etc/ssh/sshd_config
	# Disable login on root level
    sudo sed -i '/^#PermitRootLogin/c\PermitRootLogin no' /etc/ssh/sshd_config
	# Disable empty passwords
	sudo sed -i '/^#PermitEmptyPasswords/c\PermitEmptyPasswords no' /etc/ssh/sshd_config
	# Disable password authentication (use keys only)
    sudo sed -i '/^#PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config
	# Disable X11 (GUI) forwarding
    sudo sed -i '/^#X11Forwarding/c\X11Forwarding no' /etc/ssh/sshd_config
	# Reduce maximum login attempts to 3
    sudo sed -i '/^#MaxAuthTries/c\MaxAuthTries 3' /etc/ssh/sshd_config
	# Disable TCP and Agent forwarding
    sudo sed -i '/^#AllowTcpForwarding/c\AllowTcpForwarding no' /etc/ssh/sshd_config
    sudo sed -i '/^#AllowAgentForwarding/c\AllowAgentForwarding no' /etc/ssh/sshd_config
    
    # Interval to test connection status
    echo "ClientAliveInterval 300" | sudo tee -a /etc/ssh/sshd_config
	# Intervals missed before disconnect
    echo "ClientAliveCountMax 2" | sudo tee -a /etc/ssh/sshd_config

	# Update firewall rules
	if command -v ufw &> /dev/null; then
		sudo ufw allow 2222
		sudo ufw deny 22
		sudo ufw reload
	fi

    # Refresh SSH service
    sudo systemctl restart sshd

    success "SSH configuration hardened. SSH Port Changed To 2222. Requests To Port 22 Will Be Denied."
else
    warn "Skipped SSH hardening."
fi

# Update System
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Update And Upgrade The System?" --no-wrap
    if [ $? = 0 ]; then
        update_system="true"
    else
        update_system="false"
    fi
fi

if [ "$update_system" = "true" ]; then
	sudo apt update && sudo apt upgrade -y
else
	warn "Skipped Update."
fi

# Remove $PATH Duplicates
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Remove Duplicates from \$PATH?" --no-wrap
    if [ $? = 0 ]; then
        remove_duplicates_path="true"
    else
        remove_duplicates_path="false"
    fi
fi

if [ "$remove_duplicates_path" = "true" ]; then
    OLD_IFS=$IFS
    IFS=:
    NEWPATH=
    unset EXISTS
    declare -A EXISTS
    for p in $PATH; do
        if [ -z "${EXISTS[$p]}" ]; then
            NEWPATH=${NEWPATH:+$NEWPATH:}$p
            EXISTS[$p]=yes
        fi
    done
    IFS=$OLD_IFS
    export PATH=$NEWPATH
    unset EXISTS
    success "Removed duplicate entries from \$PATH."
else
    warn "Skipped removing duplicates from \$PATH."
fi

# Disable Selected Services
if [ "$auto_mode" = "true" ]; then
    if [ -n "$services_to_disable" ]; then
        IFS=',' read -ra SERVICES <<< "$services_to_disable"
        for svc in "${SERVICES[@]}"; do
            svc_trimmed=$(echo "$svc" | xargs)  # Trim whitespace
            if systemctl list-unit-files | grep -q "^$svc_trimmed.service"; then
                sudo systemctl disable "$svc_trimmed"
                success "Disabled $svc_trimmed.service"
            else
                warn "Service $svc_trimmed.service not found."
            fi
        done
    else
        warn "No services listed to disable in config."
    fi
else
    echo "Available enabled services:"
    systemctl list-unit-files --type=service | grep enabled
    read -p "Enter the name of a service to disable (or press Enter to continue): " svc

    while [[ ! -z "$svc" ]]; do
        if systemctl list-unit-files | grep -q "^$svc.service"; then
            sudo systemctl disable "$svc"
            success "Disabled $svc.service"
        else
            warn "Service $svc.service not found."
        fi
        read -p "Enter the name of another service to disable (or press Enter to continue): " svc
    done
    success "Disabled selected services."
fi

# Install Programs
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Install Programs From List?" --no-wrap
    if [ $? = 0 ]; then
        install_programs="true"
    else
        install_programs="false"
    fi
fi

if [ "$install_programs" = "true" ]; then
	# Just some examples, modify to your needs
	# Using somewhat cumbersome "apt install -y" for each entry to allow for other custom install commands
	# (user might want to `curl` or `wget` something, or use `snap` or `flatpak` for some programs, this works here)
	declare -A tools=(
		["GParted"]="apt install -y gparted"
		["Htop"]="apt install -y htop"
		["Neofetch"]="apt install -y neofetch"
		["Git"]="apt install -y git"
		["Git-LFS"]="apt install -y git-lfs"
		["VLC"]="apt install -y vlc"
		["Flameshot"]="apt install -y flameshot"
		["PDFArranger"]="apt install -y pdfarranger"
		["OneDrive"]="apt install -y onedrive"
		["OBS"]="apt install -y obs-studio"
		["Audacity"]="apt install -y audacity"
		["Brasero"]="apt install -y brasero"
		["Kid3"]="apt install -y kid3"
		["Pinta"]="apt install -y pinta"
		["Remmina"]="apt install -y remmina"
		["NumLockX"]="apt install -y numlockx"
	)

	for tool in "${!tools[@]}"; do
		echo "Installing $tool..."
		if eval ${tools[$tool]}; then
			success "Installed $tool."
			echo
		else
			error "Failed Installing $tool."
			echo
		fi
	done
else
	warn "Skipped Program Installations."
fi

# Reboot System
if ! [ "$auto_mode" = "true" ]; then
    zenity --question --text="Reboot Now?" --no-wrap
    if [ $? = 0 ]; then
        reboot_system="true"
    else
        reboot_system="false"
    fi
fi

if [ "$reboot_system" = "true" ]; then
	reboot
fi