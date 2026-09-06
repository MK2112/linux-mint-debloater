#!/bin/bash
# Version: 1.0.5

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"
LOG_FILE="$SCRIPT_DIR/debloat.log"

if [ "$(id -u)" -eq 0 ]; then
    echo -e "\033[1;31m[ERROR]\033[0m Do Not Run This Script With sudo (e.g. 'sudo ./debloat.sh'). Run As Your Normal User: ./debloat.sh"
    echo "The Script Uses sudo Internally Only Where Needed."
    exit 1
fi

for dep in zenity timeshift ufw curl sudo; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo -e "\033[1;31m[ERROR]\033[0m Required Dependency '$dep' Not Installed - Please Install, Then Re-Run This Script"
        exit 1
    fi
done

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

REPO_URL="https://raw.githubusercontent.com/MK2112/linux-mint-debloater/main/debloat.sh"

get_version() {
    grep '^# Version:' "$1" | head -n1 | awk '{print $3}'
}

log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}

is_true() {
    local val
    val="$(printf '%s' "$1" | tr -d '\r' | xargs 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [ "$val" = "true" ]
}

info()    { echo -e "${CYAN}[i] $1${RESET}"; }
success() { echo -e "${GREEN}[+] $1${RESET}"; }
warn()    { echo -e "${YELLOW}[~] $1${RESET}"; }
error()   { echo -e "${RED}[-] $1${RESET}"; }

LOCAL_VERSION=$(get_version "$0")
REMOTE_VERSION=$(curl -fsSL "$REPO_URL" 2>/dev/null | grep '^# Version:' | head -n1 | awk '{print $3}')

if [ -n "$REMOTE_VERSION" ] && [ "$(printf '%s\n' "$LOCAL_VERSION" "$REMOTE_VERSION" | sort -V | head -n1)" != "$REMOTE_VERSION" ]; then
    log "Update To $REMOTE_VERSION Available (You Have $LOCAL_VERSION)"
    zenity --question --title="Update Available" --text="A New Version ($REMOTE_VERSION) Is Available.\nUpdate Now?" --no-wrap
    if [ $? -eq 0 ]; then
        TMP_UPDATE="$(mktemp /tmp/debloat-mint.sh.update.XXXXXX)"
        if curl -fsSL "$REPO_URL" -o "$TMP_UPDATE"; then
            # Check for update validity
            if grep -q '^#!/bin/bash' "$TMP_UPDATE" && grep -q "^# Version: $REMOTE_VERSION" "$TMP_UPDATE"; then
                cp "$0" "$0.bak"
                mv "$TMP_UPDATE" "$0"
                chmod +x "$0"
                log "Script Updated To Version $REMOTE_VERSION. Please Re-Run"
                zenity --info --title="Updated" --text="Script Updated To $REMOTE_VERSION. Please Re-Run The Script" --no-wrap
                exit 0
            else
                log "Update Failed: Downloaded File Is Not A Valid Script"
                zenity --error --title="Update Failed" --text="Downloaded File Is Not A Valid Script" --no-wrap
                rm -f "$TMP_UPDATE"
            fi
        else
            log "Update Failed: Could Not Download New Version"
            zenity --error --title="Update Failed" --text="Could Not Download New Version" --no-wrap
        fi
    else
        log "User Chose Not To Update"
    fi
fi



read_config() {
    grep "^$1=" "$CONFIG_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r' | xargs 2>/dev/null
}

auto_mode=$(read_config "auto")

if is_true "$auto_mode"; then
	auto_mode="true"
	success "Running In Auto Mode"
	info "Using Settings From $CONFIG_FILE"
	echo
	create_snapshot=$(read_config "options/create_snapshot")
	debloat=$(read_config "options/debloat")
	portable_use=$(read_config "options/portable_use")
	disable_flatpak=$(read_config "options/disable_flatpak")
	optimize_boot=$(read_config "options/optimize_boot")
	disable_online_accounts=$(read_config "options/disable_online_accounts")
	disable_telemetry=$(read_config "options/disable_telemetry")
	configure_firewall=$(read_config "options/configure_firewall")
    harden_net=$(read_config "options/harden_net")
    harden_ssh=$(read_config "options/harden_ssh")
	encrypt_dns=$(read_config "options/encrypt_dns")
	update_system=$(read_config "options/update_system")
	install_programs=$(read_config "options/install_programs")
	reboot_system=$(read_config "options/reboot_system")
	remove_duplicates_path=$(read_config "options/remove_duplicates_path")
    services_to_disable=$(read_config "options/services_to_disable")

    for flg in create_snapshot debloat portable_use disable_flatpak optimize_boot disable_online_accounts disable_telemetry configure_firewall harden_net harden_ssh encrypt_dns update_system install_programs reboot_system remove_duplicates_path; do
        if is_true "${!flg}"; then
            printf -v "$flg" '%s' "true"
        else
            printf -v "$flg" '%s' "false"
        fi
    done
    unset flg
