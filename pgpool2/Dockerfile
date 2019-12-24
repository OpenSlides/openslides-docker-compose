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
    pgpool2 \
    postgresql-client && \
  rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint
COPY pcp-wrapper.sh /usr/local/bin/pool-info

ENTRYPOINT entrypoint
# CMD ['pgpool', '-n']
