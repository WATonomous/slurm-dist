#!/bin/bash

set -o errexit -o nounset -o pipefail

if [ ! -d /var/spool/slurmctld ]; then
    echo "/var/spool/slurmctld does not exist. Creating it."
    mkdir -p /var/spool/slurmctld
fi

chown slurm: /var/spool/slurmctld

/usr/bin/supervisord -c /etc/supervisord.conf