else
	success "Running In Manual Mode"
	info "Select Operations In The Dialog"
	echo

    choices=$(zenity --list --checklist \
        --title="Linux Mint Debloater v$LOCAL_VERSION" \
        --text="Select Which Operations To Perform:" \
        --column="Run" --column="Operation" \
        TRUE "Create Snapshot" \
        TRUE "Debloat System" \
        FALSE "Portable Use Optimization" \
        FALSE "Disable Flatpak" \
        TRUE "Optimize Boot Time" \
        TRUE "Disable Online Accounts" \
        TRUE "Disable Telemetry" \
        TRUE "Configure Firewall" \
        FALSE "Kernel-Level Network Hardening" \
        FALSE "Harden SSH" \
        TRUE "Encrypt DNS" \
        TRUE "Update System" \
        FALSE "Install Programs" \
        FALSE "Clean PATH Duplicates" \
        FALSE "Disable Services" \
        FALSE "Reboot" \
        --separator="|" \
        --height=520 --width=480)

    if [ $? -ne 0 ]; then
        warn "User Cancelled - Exiting..."
        exit 0
    fi

    create_snapshot="false"
    debloat="false"
    portable_use="false"
    disable_flatpak="false"
    optimize_boot="false"
    disable_online_accounts="false"
    disable_telemetry="false"
    configure_firewall="false"
    harden_net="false"
    harden_ssh="false"
    encrypt_dns="false"
    update_system="false"
    install_programs="false"
    remove_duplicates_path="false"
    reboot_system="false"
    services_to_disable=""

    [[ "$choices" == *"Create Snapshot"* ]]                && create_snapshot="true"
    [[ "$choices" == *"Debloat System"* ]]                 && debloat="true"
    [[ "$choices" == *"Portable Use Optimization"* ]]      && portable_use="true"
    [[ "$choices" == *"Disable Flatpak"* ]]                && disable_flatpak="true"
    [[ "$choices" == *"Optimize Boot Time"* ]]             && optimize_boot="true"
    [[ "$choices" == *"Disable Online Accounts"* ]]        && disable_online_accounts="true"
    [[ "$choices" == *"Disable Telemetry"* ]]              && disable_telemetry="true"
    [[ "$choices" == *"Configure Firewall"* ]]             && configure_firewall="true"
    [[ "$choices" == *"Kernel-Level Network Hardening"* ]] && harden_net="true"
    [[ "$choices" == *"Harden SSH"* ]]                     && harden_ssh="true"
    [[ "$choices" == *"Encrypt DNS"* ]]                    && encrypt_dns="true"
    [[ "$choices" == *"Update System"* ]]                  && update_system="true"
    [[ "$choices" == *"Install Programs"* ]]               && install_programs="true"
    [[ "$choices" == *"Clean PATH Duplicates"* ]]          && remove_duplicates_path="true"
    [[ "$choices" == *"Disable Services"* ]]               && services_to_disable="$(zenity --entry --title="Disable Services" --text="Comma-separated service names (e.g. bluetooth,cups):" --entry-text="bluetooth,cups" 2>/dev/null)"
    [[ "$choices" == *"Reboot"* ]]                         && reboot_system="true"
fi

if [ "$create_snapshot" = "true" ]; then
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	sudo timeshift --create --comments "LM Primer ::System Snapshot:: $timestamp" --tags O

	if [ $? -eq 0 ]; then
	  	success "Timeshift Snapshot Created Successfully"
	else
	  	error "Failed To Create Timeshift Snapshot"
		exit 1
	fi
else
	warn "Skipped Snapshot Creation"
fi

