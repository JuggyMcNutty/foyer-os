#!/bin/sh
# foyer-os session — started by init on tty1 (OpenRC: /etc/inittab respawn).
# Runs PipeWire + gamescope + the Foyer launcher.

FOYER_CONF=/etc/foyer
[ -d "$FOYER_CONF" ] || FOYER_CONF=/etc/htpc
export FOYER_CONF

# init gives us a minimal env: no /usr/local/bin, HOME=/
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export XDG_CONFIG_HOME=/root/.config
export XDG_STATE_HOME=/var/lib/foyer/state
export XDG_DATA_HOME=/var/lib/foyer/share
export XDG_RUNTIME_DIR=/run/foyer
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Display mode. Empty WIDTH/HEIGHT = let gamescope use the monitor's preferred mode.
WIDTH=""; HEIGHT=""; RATE=""; RENDER_WIDTH=""; RENDER_HEIGHT=""
[ -r "$FOYER_CONF/session.conf" ] && . "$FOYER_CONF/session.conf"

GS_ARGS=""
[ -n "$WIDTH" ] && GS_ARGS="$GS_ARGS -W $WIDTH"
[ -n "$HEIGHT" ] && GS_ARGS="$GS_ARGS -H $HEIGHT"
[ -n "$RATE" ] && GS_ARGS="$GS_ARGS -r $RATE"
# Internal (UI/app render) resolution; defaults to the output size.
RW=${RENDER_WIDTH:-$WIDTH}; RH=${RENDER_HEIGHT:-$HEIGHT}
[ -n "$RW" ] && GS_ARGS="$GS_ARGS -w $RW"
[ -n "$RH" ] && GS_ARGS="$GS_ARGS -h $RH"

# Audio: PipeWire + pulse compat (HDMI sink picked by wireplumber)
pipewire >/dev/null 2>&1 &
pipewire-pulse >/dev/null 2>&1 &
wireplumber >/dev/null 2>&1 &

# Launcher: packaged (/usr/bin/foyer + /usr/share/foyer) or the interim
# /opt/htpc/launcher tree.
if [ -x /opt/htpc/launcher/foyer ]; then
    cd /opt/htpc/launcher
    LAUNCHER=./foyer
else
    cd /usr/share/foyer 2>/dev/null || cd /
    LAUNCHER=foyer
fi

# shellcheck disable=SC2086
exec gamescope $GS_ARGS -- $LAUNCHER -c "$FOYER_CONF/config.ini" -l "$FOYER_CONF/layout.xml"
