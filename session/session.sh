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

# Display-mode trial: `foyer-ctl display mode/set` leaves session.conf.pending.
# If the new mode isn't confirmed in the UI (keep/revert dialog) within 25 s,
# or the session already died once in it, restore session.conf.prev.
SC="$FOYER_CONF/session.conf"
if [ -f "$SC.pending" ] && [ -f "$SC.prev" ]; then
    now=$(date +%s); since=$(date -r "$SC.pending" +%s 2>/dev/null || echo "$now")
    if [ $((now - since)) -gt 40 ]; then
        mv "$SC.prev" "$SC"; rm -f "$SC.pending"            # crashed in trial mode
    else
        ( sleep 25; if [ -f "$SC.pending" ] && [ -f "$SC.prev" ]; then
              mv "$SC.prev" "$SC"; rm -f "$SC.pending"
              pkill -9 -f gamescope-wl 2>/dev/null || pkill -9 -x gamescope 2>/dev/null
          fi ) >/dev/null 2>&1 &
    fi
fi

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

# Audio: PipeWire + pulse compat + WirePlumber. The previous session's
# daemons survive a gamescope crash/respawn (a half-dead set, e.g. no
# wireplumber, makes PipeWire clients hang), so always start a fresh trio.
for d in wireplumber pipewire-pulse pipewire; do pkill -x "$d" 2>/dev/null; done
sleep 0.3
pipewire >/dev/null 2>&1 &
pipewire-pulse >/dev/null 2>&1 &
wireplumber >/dev/null 2>&1 &
# Route audio to the TV (HDMI) unless the user picked another output.
( sleep 3; foyer-ctl audio output/restore ) >/dev/null 2>&1 &

# Launcher: packaged (/usr/bin/foyer + /usr/share/foyer) or the interim
# /opt/htpc/launcher tree.
if [ -x /opt/htpc/launcher/foyer ]; then
    cd /opt/htpc/launcher
    LAUNCHER=./foyer
else
    cd /usr/share/foyer 2>/dev/null || cd /
    LAUNCHER=foyer
fi
ARGS="-c $FOYER_CONF"
[ -f "$FOYER_CONF/layout.xml" ] && [ ! -f "$FOYER_CONF/layout.toml" ] && ARGS="$ARGS -l $FOYER_CONF/layout.xml"

# gamescope needs a Vulkan driver with DRM support. If it dies right away
# (unsupported/virtual GPU), run Foyer straight on KMS so the box still shows
# a UI (apps then need their own fullscreen KMS/Wayland support).
FAILS=/run/foyer/gamescope-fails
if [ "$(cat "$FAILS" 2>/dev/null || echo 0)" -lt 2 ]; then
    start=$(date +%s)
    # shellcheck disable=SC2086
    gamescope $GS_ARGS -- $LAUNCHER $ARGS
    rc=$?
    if [ $rc -ne 0 ] && [ $(( $(date +%s) - start )) -lt 10 ]; then
        echo $(( $(cat "$FAILS" 2>/dev/null || echo 0) + 1 )) > "$FAILS"
    else
        rm -f "$FAILS"
    fi
    exit $rc
fi
echo "foyer-session: gamescope unavailable; running Foyer on KMS" >&2
export SDL_VIDEO_DRIVER=kmsdrm
# shellcheck disable=SC2086
exec $LAUNCHER $ARGS