if [ "$debloat" = "true" ]; then
    log "Starting Debloat Process"
    # Purging these programs
    # Delete from the list below if program should stay
    programs=(
        mintwelcome         # Welcome screen
        redshift            # Screen Color adjustment tool for eye strain reduction
        libreoffice-core    # Core components of LibreOffice
        libreoffice-common  # Common files for LibreOffice
        transmission-gtk    # BitTorrent client
        hexchat             # Internet Relay Chat client
        baobab              # Disk usage analyzer
        seahorse            # GNOME frontend for GnuPG
        thunderbird         # Email and news client
        rhythmbox           # Music player
        pix                 # Image viewer and browser
        simple-scan         # Scanning utility
        drawing             # Drawing application
        gnote               # Note-taking application
        xreader             # Document viewer
        onboard             # On-screen keyboard
        celluloid           # Video player
        gnome-calendar      # Calendar application
        gnome-contacts      # Contacts manager
        gnome-logs          # Log viewer for the systemd
        gnome-power-manager # GNOME desktop Power management tool
        warpinator          # Tool for local network file sharing
    )

    for program in "${programs[@]}"; do
        log "Purging Package: $program"
        sudo apt purge "$program" -y 2>&1 | tee -a "$LOG_FILE"
        if [ "${PIPESTATUS[0]}" -eq 0 ]; then
            log "Successfully Purged $program"
        else
            log "Failed To Purge $program"
        fi
    done

    # Check for orphaned packages
	orphans=$(LC_ALL=C sudo apt-get -s autoremove 2>/dev/null | awk '/^Remv / {print $2}' | paste -sd' ' -)
    if [ -n "$orphans" ]; then
        log "Orphaned Packages Found: $orphans"
        rm_orphans="false"
        if [ "$auto_mode" = "true" ]; then
            rm_orphans="true"
            log "Auto Mode: Removing Orphaned Packages Without Prompt"
        else
            zenity --question --title="Orphaned Packages" --text="Orphaned Packages Detected:\n$orphans\n\nRemove Them Now?" --width=480
            if [ $? -eq 0 ]; then
                rm_orphans="true"
            fi
        fi
        if [ "$rm_orphans" = "true" ]; then
            log "Removing Orphaned Packages: $orphans"
            sudo apt autoremove -y 2>&1 | tee -a "$LOG_FILE"
            sudo apt clean 2>&1 | tee -a "$LOG_FILE"
            success "Orphaned Packages Removed"
        else
            warn "User Chose Not To Remove Orphaned Packages"
        fi
        unset rm_orphans
    else
        log "No Orphaned Packages Found After Debloat"
        sudo apt clean 2>&1 | tee -a "$LOG_FILE"
    fi
    success "System Debloated Successfully"
else
    warn "Skipped System Debloat"
fi

# Portable Optimization
if [ "$portable_use" = "true" ]; then
	# TLP, Powertop, ThermalD
  	sudo apt update && sudo apt upgrade -y
	sudo apt install -y tlp powertop thermald || warn "Some Power Packages Failed To Install - Continuing"
	
    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^thermald\.service"; then
 		sudo systemctl enable thermald 2>/dev/null || true
 		sudo systemctl start thermald 2>/dev/null || warn "thermald Not Started (Likely Non-Intel CPU)"
	fi
	
    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^tlp\.service"; then
 		sudo systemctl enable tlp 2>/dev/null || true
 		sudo systemctl start tlp 2>/dev/null || true
	fi
	
    running_battery="false"
	
    for pwrsply in /sys/class/power_supply/*/online; do
		if [ -f "$pwrsply" ] && [ "$(cat "$pwrsply" 2>/dev/null)" = "0" ]; then
			running_battery="true"
			break
		fi
	done
	
    if [ "$running_battery" = "true" ]; then
		sudo powertop --auto-tune || warn "powertop --auto-tune Failed"
	fi
	unset running_battery pwrsply

	# TLP Configuration (Adapt to your needs)
	if [ -f /etc/tlp.conf ]; then
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
     	-e 's/#CPU_MAX_PERF_ON_BAT=30/CPU_MAX_PERF_ON_BAT=75/' \
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
	else
		warn "TLP Config /etc/tlp.conf Not Found (Newer TLP Uses /etc/tlp.d/) - Skipping TLP Tuning"
	fi

	BT_CONF_FILE="/etc/bluetooth/main.conf"
	if [ ! -f "$BT_CONF_FILE" ]; then
		warn "Bluetooth Config $BT_CONF_FILE Does Not Exist - Skipping Bluetooth Tuning"
	else
		sudo cp -n "$BT_CONF_FILE" "$BT_CONF_FILE.bak" 2>/dev/null || true
		sudo sed -i -E 's/^#?AutoEnable=.*/AutoEnable=false/' "$BT_CONF_FILE"
		if ! grep -q "^AutoEnable=" "$BT_CONF_FILE"; then
			echo "AutoEnable=false" | sudo tee -a "$BT_CONF_FILE" > /dev/null
		fi
		if grep -q "^AutoEnable=false" "$BT_CONF_FILE"; then
    		success "Successfully Updated $BT_CONF_FILE - AutoEnable Is Now Turned Off"
		else
    		error "Updating $BT_CONF_FILE Failed - Check Manually"
		fi
	fi

	sudo apt autoremove -y && sudo apt clean
	success "Successfully Optimized For Portability"
