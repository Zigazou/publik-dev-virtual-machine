#!/bin/bash

DIALOG_TITLE="Creation of a VirtualBox virtual machine for Publik dev"

# Automatically determines how many steps this script has.
STEPS=$(grep '^show_progression' "$0" | wc --lines)
STEP=0

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
        --infobox "$message\n\n$date $2 [$$]: $message (line=$1, rc=$rc)" 10 70
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

# Read four lines from stdin and set global variables. This function is meant
# to be used only by the ask_variables function.
function read_variables() {
    read VM_NAME
    read VM_CPU
    read VM_DISK_SIZE
    read VM_RAM_SIZE
}

# Ask user for some variables (password and proxy).
function ask_variables() {
    exec 3>&1
    read_variables < <(dialog \
        --backtitle "$DIALOG_TITLE" \
        --title "Virtual machine settings" \
        --mixedform "Modify the settings according to your wishes" 13 60 6 \
        "Name"             1 1 ""      1 18 30 100 0 \
        "Number of CPU(s)" 2 1 "2"     2 18  3   3 0 \
        "Disk size (MB)"   3 1 "20000" 3 18  8  16 0 \
        "Memory size (MB)" 4 1 "2048"  4 18  6  16 0 \
        2>&1 1>&3)

    exec 3>&-
}

# Ensures dialog command is installed.
which dialog > /dev/null \
    || (echo "ERROR: the dialog command is missing." >&2 ; exit 1)

# Ensures VBoxManage is installed.
assert "VBoxManage command not found" which VBoxManage

# Look for publik ISO image.
set publik*.iso
assert "No publik*.iso image found" test "$1" != ""
VM_ISO=$(readlink --canonicalize-existing "$1")

# Ask for the new virtual machine parameters.
ask_variables

# Create the virtual machine.
show_progression "Creating $VM_NAME virtual machine"
VM_SETTINGS_FILE=$(VBoxManage createvm \
    --name "$VM_NAME" \
    --ostype "Debian_64" \
    --register \
    | sed --quiet "/Settings file:/s/^.*'\([^']*\)'.*\$/\\1/gp"
    )

VM_DIR=$(dirname "$VM_SETTINGS_FILE")

assert "Unable to create virtual machine $VM_NAME" test -r "$VM_SETTINGS_FILE"
assert "Unable to create virtual machine $VM_NAME" test -r "$VM_DIR"

# Set virtual machine parameters.
show_progression "Setting virtual machine parameters"
assert "Unable to set virtual machine parameters" \
    VBoxManage modifyvm "$VM_NAME" \
        --cpus "$VM_CPU" \
        --memory "$VM_RAM_SIZE" \
        --vram 1

assert "Unable to disable audio" \
    VBoxManage modifyvm "$VM_NAME" \
        --audio none

assert "Unable to set network parameters" \
    VBoxManage modifyvm "$VM_NAME" \
        --nic1 bridged \
        --bridgeadapter1 eno1

# Create virtual hard drive.
show_progression "Creating virtual hard drive"
assert "Unable to create virtual hard drive" \
    VBoxManage createhd \
        --filename "$VM_DIR/harddrive.vdi" \
        --size "$VM_DISK_SIZE" \
        --variant Standard

# Create SATA controller.
show_progression "Creating SATA controller"
assert "Unable to create storage controller" \
    VBoxManage storagectl "$VM_NAME" \
        --name "SATA Controller" \
        --add sata \
        --bootable on

# Attach virtual hard drive.
show_progression "Attaching virtual hard drive"
assert "Unable to attach virtual hard drive" \
    VBoxManage storageattach "$VM_NAME" \
        --storagectl "SATA Controller" \
        --port 0 \
        --device 0 \
        --type hdd  \
        --medium "$VM_DIR/harddrive.vdi"

# Create IDE controller.
show_progression "Creating IDE controller"
assert "Unable to create IDE controller" \
    VBoxManage storagectl "$VM_NAME" \
        --name "IDE Controller" \
        --add ide

# Attach ISO image.
show_progression "Attaching ISO image"
assert "Unable to attach ISO image" \
    VBoxManage storageattach "$VM_NAME" \
        --storagectl "IDE Controller"  \
        --port 0 \
        --device 0 \
        --type dvddrive \
        --medium "$VM_ISO"

end_progression "Virtual machine created!"
sleep 1

# Do we start the virtual machine now?
dialog \
    --backtitle "$DIALOG_TITLE" \
    --title "And now..." \
    --yesno "Do you want to start your new Publik VirtualBox machine?" 5 70 \
    && VBoxManage startvm "$VM_NAME"

