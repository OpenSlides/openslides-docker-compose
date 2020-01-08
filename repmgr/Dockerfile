FROM debian:buster

ENV DEBIAN_FRONTEND noninteractive
ENV DEBIAN_PRIORITY critical
ENV DEBCONF_NOWARNINGS yes

RUN apt-get update && \
  apt-get install --yes --no-install-recommends \
    iproute2 \
    man \
    less \
    vim \
    postgresql-11 \
    postgresql-client \
    repmgr \
    pgtop \
    rsync \
    openssh-server \
    openssh-client && \
  rm -rf /var/lib/apt/lists/*

COPY repmgr.conf.in /etc/
RUN touch /etc/repmgr.conf && chown postgres /etc/repmgr.conf
COPY pg_hba.conf /var/lib/postgresql/
COPY current-primary.sh /usr/local/bin/current-primary

# SSH config
COPY ssh_host_ed25519_key* /etc/ssh/
COPY id_ed25519* /var/lib/postgresql/.ssh/
COPY postgres_known_hosts /var/lib/postgresql/.ssh/known_hosts
COPY postgres_authorized_keys /var/lib/postgresql/.ssh/authorized_keys

RUN chmod 600 /etc/ssh/ssh_host_ed25519_key && \
    chmod 600 /var/lib/postgresql/.ssh/id_ed25519 && \
    chmod 700 /var/lib/postgresql/.ssh/ && \
    chown -R postgres:postgres /var/lib/postgresql/.ssh/
RUN echo "HostKey /etc/ssh/ssh_host_ed25519_key" >> /etc/ssh/sshd_config

COPY root-entrypoint.sh /usr/local/sbin/root-entrypoint
COPY entrypoint.sh      /usr/local/bin/entrypoint

ENTRYPOINT ["/usr/local/sbin/root-entrypoint"]
CMD ["repmgrd", "-f", "/etc/repmgr.conf", "--pid-file", \
    "/dev/shm/repmgrd.pid", "--daemonize=false"]
