FROM python:3.7-slim

RUN mkdir /app

RUN apt -y update && \
  apt -y upgrade && \
  apt install -y libpq-dev curl wget xz-utils bzip2 git gcc gnupg2 make g++
RUN curl -sL https://deb.nodesource.com/setup_11.x | bash -
RUN apt -y install nodejs
RUN npm install -g @angular/cli@latest
RUN useradd -m openslides
RUN chown -R openslides /app
WORKDIR /app

ARG BRANCH
ARG REPOSITORY_URL
ARG COMMIT_HASH

USER openslides
RUN git clone -b $BRANCH $REPOSITORY_URL .
RUN git reset --hard $COMMIT_HASH
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
  ./node_modules/.bin/compodoc -t -p src/tsconfig.app.json -n 'OpenSlides Documentation' -d ../openslides/static/doc -e html && \
  rm -fr /app/client/node_modules

RUN python manage.py createsettings
RUN sed -i "s/EMAIL_HOST = 'localhost'/EMAIL_HOST = 'postfix'/" personal_data/var/settings.py
RUN sed -i 's/EMAIL_PORT = 587/EMAIL_PORT = 25/' personal_data/var/settings.py
RUN sed -i "s/EMAIL_HOST_USER = ''/EMAIL_HOST_USER = 'openslides'/" personal_data/var/settings.py
RUN sed -i "s/EMAIL_HOST_PASSWORD = ''/EMAIL_HOST_PASSWORD = 'openslides'/" personal_data/var/settings.py
RUN sed -i 's/use_redis = False/use_redis= True/' personal_data/var/settings.py
RUN sed -i 's#"hosts": \[("localhost"#"hosts": \[("redis"#' personal_data/var/settings.py
RUN sed -i 's#redis://127.0.0.1#redis://redis:6379/0#' personal_data/var/settings.py
RUN sed -i "s/'host': '127.0.0.1',/'host': 'redis',/" personal_data/var/settings.py
RUN sed -i "s/'ENGINE': 'django.db.backends.sqlite3',/'ENGINE': 'django.db.backends.postgresql',/" personal_data/var/settings.py
RUN sed -i "s/'NAME': os.path.join(OPENSLIDES_USER_DATA_DIR, 'db.sqlite3'),/'NAME': 'openslides',\n        'USER': 'openslides',\n        'PASSWORD': 'openslides',\n        'HOST': 'postgres',\n        'PORT': '5432'/" personal_data/var/settings.py
