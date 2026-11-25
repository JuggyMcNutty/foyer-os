# shellcheck shell=sh
# Shared helpers: load a profile and expand logical packages.
load_profile() {
    _p="$1"
    case "$_p" in */*) ;; *) _p="$REPO/profiles/$_p.sh" ;; esac
    [ -f "$_p" ] || { echo "unknown profile: $1 (see profiles/)" >&2; exit 1; }
    BASE=alpine; ARCH=x86_64; WIFI=no; BT=no; BOOT=uefi; SWAP_MB=0; EXTRA_PKGS=""; FIRMWARE=""; RENDER_MAX=native
    ASSET_BUDGET_MB=96; NET=net-ethernet; KERNEL=kernel-lts; GPU=gpu-generic; HOSTNAME=foyer
    # shellcheck disable=SC1090
    . "$_p"
    PROFILE_NAME=$(basename "$_p" .sh)
}

# expand_pkgs BASE logical... -> distro package names
expand_pkgs() {
    _base=$1; shift
    _map="$REPO/profiles/base/$_base.pkgs"
    for _l in "$@"; do
        _line=$(awk -v k="$_l" '$1 == k { $1 = ""; print; exit }' "$_map")
        if [ -n "$_line" ]; then echo "$_line"; else echo "$_l"; fi
    done | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' '
}

profile_pkgs() {
    _logical="base $KERNEL $FIRMWARE $GPU $NET $EXTRA_PKGS"
    [ "$WIFI" = yes ] && _logical="$_logical net-wifi"
    [ "$BT" = yes ] && _logical="$_logical bt"
    case "$BOOT" in uefi) _logical="$_logical boot-uefi" ;; bios) _logical="$_logical boot-bios" ;; both) _logical="$_logical boot-uefi boot-bios" ;; esac
    # shellcheck disable=SC2086
    expand_pkgs "$BASE" $_logical
}

# session.conf lines derived from the profile
profile_session_conf() {
    echo "# foyer-os session display mode (profile: $PROFILE_NAME)."
    echo "# Empty WIDTH/HEIGHT = monitor's preferred mode (EDID)."
    echo "WIDTH="
    echo "HEIGHT="
    echo "RATE="
    if [ "$RENDER_MAX" != native ]; then
        echo "RENDER_WIDTH=${RENDER_MAX%x*}"
        echo "RENDER_HEIGHT=${RENDER_MAX#*x}"
    else
        echo "RENDER_WIDTH="
        echo "RENDER_HEIGHT="
    fi
}
