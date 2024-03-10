FROM ubuntu:22.04 as builder

RUN apt-get update && apt-get install -y wget build-essential fakeroot devscripts equivs

# Download code and install build dependencies
RUN mkdir /tmp/builder \
    && cd /tmp/builder \
    && wget -q https://download.schedmd.com/slurm/slurm-23.11.4.tar.bz2 \
    && tar -xf slurm*.tar.bz2 \
    && cd slurm* \
    && mk-build-deps --install --tool "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes" debian/control

# Install packages to enable building of plugins
# https://slurm.schedmd.com/quickstart_admin.html#prereqs
RUN apt-get update && apt-get install -y \
    # for the auth/munge plugin
    libmunge-dev \
    # for the mysql plugin
    libmysqlclient-dev \
    # for the cgroup/v2 plugin
    libhwloc-dev \
    libdbus-1-dev \
    # for HDF5 job accounting
    libhdf5-dev \
    # for Lua API
    liblua5.3-dev \
    # for NVIDIA GPU support
    libnvidia-ml-dev \
    # for readline support
    libreadline-dev \
    # for rest API
    libhttp-parser-dev \
    libjson-c-dev \
    libyaml-dev \
    libjwt-dev

RUN cd /tmp/builder/slurm* \
    && ./configure --prefix /opt/slurm --sysconfdir /etc/slurm  \
    && make -j$(nproc) install \
    && cd / \
    && rm -rf /tmp/builder


# Package the built slurm package
FROM ubuntu:22.04 as packager

COPY --from=builder /opt/slurm /opt/slurm

RUN tar -C /opt -czf /opt/slurm.tar.gz slurm


FROM ubuntu:22.04 as slurmctld

# Create the users. 60430 is the default slurm uid. 60429 for munge is arbitrary.
RUN groupadd --gid 64029 munge && useradd --uid 64029 --gid 64029 --home-dir /var/spool/munge --no-create-home --shell /bin/false munge
RUN groupadd --gid 64030 slurm && useradd --uid 64030 --gid 64030 --home-dir /var/spool/slurm --no-create-home --shell /bin/false slurm

# Install runtime dependencies
RUN apt-get update && apt-get install libmunge2 munge supervisor -y

RUN mkdir /run/munge && chown munge:munge /run/munge

# Copy the built slurm binaries from the builder stage
COPY --from=builder /opt/slurm /opt/slurm

# Default configuration options in supervisord.conf that can be overridden at runtime
ENV MUNGED_ARGS=
ENV SLURMCTLD_ARGS=
# This allows the user to use a pre-existing munge key
ENV MUNGE_KEY_IMPORT_PATH=/etc/munge/munge.imported.key

# Configure supervisor
RUN cat > /etc/supervisord.conf <<EOF
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log

[unix_http_server]
file=/var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[program:munge]
command=/usr/bin/bash -c 'if [ -s "%(ENV_MUNGE_KEY_IMPORT_PATH)s" ]; then cp "%(ENV_MUNGE_KEY_IMPORT_PATH)s" /etc/munge/munge.key; fi; /usr/sbin/munged --foreground %(ENV_MUNGED_ARGS)s'
autostart=true
autorestart=true
user=munge
stdout_logfile=/var/log/supervisor/munge.out
stderr_logfile=/var/log/supervisor/munge.err
priority=100

[program:slurmctld]
command=/opt/slurm/sbin/slurmctld -D %(ENV_SLURMCTLD_ARGS)s
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/slurmctld.out
stderr_logfile=/var/log/supervisor/slurmctld.err
priority=150

EOF

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
