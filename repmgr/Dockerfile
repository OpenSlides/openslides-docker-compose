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
    openssh-client \
    supervisor \
    gettext-base \
  && rm -rf /var/lib/apt/lists/*

COPY repmgr-promote.sh /usr/local/bin/repmgr-promote
COPY repmgr.conf.in /etc/
RUN touch /etc/repmgr.conf && chown postgres /etc/repmgr.conf

COPY pg_hba.conf /var/lib/postgresql/

COPY current-primary.sh /usr/local/bin/current-primary
COPY entrypoint.sh /usr/local/bin/entrypoint
COPY cluster-setup.sh /usr/local/sbin/cluster-setup
COPY pg_backuptrigger.sh /usr/local/bin/pg_backuptrigger

# SSH config
RUN rm /etc/ssh/ssh_host_*_key*
RUN echo "HostKey /var/lib/postgresql/.ssh/ssh_host_ed25519_key" >> /etc/ssh/sshd_config
RUN mkdir -p -m 700 /var/lib/postgresql/.ssh && \
      chown postgres:postgres /var/lib/postgresql/.ssh

RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisord.conf

WORKDIR "/var/lib/postgresql/"
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
