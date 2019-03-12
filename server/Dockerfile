FROM python:3.7-slim

ENV DEBIAN_FRONTEND noninteractive
ENV DEBIAN_PRIORITY critical
ENV DEBCONF_NOWARNINGS yes
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE 1

RUN mkdir /app

RUN apt-get -y update && apt-get -y upgrade && \
  apt-get install -y \
    apt-transport-https \
    bzip2 \
    curl \
    g++ \
    gcc \
    git \
    gnupg2 \
    libpq-dev \
    make \
    wget \
    xz-utils

# NodeJS
# Add included apt config and OpenPGP key for increased reproducibility (avoids
# curl/bash invocation (see below))
COPY node-apt/nodesource.list /etc/apt/sources.list.d/
COPY node-apt/nodesource.gpg.key /root/
RUN apt-key add /root/nodesource.gpg.key
# RUN curl -sL https://deb.nodesource.com/setup_11.x | bash -
RUN apt-get update && apt-get -y install nodejs

RUN npm install -g @angular/cli@latest
RUN useradd -m openslides
RUN chown -R openslides /app
WORKDIR /app

ARG REPOSITORY_URL
ARG GIT_CHECKOUT

USER openslides
RUN git clone --no-checkout -- $REPOSITORY_URL .
RUN git checkout $GIT_CHECKOUT
RUN rm -rf .git

USER root
RUN pip install -r requirements.txt
RUN rm -rf /var/lib/apt/lists/*

USER openslides

RUN ng config -g cli.warnings.versionMismatch false && \
  cd client && \
  npm install
RUN cd client && \
  npm run build && \
  ./node_modules/.bin/compodoc -t -p src/tsconfig.app.json \
    -n 'OpenSlides Documentation' -d ../openslides/static/doc -e html && \
  rm -fr /app/client/node_modules

RUN python manage.py createsettings
RUN sed -i \
  -e "/EMAIL_HOST\ /s/localhost/postfix/" \
  -e "/EMAIL_PORT/s/587/25/" \
  -e "/EMAIL_HOST_USER/s/''/'openslides'/" \
  -e "/EMAIL_HOST_PASSWORD/s/''/'openslides'/" \
  -e "/use_redis/s/False/True/" \
  -e "/\"hosts\":.*6379/s/localhost/redis/" \
  -e "/'host':/s/127\.0\.0\.1/redis/" \
  -e "/REDIS_ADDRESS/s/127\.0\.0\.1/redis:6379\/0/" \
  -e "/'ENGINE':\ 'django\.db\.backends/s/sqlite3/postgresql/" \
  -e "/^\s*'NAME'/s/\(^.*'NAME':\).*/\1\ 'openslides',/" \
  -e "/^\s*'NAME'/a\ \ \ \ \ \ \ \ 'USER': 'openslides',\n\ \
       'PASSWORD': 'openslides',\n\ \
       'HOST': 'postgres',\n\ \
       'PORT': '5432'" \
  personal_data/var/settings.py
