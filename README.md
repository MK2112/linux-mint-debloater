# Linux Mint / Ubuntu Debloater

Streamline and optimize your Linux Mint or Ubuntu.

```bash
sudo apt install -y git
# Clone the repository
git clone https://github.com/MK2112/linux-mint-debloater.git
cd linux-mint-debloater
# Execute the script
chmod +x debloat-mint.sh
sudo ./debloat-mint.sh
```

**Supported:**
- Linux Mint 21.3, 22, 22.1, 22.2
- Ubuntu 24.04 LTS, 24.10, 25.04

## Functionality

All of these are optional, you can pick what you want to do:

- **Backs up** your system (Timeshift snapshot)
- **Debloats**: Removes unwanted pre-installed software (fully customizable)
- **Optimizes**: Improves performance, boot time, and configures for portable use
- **Secures**: Updates, disables telemetry, and configures firewall
- **Hardens**: SSH and firewall hardening (with double confirmation for SSH)
- **Encrypts**: DNS traffic encryption for IPv4 and IPv6
- **Disables Online Accounts**: Disables GNOME Online Accounts and related integration
- **Installs**: Lets you define a custom list of programs to install
- **Automates**: Set `auto=true` in `config.txt` for unattended, fully automatic runs

## Safety & UX

- **Dependency Checks**: The script halts if `zenity`, `timeshift`, or `ufw` are missing, so you never run into missing tool errors. These are installed by default on Mint, but just to make sure.
- **Root Required**: Will only run as root for your safety.
- **Double Confirmation**: SSH hardening prompts for a second "Are you sure?" confirmation to prevent accidental lockouts.
- **No Surprises**: Every major action is confirmed with you, unless you enable full auto-mode.

## Configuration: `config.txt`

Options for automated runs are controlled by a simple `config.txt` file.<br>
The lists for programs to be removed or installed are editable in the `debloat-mint.sh` script itself.

Example:
```ini
auto=false
options/create_snapshot=false
options/debloat=false
options/portable_use=false
options/disable_flatpak=false
options/optimize_boot=false
options/disable_telemetry=false
options/configure_firewall=false
options/harden_ssh=false
options/encrypt_dns=false
options/update_system=false
options/install_programs=false
options/reboot_system=false
options/remove_duplicates_path=false
```
**`auto`**: Set to `true` for automated runs (no prompts, executing as specified in `config.txt`)

## How to Use

1. **Edit `config.txt`** to select which actions to perform.
2. **Run the script as root**: `sudo ./debloat-mint.sh`
3. **Follow the prompts** (unless in auto mode). Confirm or skip each action.

## Tips
- **First time?** Run with defaults and review each prompt.
- **Automate everything:** Set `auto=true` for hands-off setup (great for VM or repeatable builds).
- **SSH Hardening:** Double-confirmation prevents accidental lockout. Read the prompts carefully!

## Requirements
- Linux Mint or Ubuntu installed
- Root privileges
- `zenity`, `timeshift`, `ufw` (script will check and warn if missing, they are pre-installed on Mint and Ubuntu)

## Credits
This is a hard fork of [aaron-dev-git/Linux-Mint-Debloater](https://github.com/aaron-dev-git/Linux-Mint-Debloater).
