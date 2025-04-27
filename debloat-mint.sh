#!/bin/bash

# Checking privileges
if [ "$EUID" -ne 0 ]; then
	echo "Please Run As Root."
  	return 1 2>/dev/null
	exit 1
fi

# Read config
read_config() {
    grep "^$1=" config.txt | cut -d'=' -f2- | tr -d '\r' 2>/dev/null
}

auto_mode=$(read_config "auto")

if [ "$auto_mode" = "true" ]; then
	echo "[+] Running In Auto Mode."
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
else
	echo "[+] Running In Manual Mode."
	echo "[~] Change value of 'auto' to 'true' in config.txt to enable auto mode."
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
	  	echo "Timeshift Snapshot Created Successfully."
	else
	  	echo "Failed To Create Timeshift Snapshot."
	  	return 1 2>/dev/null
		exit 1
	fi
else
	echo "[~] Skipped Snapshot Creation."
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
 	# Purging these programs (delete from list if program should stay)
	programs=(
	    mintwelcome			# Welcome screen
	    redshift			# Screen Color adjustment tool for eye strain reduction
	    libreoffice-core	# Core components of LibreOffice
	    libreoffice-common	# Common files for LibreOffice
	    transmission-gtk	# BitTorrent client
	    hexchat				# Internet Relay Chat client
	    baobab				# Disk usage analyzer
	    seahorse			# GNOME frontend for GnuPG
	    thunderbird			# Email and news client
	    rhythmbox			# Music player
	    pix					# Image viewer and browser
	    simple-scan			# Scanning utility
	    drawing				# Drawing application
	    gnote				# Note-taking application
	    xreader				# Document viewer
	    onboard				# On-screen keyboard
	    celluloid			# Video player
		gnome-calendar		# Calendar application
		gnome-contacts		# Contacts manager
	    gnome-logs			# Log viewer for the systemd 
	    gnome-power-manager	# GNOME desktop Power management tool
	    warpinator			# Tool for local network file sharing
	)

	for program in "${programs[@]}"; do
	    sudo apt purge "$program" -y
	done

	sudo apt autoremove -y && sudo apt clean
 	echo "[+] System Debloated."
else
	echo "[~] Skipped System Debloat."
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
	if $(cat /sys/class/power_supply/AC/online) = 0; then
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
		echo "[!] Bluetooth Config Error: $BT_CONF_FILE Does Not Exist."
		return 1 2>/dev/null
		exit 1
	else
		sed -i 's/^AutoEnable=true/AutoEnable=false/' "$BT_CONF_FILE"
	fi

	if grep -q "^AutoEnable=false" "$BT_CONF_FILE"; then
    	echo "[+] Successfully Updated $BT_CONF_FILE. AutoEnable Is Now Set To <False>."
	else
    	echo "[!] Updating $BT_CONF_FILE Failed. Check Manually."
	fi

	# Install and configure preload for faster application launch
	sudo apt install -y preload
	sudo systemctl enable preload && sudo systemctl start preload
	sudo apt autoremove -y && sudo apt clean
 
	echo "[+] Successfully Optimized For Portability."
else
	echo "[~] Skipped Optimization For Portability."
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
 	echo "[+] Disabled Flatpak."
else
	echo "[~] Skipped Disabling Flatpak."
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
	
 	echo "[+] Boot Optimization Successful."
else
	echo "[~] Skipped Boot Optimization."
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
        	echo "Firefox: Configuration file not found. Not installed or not used."
    	fi

    	thunderbird_config=$(find "/home/${SUDO_USER:-$USER}/.thunderbird/" -name "*.default-esr" -exec echo {}/prefs.js \;)
    	if [ -f "$thunderbird_config" ]; then
        	echo 'user_pref("datareporting.healthreport.uploadEnabled", false);' >> "$thunderbird_config"
        	echo 'user_pref("datareporting.policy.dataSubmissionEnabled", false);' >> "$thunderbird_config"
        	echo 'user_pref("mail.shell.checkDefaultClient", false);' >> "$thunderbird_config"
        	echo 'user_pref("mailnews.start_page.enabled", false);' >> "$thunderbird_config"
    	else
        	echo "Thunderbird: Configuration file not found. Not installed or not used."
    	fi

	chromium_config=$(find "/home/${SUDO_USER:-$USER}/.config/chromium/" -name "Default/Preferences")
	if [ -f "$chromium_config" ]; then
		sed -i 's/"metrics": {/"metrics": {"enabled": false,/' "$chromium_config"
		sed -i 's/"reporting": {/"reporting": {"enabled": false,/' "$chromium_config"
	else
		echo "Chromium: Configuration file not found. Not installed or not used."
	fi	

	# False by default, just making sure
	gsettings set org.gnome.desktop.privacy send-software-usage-stats false
	gsettings set org.gnome.desktop.privacy report-technical-problems false
else
	echo "[~] Skipped Reporting and Telemetry."
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
    echo "[+] Firewall configured and enabled successfully."
else
    echo "[~] Skipped Firewall configuration."
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

    echo "[+] SSH configuration hardened. SSH Port Changed To 2222. Requests To Port 22 Will Be Denied."
else
    echo "[~] Skipped SSH hardening."
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
	echo "[~] Skipped Update."
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
			echo "[+] Installed $tool."
			echo
		else
			echo "[-] Failed Installing $tool."
			echo
		fi
	done
else
	echo "[~] Skipped Program Installations."
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
