#!/bin/bash

set -o errexit -o nounset -o pipefail

if [ ! -d /var/spool/slurm/ ]; then
    echo "/var/spool/slurm/ does not exist. Creating it."
    mkdir -p /var/spool/slurm/
fi

chown slurm: /var/spool/slurm/

/usr/bin/supervisord -c /etc/supervisord.conf