FROM debian:buster

ENV DEBIAN_FRONTEND noninteractive
ENV DEBIAN_PRIORITY critical
ENV DEBCONF_NOWARNINGS yes

RUN apt-get update && \
  apt-get install -y \
    iproute2 \
    man \
    less \
    vim \
    postgresql-11 \
    postgresql-client \
    repmgr \
    wait-for-it \
    pgtop \
    rsync \
    openssh-server \
    openssh-client

RUN rm -rf /var/lib/apt/lists/*

COPY repmgr.conf.in /etc/
RUN touch /etc/repmgr.conf && chown postgres /etc/repmgr.conf
COPY pg_hba.conf /var/lib/postgresql/
COPY entrypoint.sh /usr/local/bin/entrypoint

COPY id_ed25519* /var/lib/postgresql/.ssh/
COPY id_ed25519 /etc/ssh/ssh_host_ed25519_key
COPY id_ed25519.pub /etc/ssh/ssh_host_ed25519_key.pub

RUN pg_dropcluster 11 main

USER postgres

ENTRYPOINT entrypoint