else
	warn "Skipped Optimization For Portability"
fi

# Disable Flatpak
if [ "$disable_flatpak" = "true" ]; then
	sudo apt purge -y flatpak
	sudo apt-mark hold flatpak
	sudo rm -rf /var/lib/flatpak 2>/dev/null || true
	rm -rf "$HOME/.local/share/flatpak" 2>/dev/null || true
	# To Re-Enable Later: sudo apt-mark unhold flatpak && sudo apt install -y flatpak
 	success "Disabled Flatpak"
else
	warn "Skipped Disabling Flatpak"
fi

# Boot Optimization
if [ "$optimize_boot" = "true" ]; then
	sudo cp -n /etc/default/grub /etc/default/grub.bak 2>/dev/null || true
	sudo cp -n /etc/systemd/logind.conf /etc/systemd/logind.conf.bak 2>/dev/null || true
	sudo cp -n /etc/systemd/system.conf /etc/systemd/system.conf.bak 2>/dev/null || true
    if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
		sudo sed -i -E 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
	else
		echo "GRUB_TIMEOUT=1" | sudo tee -a /etc/default/grub > /dev/null
	fi
	if grep -q "^#\?GRUB_DISABLE_SUBMENU=" /etc/default/grub; then
		sudo sed -i -E 's/^#?GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
	else
		echo "GRUB_DISABLE_SUBMENU=y" | sudo tee -a /etc/default/grub > /dev/null
	fi
	if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
		sudo sed -i -E 's/splash/nosplash/g' /etc/default/grub
		if ! grep -q 'nosplash' /etc/default/grub; then
			sudo sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)"/\1 nosplash"/' /etc/default/grub
		fi
	fi
    if ! sudo update-grub; then
		error "update-grub Failed - Check /etc/default/grub Manually"
	fi
	if grep -q "^#\?NAutoVTs=" /etc/systemd/logind.conf; then
		sudo sed -i -E 's/^#?NAutoVTs=.*/NAutoVTs=2/' /etc/systemd/logind.conf
	else
		echo "NAutoVTs=2" | sudo tee -a /etc/systemd/logind.conf > /dev/null
	fi
	if grep -q "^#\?DefaultTimeoutStartSec=" /etc/systemd/system.conf; then
		sudo sed -i -E 's/^#?DefaultTimeoutStartSec=.*/DefaultTimeoutStartSec=40s/' /etc/systemd/system.conf
	else
		echo "DefaultTimeoutStartSec=40s" | sudo tee -a /etc/systemd/system.conf > /dev/null
	fi
    if grep -q "^#\?DefaultTimeoutStopSec=" /etc/systemd/system.conf; then
		sudo sed -i -E 's/^#?DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=40s/' /etc/systemd/system.conf
	else
		echo "DefaultTimeoutStopSec=40s" | sudo tee -a /etc/systemd/system.conf > /dev/null
	fi
	
    sudo systemctl daemon-reload
 	success "Boot Optimization Successful (Backups: *.bak)"
else
	warn "Skipped Boot Optimization"
fi

# Disable Online Accounts Integration
if [ "$disable_online_accounts" = "true" ]; then
    info "Disabling GNOME Online Accounts And Related Integration"
    # Remove gnome-online-accounts and related packages
    sudo apt purge -y gnome-online-accounts gnome-control-center-data
    # Remove autostart entry if present
    autostart_dir="/etc/xdg/autostart"
    if [ -f "$autostart_dir/gnome-online-accounts-panel.desktop" ]; then
        sudo rm "$autostart_dir/gnome-online-accounts-panel.desktop"
    fi
    # Kill any running goa-daemon
    pkill -f goa-daemon 2>/dev/null || true
    success "Online Accounts Integration Disabled"
else
    warn "Skipped Disabling Online Accounts Integration"
fi

