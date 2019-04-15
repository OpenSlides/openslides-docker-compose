FROM debian:buster

EXPOSE 25

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    apt-get upgrade -y
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --purge \
    postfix \
    bsd-mailx \
    netcat

ADD entrypoint /usr/local/bin/entrypoint

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["postfix", "start-fg"]
