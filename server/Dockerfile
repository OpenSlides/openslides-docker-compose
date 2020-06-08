FROM python:3.7-slim AS base

ENV DEBIAN_FRONTEND noninteractive
ENV DEBIAN_PRIORITY critical
ENV DEBCONF_NOWARNINGS yes
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE 1

# Variables relevant for CMD
ENV DJANGO_SETTINGS_MODULE settings
ENV PYTHONPATH personal_data/var/

RUN mkdir -p /app
WORKDIR /app
RUN useradd -m openslides
RUN chown -R openslides /app

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
    postgresql-client \
    rsync \
    wait-for-it \
    wget \
    xz-utils

# Install additional tools
RUN apt-get install --no-install-recommends -y \
  dnsutils \
  iputils-ping \
  netcat \
  procps \
  traceroute \
  vim

# Install saml requirements
RUN apt-get install --no-install-recommends -y \
  libxml2-dev \
  libxmlsec1-dev \
  libxmlsec1-openssl \
  pkg-config

# Clone OpenSlides repo
USER openslides
ARG REPOSITORY_URL=https://github.com/OpenSlides/OpenSlides.git
ARG GIT_CHECKOUT=master
RUN git clone --no-checkout -- $REPOSITORY_URL . && \
      git checkout $GIT_CHECKOUT

USER root
RUN pip install -r requirements/production.txt -r requirements/big_mode.txt && \
      rm -rf /root/.cache/pip

# RUN printf "Backend built on %s:\n\n Repository: %s\n Branch:     %s\n\n%s\n" \
#   "$(date)" \
#   "$REPOSITORY_URL" \
#   "$(git rev-parse --abbrev-ref HEAD)" \
#   "$(git show -s --format=raw)" > /app/image-version.txt

RUN rm -rf .git /var/lib/apt/lists/*

USER openslides

COPY openslides-config.sh /usr/local/bin/openslides-config
COPY entrypoint /usr/local/sbin/
ENTRYPOINT ["/usr/local/sbin/entrypoint"]
CMD ["gunicorn", "-w", "8", "--preload", "-b", "0.0.0.0:8000", "-k", \
  "uvicorn.workers.UvicornWorker", "openslides.asgi:application"]