# Disable Reporting and Telemetry
if [ "$disable_telemetry" = "true" ]; then
	set_tel_pref() {
		local tel_file="$1" tel_pref="$2" tel_line="$3"
		[ -f "$tel_file" ] || return 0
		if grep -Fq "$tel_pref" "$tel_file"; then
			sed -i -E "s|.*${tel_pref}.*|${tel_line}|" "$tel_file"
		else
			printf '%s\n' "$tel_line" >> "$tel_file"
		fi
	}

	ff_home="/home/${SUDO_USER:-$USER}"
	ff_found="false"
	while IFS= read -r ff_profile; do
		[ -z "$ff_profile" ] && continue
		ff_found="true"
		ff_user_js="$ff_profile/user.js"
		touch "$ff_user_js"
		set_tel_pref "$ff_user_js" 'toolkit.telemetry.enabled' 'user_pref("toolkit.telemetry.enabled", false);'
		set_tel_pref "$ff_user_js" 'toolkit.telemetry.unified' 'user_pref("toolkit.telemetry.unified", false);'
		set_tel_pref "$ff_user_js" 'browser.region.update.enabled' 'user_pref("browser.region.update.enabled", false);'
		set_tel_pref "$ff_user_js" 'extensions.getAddons.cache.enabled' 'user_pref("extensions.getAddons.cache.enabled", false);'
		set_tel_pref "$ff_user_js" 'datareporting.healthreport.uploadEnabled' 'user_pref("datareporting.healthreport.uploadEnabled", false);'
		set_tel_pref "$ff_user_js" 'datareporting.policy.dataSubmissionEnabled' 'user_pref("datareporting.policy.dataSubmissionEnabled", false);'
		set_tel_pref "$ff_user_js" 'browser.newtabpage.activity-stream.telemetry' 'user_pref("browser.newtabpage.activity-stream.telemetry", false);'
		set_tel_pref "$ff_user_js" 'browser.newtabpage.activity-stream.feeds.telemetry' 'user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);'
		set_tel_pref "$ff_user_js" 'extensions.htmlaboutaddons.recommendations.enabled' 'user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);'
		log "Firefox Telemetry Disabled In $ff_user_js"
	done < <(find "$ff_home/.mozilla/firefox/" -maxdepth 1 -type d -name "*.default*" 2>/dev/null)
	if [ "$ff_found" = "false" ]; then
    	warn "Firefox: No Profile Found - Not Installed Or Not Used"
	fi
	unset ff_profile ff_user_js ff_found ff_home

	tb_found="false"
	while IFS= read -r tb_profile; do
		[ -z "$tb_profile" ] && continue
		tb_found="true"
		tb_user_js="$tb_profile/user.js"
		touch "$tb_user_js"
		set_tel_pref "$tb_user_js" 'datareporting.healthreport.uploadEnabled' 'user_pref("datareporting.healthreport.uploadEnabled", false);'
		set_tel_pref "$tb_user_js" 'datareporting.policy.dataSubmissionEnabled' 'user_pref("datareporting.policy.dataSubmissionEnabled", false);'
		set_tel_pref "$tb_user_js" 'mail.shell.checkDefaultClient' 'user_pref("mail.shell.checkDefaultClient", false);'
		set_tel_pref "$tb_user_js" 'mailnews.start_page.enabled' 'user_pref("mailnews.start_page.enabled", false);'
		log "Thunderbird Telemetry Disabled In $_user_js"
	done < <(find "/home/${SUDO_USER:-$USER}/.thunderbird/" -maxdepth 1 -type d -name "*.default*" 2>/dev/null)
	if [ "$tb_found" = "false" ]; then
    	warn "Thunderbird: No Profile Found - Not Installed Or Unused"
	fi
	unset tb_profile tb_user_js tb_found

	if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || [ -d "/home/${SUDO_USER:-$USER}/.config/chromium" ]; then
		sudo mkdir -p /etc/chromium/policies/managed
		echo '{"MetricsReportingEnabled": false, "UserFeedbackAllowed": false}' | sudo tee /etc/chromium/policies/managed/disable-metrics.json > /dev/null
		log "Chromium Metrics Disabled Via Managed Policy"
	else
		warn "Chromium: Not Installed - Skipping"
	fi

	if gsettings list-schemas 2>/dev/null | grep -q "^org.gnome.desktop.privacy$"; then
		gsettings set org.gnome.desktop.privacy send-software-usage-stats false || warn "Failed To Set GNOME send-software-usage-stats"
		gsettings set org.gnome.desktop.privacy report-technical-problems false || warn "Failed To Set GNOME report-technical-problems"
	fi
	if gsettings list-schemas 2>/dev/null | grep -q "^org.cinnamon.desktop.privacy$"; then
    	gsettings set org.cinnamon.desktop.privacy remember-recent-files false || warn "Failed To Set Cinnamon remember-recent-files"
	fi
