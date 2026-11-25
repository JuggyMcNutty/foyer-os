# shellcheck shell=sh
# foyer-ctl backend: systemd + NetworkManager (Debian)
be_poweroff() { systemctl poweroff; }
be_reboot() { systemctl reboot; }
be_suspend() { systemctl suspend; }
be_service_restart() { systemctl restart "$1" >/dev/null 2>&1; }
be_restart_session() { systemctl restart foyer-session.service; }
be_ntp_sync() { timedatectl set-ntp true >/dev/null 2>&1 && systemctl restart systemd-timesyncd >/dev/null 2>&1; }
be_upgrade() { apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade; }
be_wifi_kind() { echo nm; }
