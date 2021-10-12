FROM debian:buster

EXPOSE 25

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    apt-get upgrade -y
RUN set -x; DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --purge \
    postfix \
    bsd-mailx \
    netcat || \
    sed -i 's/^myhostname = \(.*\)$/myhostname = example.com/' /etc/postfix/main.cf && \
    apt install --fix-broken

ADD entrypoint /usr/local/bin/entrypoint

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["postfix", "start-fg"]