else
	warn "Skipped Reporting And Telemetry"
fi

# Configure Firewall
if [ "$configure_firewall" = "true" ]; then
	if ! command -v ufw &> /dev/null; then
        sudo apt install -y ufw || {
            error "Failed To Install UFW"
            exit 1
        }
    fi

    sudo ufw status numbered 2>/dev/null | tee -a "$LOG_FILE" || true
    sudo cp -n /etc/ufw/user.rules "/etc/ufw/user.rules.bak.$(date +%F-%H%M%S)" 2>/dev/null || true

    if [ "$auto_mode" != "true" ]; then
        zenity --question --title="Reset Firewall?" --text="This Will Reset All UFW Rules And Apply A Deny-Incoming Default.\nA Backup Is Saved To /etc/ufw/user.rules.bak.*\nContinue?" --width=480
        if [ $? -ne 0 ]; then
            warn "Firewall Configuration Cancelled By User"
            configure_firewall="false"
        fi
    fi
fi

if [ "$configure_firewall" = "true" ]; then
    sudo ufw --force reset
    sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw

    # Default: Deny incoming, allow outgoing, deny routed (forwarded) traffic, standard logging
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default deny routed
    sudo ufw logging low

    # Enabling firewall should not strand a remote session
    ssh_needed="false"
    if [ -f /etc/ssh/sshd_config ] || command -v sshd >/dev/null 2>&1; then
        if systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-enabled sshd >/dev/null 2>&1 \
            || systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1 \
            || ss -tln 2>/dev/null | grep -q ":22 "; then
            ssh_needed="true"
        fi
    fi
    if [ "$ssh_needed" = "true" ]; then
        sudo ufw allow 22/tcp || warn "Failed To Allow SSH (22/tcp)"
        if [ "$harden_ssh" = "true" ]; then
            log "SSH Hardening Selected: Firewall Keeps 22 Open For Now; SSH Section Will Migrate It To 2222"
        fi
    else
        log "No SSH Server Detected - Leaving All Incoming Ports Denied"
    fi
    unset ssh_needed

    sudo ufw --force enable
    sudo ufw status verbose 2>&1 | tee -a "$LOG_FILE"
    success "Firewall Configured And Enabled Successfully"
else
    warn "Skipped Firewall Configuration"
fi

# Kernel-level Anti-Spoofing
# Prevents IP address spoofing attacks, adds kernel-level network hardening measures.
# Does not replace a properly setup firewall.
if [ "$harden_net" = "true" ]; then
    sudo cp -n /etc/sysctl.d/99-network-hardening.conf "/etc/sysctl.d/99-network-hardening.conf.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
    cat <<EOF | sudo tee /etc/sysctl.d/99-network-hardening.conf > /dev/null
# Anti-spoofing
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0

# Disable source-routed packets
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0

# Disable packet redirects sent by this host
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0

# SYN flood protection
net.ipv4.tcp_syncookies=1

# Ignore broadcast ICMP requests
net.ipv4.icmp_echo_ignore_broadcasts=1

# IPv6 router advertisements
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0

# Do not forward IP traffic
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0

# Disable SUID core dumps
fs.suid_dumpable=0
EOF

    if sudo sysctl --system 2>&1 | tee -a "$LOG_FILE"; then
        success "Kernel-Level Network Hardening Enabled"
    else
        error "sysctl --system Reported Errors - Check Config"
    fi
else
    warn "Skipped Kernel-Level Network Hardening"
fi

# Harden SSH
if [ "$harden_ssh" = "true" ] && [ "$auto_mode" = "true" ]; then
    log "Auto Mode: SSH Hardening Selected - Proceeding Without Interactive Confirm"
fi

if [ "$harden_ssh" = "true" ] && [ "$auto_mode" != "true" ]; then
    zenity --question --title="Confirm SSH Hardening" --text="Are You Sure? This Will Change Your SSH Configuration And Port." --no-wrap
    if [ $? != 0 ]; then
        warn "SSH Hardening Cancelled By User"
        harden_ssh="false"
    fi
fi

