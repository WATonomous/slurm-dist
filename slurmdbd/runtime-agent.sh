#!/bin/bash

set -o errexit -o nounset -o pipefail

function update_passwd_group() {
    cat /etc/passwd.system /etc/runtime_config/passwd > /etc/passwd
    cat /etc/group.system /etc/runtime_config/group > /etc/group
}

function watch_runtime_config() {
    inotifywait --monitor --recursive --event create,delete,modify,attrib,move /etc/runtime_config | while read FILE; do
        echo "Detected changes in /etc/runtime_config/. Updating /etc/passwd and /etc/group after a short delay."
        # approximate debounce
        timeout 3 cat > /dev/null || true
        echo "Updating /etc/passwd and /etc/group"
        update_passwd_group
    done
}

function update_slurmdbd_conf() {
    cp /etc/slurmdbd_config/slurmdbd.conf /etc/slurm/slurmdbd.conf
    chown slurm: /etc/slurm/slurmdbd.conf
}

function watch_slurmdbd_config() {
    inotifywait --monitor --recursive --event create,delete,modify,attrib,move /etc/slurmdbd_config | while read FILE; do
        echo "Detected changes in /etc/slurmdbd_config/. Updating /etc/slurm/slurmdbd.conf after a short delay."
        # approximate debounce
        timeout 3 cat > /dev/null || true

        echo "Updating /etc/slurm/slurmdbd.conf"
        update_slurmdbd_conf

        echo "Restarting slurmdbd"
        /usr/bin/supervisorctl restart slurmdbd
    done
}

# Inital update
update_passwd_group
update_slurmdbd_conf

# Continuously watch for changes
watch_runtime_config &
watch_slurmdbd_config &

wait