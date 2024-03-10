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

function watch_slurm_config() {
    inotifywait --monitor --recursive --event create,delete,modify,attrib,move /etc/slurm | while read FILE; do
        echo "Detected changes in /etc/slurm/. Running scontrol reconfigure after a short delay."
        # approximate debounce
        timeout 3 cat > /dev/null || true
        echo "Running scontrol reconfigure"
        /opt/slurm/bin/scontrol reconfigure
    done
}

# Inital update
update_passwd_group

# Continuously watch for changes
watch_runtime_config &
watch_slurm_config &

wait