from catatnight/postfix

RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /dev/stdout /var/log/mail.log && \
    ln -sf /dev/stderr /var/log/mail.err
