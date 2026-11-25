# shellcheck shell=sh
# foyer-ctl backend: OpenRC + ifupdown-ng + wpa_supplicant (Alpine)
be_poweroff() { poweroff; }
be_reboot() { reboot; }
be_suspend() { echo mem > /sys/power/state; }
be_service_restart() { rc-service "$1" restart >/dev/null 2>&1; }
be_restart_session() { pkill -9 -x gamescope-wl 2>/dev/null || pkill -9 -x gamescope 2>/dev/null; }
be_ntp_sync() {
    if command -v chronyc >/dev/null 2>&1; then chronyc -a makestep >/dev/null 2>&1
    elif command -v ntpd >/dev/null 2>&1; then ntpd -q -n -p pool.ntp.org >/dev/null 2>&1
    else return 1; fi
}
be_upgrade() { apk update && apk upgrade; }
# WiFi via wpa_supplicant (see foyer-ctl wifi:*)
be_wifi_kind() { echo wpa; }
