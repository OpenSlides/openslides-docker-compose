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
    openssh-client \
    pgbouncer \
    postgresql-client \
    wait-for-it && \
  rm -rf /var/lib/apt/lists/*

COPY pgbouncer.ini /etc/pgbouncer/
COPY userlist.txt  /etc/pgbouncer/

RUN touch /etc/primary && \
  chown postgres:postgres /etc/primary
RUN touch /etc/pgbouncer/pgbouncer.database.ini && \
  chown postgres:postgres \
    /etc/pgbouncer/pgbouncer.database.ini

# SSH config
RUN mkdir -p -m 700 /var/lib/postgresql/.ssh && \
      chown postgres:postgres /var/lib/postgresql/.ssh

USER postgres

COPY find-primary.sh /usr/local/lib/find-primary.sh
COPY update-config.sh /usr/local/bin/update-config.sh
COPY healthcheck.sh /usr/local/bin/healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s \
  CMD healthcheck || exit 1

COPY entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT entrypoint
