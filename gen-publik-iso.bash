#!/bin/bash
# This script creates a new ISO image file by adding a pressed.cfg file to an
# existing debian ISO image file. This is necessary because ISO image files are
# read-only filesystems.

DIALOG_TITLE="Generation of Debian ISO install image for Publik"

# Automatically determines how many steps this script has.
STEPS=$(grep '^show_progression' "$0" | wc --lines)
STEP=0

# Global variables.
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
SUDO_PASS=""
HTTP_PROXY=""

# Exit if a command does not end well.
function assert() {
    local message="$1"
    shift
    "$@"
    local rc=$?
    [ $rc -eq 0 ] && return 0
    set $(caller)
    local date=$(date "+%Y-%m-%d %T%z")
    dialog \
        --backtitle "$DIALOG_TITLE" \
        --infobox "$message\n\n$date $2 [$$]: $message (line=$1, rc=$rc)" 5 70
    exit $rc
}

# Show progression.
function show_progression() {
    local step_name="$1"
    local percent=$((100 * STEP / STEPS))

    echo "$percent" | dialog \
        --backtitle "$DIALOG_TITLE" \
        --gauge "$step_name" 6 70

    STEP=$((STEP + 1))
}

# End progression at 100%.
function end_progression() {
    show_progression "$1"
}

# Calculate free space in bytes where a file resides.
function freespace() {
    df --block-size=1 "$(dirname "$1")" \
        | tail -1 \
        | sed 's/  */ /g' \
        | cut --fields=4 --delimiter=' '
}

# Display script usage.
function usage() {
    echo "iso-add-file.bash source.iso destination.iso preseed.cfg install.bash"
    echo "    - source.iso must exist"
    echo "    - destination.iso must not exist"
    echo "    - preseed.cfg must exist"
    echo "    - install.bash must exist, must start with 'install' and ends"
    echo "      with '.bash'"
    echo
    exit 0
}

# Read four lines from stdin and set global variables. This function is meant
# to be used only by the ask_variables function.
function read_variables() {
    read SUDO_PASS
    read PROXY_HOST
    read PROXY_PORT
    read PROXY_USER
    read PROXY_PASS
}

# Ask user for some variables (password and proxy).
function ask_variables() {
    exec 3>&1
    read_variables < <(dialog \
        --backtitle "$DIALOG_TITLE" \
        --title "Proxy settings" \
        --insecure \
        --mixedform "Enter Proxy settings (leave empty to ignore)" 13 60 6 \
        "SUDO password" 1 1 "" 1 15 16 100 1 \
        "Host" 3 1 "" 3 6 40 100 0 \
        "Port" 4 1 "3128" 4 6 6 6 0 \
        "User" 5 1 "" 5 6 16 100 0 \
        "Pass" 6 1 "" 6 6 16 100 1 \
        2>&1 1>&3)

    exec 3>&-
}

# Setup proxy settings according to variables.
function setup_proxy() {
    [ "$PROXY_HOST" == "" ] && return 0

    HTTP_PROXY="http://"

    if [ "$PROXY_USER" != "" ]
    then
        HTTP_PROXY="$HTTP_PROXY$PROXY_USER"
        [ "$PROXY_PASS" != "" ] && HTTP_PROXY="$HTTP_PROXY:$PROXY_PASS"
        HTTP_PROXY="$HTTP_PROXY@"
    fi

    HTTP_PROXY="$HTTP_PROXY$PROXY_HOST"
    [ "PROXY_PORT" != "" ] && HTTP_PROXY="$HTTP_PROXY:$PROXY_PORT"
    HTTP_PROXY="$HTTP_PROXY/"
}

# Makes Grub run Debian installer with preseed.cfg by default.
function gen_isolinux_cfg() {
    cat <<EOF
path 
label auto
	menu label ^Automated install
	kernel /install.amd/vmlinuz
	append auto=true priority=critical vga=788 initrd=/install.amd/initrd.gz
default auto
prompt 0
timeout 1
EOF
}

# Generate a Bourne Shell script that will be executed at the end of Debian
# installation. It setups the systeme with everything needed to automatically
# start the installation of a Publik developer instance.
function prepare_system() {
    cat <<EOF
#!/bin/sh
# Install stetch-backports repository.
echo >> /target/etc/apt/sources.list
echo 'deb http://deb.debian.org/debian stretch-backports main contrib non-free' \
    >> /target/etc/apt/sources.list
in-target apt-get update

# Install Ansible from stretch backports.
in-target apt-get install --yes -t stretch-backports ansible

# Install install*.bash scripts in publik home directory.
cp /cdrom/install*.bash /target/home/publik
chown 1000:1000 /target/home/publik/install*.bash
chmod u+x /target/home/publik/install*.bash

# Add handy aliases.
echo "alias ll='ls -l'" > /target/home/publik/.bash_aliases
chown 1000:1000 /target/home/publik/.bash_aliases

# Execute install-publik.bash on first publik login.
touch /target/home/publik/first-install
chown 1000:1000 /target/home/publik/first-install

PROFILE="/target/home/publik/.profile"
echo 'if [ -f ~/first-install ]' >> \$PROFILE
echo 'then' >> \$PROFILE
echo '  rm --force ~/first-install' >> \$PROFILE
echo '  ~/install-publik.bash' >> \$PROFILE
echo 'fi' >> \$PROFILE

# Automatically login to publik user after booting.
mkdir -pv /target/etc/systemd/system/getty@tty1.service.d/

AUTOLOGIN="/target/etc/systemd/system/getty@tty1.service.d/autologin.conf"

echo '[Service]' >> \$AUTOLOGIN
echo 'ExecStart=' >> \$AUTOLOGIN
echo 'ExecStart=-/sbin/agetty --autologin publik --noclear %I 38400 linux' \
    >> \$AUTOLOGIN
in-target systemctl enable getty@tty1.service
EOF
}