if [ "$harden_ssh" = "true" ]; then
    SSHD_CONFIG="/etc/ssh/sshd_config"
    BACKUP="/etc/ssh/sshd_config.bak.$(date +%F-%H%M%S)"
    HARDENING_DROPIN="/etc/ssh/sshd_config.d/99-endpoint-hardening.conf"

    if [ ! -f "$SSHD_CONFIG" ]; then
        error "SSH Config $SSHD_CONFIG Not Found - Is openssh-server Installed? Skipping"
        harden_ssh="false"
    elif ss -tln 2>/dev/null | grep -q ":2222 "; then
        error "Port 2222 Already In Use - Skipping SSH Hardening To Avoid Conflict"
        harden_ssh="false"
    fi
fi

if [ "$harden_ssh" = "true" ]; then
    sudo cp "$SSHD_CONFIG" "$BACKUP"
    sudo mkdir -p /etc/ssh/sshd_config.d
    sudo tee "$HARDENING_DROPIN" > /dev/null <<EOF
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
Port 2222
EOF

    if ls "$HOME/.ssh/"*.pub >/dev/null 2>&1; then
        if ! grep -q "^PasswordAuthentication no" "$HARDENING_DROPIN" 2>/dev/null; then
            echo "PasswordAuthentication no" | sudo tee -a "$HARDENING_DROPIN" > /dev/null
        fi
    else
        warn "SSH Keys Not Detected In $HOME/.ssh - Leaving Password Auth Enabled"
    fi

    # Migrate the firewall rule: opening 2222 BEFORE removing 22 avoids
    # stranding an active session; end state is a single port (2222), not both.
    if command -v ufw &> /dev/null; then
        sudo ufw allow 2222/tcp
        sudo ufw delete allow 22/tcp 2>/dev/null || true
        sudo ufw reload
    fi

    if ! sudo sshd -t; then
        warn "New SSH Config Invalid - Rolling Back..."
        sudo cp "$BACKUP" "$SSHD_CONFIG"
        sudo rm -f "$HARDENING_DROPIN"
        # Roll back the firewall migration too, or sshd (back on 22) is unreachable
        # while a useless 2222 rule stays open.
        if command -v ufw &> /dev/null; then
            sudo ufw delete allow 2222/tcp 2>/dev/null || true
            sudo ufw allow 22/tcp 2>/dev/null || true
            sudo ufw reload 2>/dev/null || true
        fi
        if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^ssh\.service"; then
            sudo systemctl restart ssh || true
        else
            sudo systemctl restart sshd || true
        fi
        warn "SSH Config Restored"
    else
        if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^ssh\.service"; then
            sudo systemctl restart ssh
        else
            sudo systemctl restart sshd
        fi
        success "SSH Configuration Hardened. Port: 2222 (Backup: $BACKUP)"
    fi
else
    warn "Skipped SSH Hardening"
fi

# Update
if [ "$update_system" = "true" ]; then
	sudo apt update && sudo apt upgrade -y
else
	warn "Skipped System Update"
fi

# Remove $PATH Duplicates
if [ "$remove_duplicates_path" = "true" ]; then
    OLD_IFS=$IFS
    IFS=:
    NEWPATH=
    declare -A EXISTS=()
    for p in $PATH; do
        if [ -z "${EXISTS[$p]:-}" ]; then
            NEWPATH=${NEWPATH:+$NEWPATH:}$p
            EXISTS[$p]=yes
        fi
    done
    IFS=$OLD_IFS
    export PATH=$NEWPATH
    unset EXISTS
    if ! grep -q "debloat.sh: dedupe PATH" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ''
            echo '# debloat.sh: dedupe PATH (added automatically)'
            echo 'export PATH="$(printf "%s" "$PATH" | awk -v RS=: -v ORS=: "!seen[$0]++" | sed "s/:$//")"'
        } >> "$HOME/.bashrc"
        info "Persisted PATH Dedupe To $HOME/.bashrc (Takes Effect On Next Login)"
    fi
    success "Removed Duplicate Entries From \$PATH"
else
    warn "Skipped Removing Duplicates From \$PATH"
fi

# Disable Selected Services
if [ -n "${services_to_disable:-}" ]; then
    IFS=',' read -ra SERVICES <<< "$services_to_disable"
    for svc in "${SERVICES[@]}"; do
        svc_trimmed=$(echo "$svc" | xargs)  # Trim whitespace
        [ -z "$svc_trimmed" ] && continue
        case "$svc_trimmed" in
            NetworkManager|network-manager|systemd-resolved|systemd-networkd|dbus|sudo|ssh|ufw)
                warn "Refusing To Disable Critical Service: $svc_trimmed"
                continue
                ;;
        esac
        if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^$svc_trimmed\.service"; then
            sudo systemctl disable --now "$svc_trimmed" || warn "Failed To Disable $svc_trimmed.service"
            success "Disabled $svc_trimmed.service"
        else
            warn "Service $svc_trimmed.service Not Found"
        fi
    done
    unset SERVICES svc svc_trimmed
