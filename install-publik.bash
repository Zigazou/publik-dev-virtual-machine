#!/bin/bash
# This script aims to install a Publik developer instance in a virtual machine
# executing Debian 9.6.0. It requires the OS to have one user publik with publik
# as password.
#
# It supports configuration of a proxy making it possible to use this script
# in a corporate environment.
#
# THIS SCRIPT IS NOT MEANT FOR PRODUCTION SITES!
#
# It requires the following packages to be installed:
# - openssh-server
# - build-essential
# - console-data
# - console-setup
# - dialog
# - libjs-pdf
# - git
# - postgresql
# - ansible (from stretch-backports)
#

if [ "$USER" != "publik" ]
then
    echo "This script should only be run in a virtual machine targeted at"
    echo "Publik's developers. You shouldn't have to run it by hand."
    exit 1
fi

# The title shown on top of each Dialog window.
DIALOG_TITLE="Installation of Publik developer instance"

# The sudo password is hardcoded. This is why this script is not meant for
# production sites.
SUDO_PASSWORD="publik"

# Proxy settings.
HTTP_PROXY=""

# Execute an Ansible command showing only TASK lines in Dialog. Exits on error.
# $1=title
# $@=command and arguments
function exec_ansible() {
    local title="$1"
    shift

    # Stdbuf forces sed to immediately filter every line it receives.
    # Sed keeps only the current task executed by Ansible making it more
    # suitable to display in a Dialog progressbox.
    "$@" 2>&1 \
        | tee -a ~/install-publik.log \
        | stdbuf -oL sed -n '/^TASK/s/.*\[\([^]]*\)\].*/\1/p' \
        | dialog --backtitle "$DIALOG_TITLE" --progressbox "$title" 20 76

    # Get return code from the first command in the last pipe.
    local rc=${PIPESTATUS[0]}
    [ $rc -eq 0 ] && return 0

    # Exits on first error.
    echo "An error occured, please consult ~/install-publik.log" >&2
    exit $rc
}

# Execute a shell command showing in Dialog. Exits on error.
# $1=title
# $@=command and arguments
function exec_command() {
    local title="$1"
    shift
    "$@" 2>&1 \
        | tee -a ~/install-publik.log \
        | dialog --backtitle "$DIALOG_TITLE" --progressbox "$title" 20 76

    # Get return code from the first command in the last pipe.
    local rc=${PIPESTATUS[0]}
    [ $rc -eq 0 ] && return 0

    # Exits on first error.
    echo "An error occured, please consult ~/install-publik.log" >&2
    exit $rc
}

# Setup proxy settings according to proxy settings found in /etc/apt/apt.conf.
function setup_proxy() {
    # Do nothing if there is no /etc/apt/apt.conf file.
    [ -r /etc/apt/apt.conf ] || return 0

    export HTTP_PROXY=$(sed --quiet '/Acquire::http::Proxy/s/^.*"\(.*\)".*$/\1/p' \
        /etc/apt/apt.conf)

    [ "$HTTP_PROXY" == "" ] && return 0

    # Exports standard HTTP?_PROXY environment variables.
    export HTTPS_PROXY="${HTTP_PROXY:0:4}s${HTTP_PROXY:4}"
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"

    # Set proxy settings for Git.
    git config --global http.proxy "$HTTP_PROXY"
    git config --global https.proxy "$HTTPS_PROXY"
}

# Generate a line to append to /etc/hosts that declare *.dev.publik.love hosts.
function update_etc_hosts() {
    echo 127.0.0.1 localhost \
        agent-combo.dev.publik.love \
        authentic.dev.publik.love \
        bijoe.dev.publik.love \
        chrono.dev.publik.love \
        combo.dev.publik.love \
        fargo.dev.publik.love \
        hobo.dev.publik.love \
        passerelle.dev.publik.love \
        wcs.dev.publik.love
}

# Patch ansible.cfg and install.yml.
function patch_files() {
    if [ "$HTTP_PROXY" != "" ]
    then
        # https_proxy used by Ansible needs http scheme, not https scheme.
        echo "  environment:" >> install.yml
        echo "    http_proxy: $HTTP_PROXY" >> install.yml
        echo "    https_proxy: $HTTP_PROXY" >> install.yml
    fi

    patch -p1 <<EOF
diff --git a/ansible.cfg b/ansible.cfg
index d7649f6..5cbcdb0 100644
--- a/ansible.cfg
+++ b/ansible.cfg
@@ -1,2 +1,4 @@
+[ssh_connection]
+pipelining = true
 [defaults]
-hash_behaviour = merge
\ No newline at end of file
+hash_behaviour = merge
-- 
2.11.0
EOF
}

# Setup proxy settings.
setup_proxy

# Initialize sudo password, don’t ask user for the password.
echo "$SUDO_PASSWORD" | sudo --prompt="" --stdin true

# Modify /etc/hosts if it does not contain *.publik.love hostnames.
grep --quiet ".dev.publik.love" /etc/hosts \
    || update_etc_hosts | sudo tee -a /etc/hosts > /dev/null

# Waiting for an Internet connection.
dialog \
    --backtitle "$DIALOG_TITLE" \
    --infobox "Waiting for an Internet connection..." 3 70

until wget --quiet --spider "http://git.entrouvert.org"
do
    sleep 1
done

# Clone Publik installer.
exec_command "Cloning Publik installer" \
    git clone "http://git.entrouvert.org/publik-devinst.git"

cd publik-devinst

# Patch files.
exec_command "Patching files" patch_files

# Run install playbook.
exec_ansible "Running install playbook" \
    ansible-playbook -i inventory.yml install.yml \
        --extra-vars "ansible_become_pass=$SUDO_PASSWORD"

# Run deploy-tenants playbook.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
exec_ansible "Running deploy-tenants playbook" \
    ansible-playbook -i inventory.yml deploy-tenants.yml

# Everything ends well!
myip=$(ip address \
    | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

dialog \
    --backtitle "$DIALOG_TITLE" \
    --infobox "Publik developer instance has been installed.

It runs on ${myip}.
  
You should access it using *.dev.publik.love domains.

Connect using user=admin@localhost, password=admin" 9 70