# MKISOFS: available tool that can create an ISO image.
MKISOFS=$(which mkisofs || which genisoimage)

which dialog > /dev/null \
    || (echo "ERROR: the dialog command is missing." >&2 ; exit 1)

assert "sudo command required" which sudo
assert "mkisofs or genisoimage command required" test "$MKISOFS" != ""
assert "mktemp command required" which mktemp

# MOUNT_SRC: where the ISO source image will be mounted at.
MOUNT_SRC=$(mktemp -d)

# MOUNT_DST: where the new ISO destination image will be built.
MOUNT_DST=$(mktemp -d)

# ISO_SRC: full path to the ISO source image.
set debian*.iso
ISO_SRC=$(readlink --canonicalize-existing "$1")

# ISO_DST: full path to the ISO destination image.
ISO_DST=$(readlink --canonicalize \
    "$(dirname "$ISO_SRC")/publik-$(basename "$ISO_SRC")")

# PRESEED: full path to the preseed.cfg file.
PRESEED=$(readlink --canonicalize-existing "$(dirname "$ISO_SRC")/preseed.cfg")

# INSTALL: full path to the install script.
INSTALL=$(readlink --canonicalize-existing \
    "$(dirname "$ISO_SRC")/install-publik.bash")

assert "$ISO_SRC not found" test -f "$ISO_SRC"
assert "$PRESEED not found" test -f "$PRESEED"
assert "$INSTALL not found" test -f "$INSTALL"
assert "$ISO_DST already exists" test ! -f "$ISO_DST"
assert "$MOUNT_DST is not writable" test -w "$MOUNT_DST"

# Ensures there is enough free space to create a new ISO file.
free_space_tmp=$(freespace "$MOUNT_DST")
free_space=$(freespace "$ISO_DST")
iso_file_size=$(du --block-size=1 "$ISO_SRC" | cut --fields=1)
space_needed=$((iso_file_size * 2))
assert "Not enough free space" test $space_needed -lt $free_space

# Ask for variables.
ask_variables
setup_proxy

assert "SUDO password is required to mount ISO images" \
    test "$SUDO_PASS" != ""

# Setup SUDO password.
echo "$SUDO_PASS" | sudo --prompt="" --stdin true

# Mount the ISO source image.
show_progression "Mounting source"
assert "Unable to mount $ISO_SRC in $MOUNT_SRC" \
    sudo mount -o loop,ro "$ISO_SRC" "$MOUNT_SRC"

# Copy all files from ISO source image to a writable directory.
show_progression "Copying files"
pushd "$MOUNT_SRC" > /dev/null
# tar is used to preserve links.
tar -cf - . | (cd "$MOUNT_DST" && tar -xf - )
popd > /dev/null

# Make temporary files modifiable.
show_progression "Making files writable"
assert "Unable to chmod temporary files" chmod -R u+w "$MOUNT_DST"

# Unmount the ISO source image.
show_progression "Unmounting source"
assert "Unable to unmount ISO source image" sudo umount "$MOUNT_SRC"
assert "Unable to remove ISO source mount point" rmdir "$MOUNT_SRC"

# Append the new files.
show_progression "Patching ISO image"
gen_isolinux_cfg > "$MOUNT_DST/isolinux/isolinux.cfg"
prepare_system > "$MOUNT_DST/prepare_system.sh"
cp "$INSTALL" "$MOUNT_DST"

# Generate a customized preseed.cfg.
if [ "$HTTP_PROXY" != "" ]
then
    diproxy="d-i mirror/http/proxy string"
    sed "s!^.*$diproxy.*\$!$diproxy $HTTP_PROXY!g" "$PRESEED" \
        > "$MOUNT_DST/preseed.cfg"
else
    cp "$PRESEED" "$MOUNT_DST"
fi

# Copy preseed.cfg into initrd.gz.
pushd "$MOUNT_DST" > /dev/null
echo "$(basename "$PRESEED")" \
    | cpio -H newc --create --quiet \
    | gzip >> "$MOUNT_DST/install.amd/initrd.gz"
popd > /dev/null

rm "$MOUNT_DST/$(basename "$PRESEED")"

# Create the ISO destination image.
show_progression "Creating new ISO image"
pushd "$MOUNT_DST" > /dev/null
assert "Unable to create ISO destination image" \
    $MKISOFS -quiet \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -joliet \
        -rock \
        -volid "PUBLIKDEV" \
        -output "$ISO_DST" \
        .
popd > /dev/null

# Remove the temporary files and directory.
show_progression "Removing temporary files"
assert "Unable to remove temporary files" rm -R "$MOUNT_DST"

end_progression "$(basename "$ISO_DST") is ready!"
sleep 1