else
    warn "No Services To Disable"
fi

# Encrypt DNS Traffic
if [ "$encrypt_dns" = "true" ]; then
    if command -v ufw &> /dev/null; then
        sudo ufw allow in on lo to 127.0.0.1 port 53 proto udp
        sudo ufw allow in on lo to 127.0.0.1 port 53 proto tcp
        sudo ufw allow in on lo to ::1 port 53 proto udp
        sudo ufw allow in on lo to ::1 port 53 proto tcp
    fi

    # Setup for DNS over TLS with Quad9 and Cloudflare as fallback
    echo "Configuring DNS over TLS, Quad9's 9.9.9.9 will become primary, Cloudflare's 1.1.1.1 will become fallback"
    if ! timeout 5 bash -c '</dev/tcp/9.9.9.9/853' 2>/dev/null; then
        warn "Port 853 To 9.9.9.9 Unreachable - Network May Block DNS-over-TLS. Continuing Anyway; Revert If DNS Breaks"
        log "DoT Pre-Check Failed: TCP/853 To 9.9.9.9 Unreachable"
    fi
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo cp -n /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak 2>/dev/null || true
    sudo tee /etc/systemd/resolved.conf.d/99-encrypted-dns.conf > /dev/null <<EOF
[Resolve]
DNS=9.9.9.9 2620:fe::fe
FallbackDNS=1.1.1.1 2606:4700:4700::1111
Domains=~.
DNSOverTLS=yes
DNSSEC=allow-downgrade
EOF
    sudo systemctl restart systemd-resolved || warn "Failed To Restart systemd-resolved"
    # Ensuring /etc/resolv.conf points to systemd's stub resolver
    if [ -L /etc/resolv.conf ] || ! grep -q "NetworkManager" /etc/resolv.conf 2>/dev/null; then
        sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    else
        warn "/etc/resolv.conf Looks Managed By NetworkManager - Leaving It In Place"
    fi
    # Check status of systemd-resolved
    systemd_status=$(systemctl is-active systemd-resolved)
    if [ "$systemd_status" != "active" ]; then
        error "systemd-resolved Is Not Running - DNS Change May Be Incomplete. Restore With: sudo rm /etc/systemd/resolved.conf.d/99-encrypted-dns.conf && sudo systemctl restart systemd-resolved"
    else
        success "Successfully Configured DNS-Over-TLS (Drop-In: /etc/systemd/resolved.conf.d/99-encrypted-dns.conf)"
        info "Verify Your DNS Provider By Visiting https://ipleak.net/"
        info "To Revert: sudo rm /etc/systemd/resolved.conf.d/99-encrypted-dns.conf && sudo systemctl restart systemd-resolved"
    fi

else
    warn "Skipped DNS Encryption"
fi

# Install Programs
if [ "$install_programs" = "true" ]; then
	# Just some examples, modify to your needs
	# Using somewhat cumbersome "apt install -y", but this allows for other custom install commands
	# (user might want to `curl` or `wget` something, or use `snap` or `flatpak` for some programs, this works here)
	declare -A tools=(
		["GParted"]="apt install -y gparted"
		["Htop"]="apt install -y htop"
		["Screenfetch"]="apt install -y screenfetch"
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

	if [ "$update_system" != "true" ]; then
		sudo apt update || warn "apt update Failed - Installs May Fail On Stale Cache"
	fi

	for tool in $(printf '%s\n' "${!tools[@]}" | sort); do
		echo "Installing $tool..."
		if sudo ${tools[$tool]}; then
			success "Installed $tool"
			echo
		else
			error "Failed Installing $tool"
			echo
		fi
	done
else
	warn "Skipped Program Installations"
fi

# Reboot
if [ "$reboot_system" = "true" ]; then
    commence_reboot="true"
    if [ "$auto_mode" != "true" ]; then
        zenity --question --title="Reboot?" --text="All Selected Operations Finished.\nReboot Now?" --width=400
        if [ $? -ne 0 ]; then
            commence_reboot="false"
            warn "Reboot Cancelled By User"
        fi
    fi
    if [ "$commence_reboot" = "true" ]; then
        info "Rebooting..."
        sudo reboot
    fi
    unset commence_reboot
fi
