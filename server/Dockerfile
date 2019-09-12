FROM python:3.7-slim

ENV DEBIAN_FRONTEND noninteractive
ENV DEBIAN_PRIORITY critical
ENV DEBCONF_NOWARNINGS yes
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE 1

# Variables relevant for CMD
ENV DJANGO_SETTINGS_MODULE settings
ENV PYTHONPATH personal_data/var/

RUN mkdir -p /build/app
WORKDIR /build/app
RUN useradd -m openslides
RUN chown -R openslides /build/app

RUN apt-get -y update && apt-get -y upgrade && \
  apt-get install --no-install-recommends -y \
    apt-transport-https \
    bzip2 \
    curl \
    g++ \
    gcc \
    git \
    gnupg2 \
    libpq-dev \
    make \
    rsync \
    sudo \
    wait-for-it \
    wget \
    xz-utils

# Install basic debugging tools
RUN apt-get install --no-install-recommends -y \
  dnsutils \
  iputils-ping \
  netcat \
  procps \
  traceroute

# Install saml requirements
RUN apt-get install --no-install-recommends -y \
  libxml2-dev \
  libxmlsec1-dev \
  libxmlsec1-openssl \
  pkg-config

# Install script which will be used to copy the files build below into the
# container's volume upon creation.
COPY update-openslides-app.sh /usr/local/bin/update-openslides-app
RUN umask 0222 && \
  echo 'openslides ALL=(root) NOPASSWD: /usr/local/bin/update-openslides-app' \
  > /etc/sudoers.d/openslides

# NodeJS
# Add included apt config and OpenPGP key for increased reproducibility (avoids
# curl/bash invocation (see below))
COPY node-apt/nodesource.list /etc/apt/sources.list.d/
COPY node-apt/nodesource.gpg.key /root/
RUN apt-key add /root/nodesource.gpg.key
# RUN curl -sL https://deb.nodesource.com/setup_11.x | bash -
RUN apt-get update && apt-get -y install nodejs
RUN rm -rf /var/lib/apt/lists/*

RUN npm install -g @angular/cli@latest

USER openslides
ARG REPOSITORY_URL=https://github.com/OpenSlides/OpenSlides.git
ARG GIT_CHECKOUT=master
RUN git clone --no-checkout -- $REPOSITORY_URL .
RUN git checkout $GIT_CHECKOUT

USER root
RUN printf "Built on %s:\n\n Repository: %s\n Branch:     %s\n\n%s\n" \
  "$(date)" \
  "$REPOSITORY_URL" \
  "$(git rev-parse --abbrev-ref HEAD)" \
  "$(git show -s --format=raw)" > /build/image-version.txt
RUN rm -rf .git
RUN pip install -r requirements/production.txt -r requirements/big_mode.txt

USER openslides
RUN ng config -g cli.warnings.versionMismatch false && \
  cd client && \
  npm install
RUN cd client && \
  npm run build && \
  rm -fr /build/app/client/node_modules

WORKDIR /app

COPY entrypoint /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["gunicorn", "-w", "8", "--preload", "-b", "0.0.0.0:8000", "-k", \
  "uvicorn.workers.UvicornWorker", "openslides.asgi:application"]
