FROM node:13 AS nodejs

RUN mkdir -p /build/app
WORKDIR /build/app
RUN useradd -m openslides
RUN chown -R openslides /build/app

USER root
RUN npm install -g @angular/cli@^9

# Clone OpenSlides repo
USER openslides
ARG REPOSITORY_URL=https://github.com/OpenSlides/OpenSlides.git
ARG GIT_CHECKOUT=master
RUN git clone --no-checkout -- $REPOSITORY_URL . && \
      git checkout $GIT_CHECKOUT

RUN ng config -g cli.warnings.versionMismatch false && \
  cd client && \
  npm install
RUN cd client && \
  npm run build && \
  rm -fr /build/app/client/node_modules

RUN printf "Client built on %s:\n\n Repository: %s\n Branch:     %s\n\n%s\n" \
  "$(date)" \
  "$REPOSITORY_URL" \
  "$(git rev-parse --abbrev-ref HEAD)" \
  "$(git show -s --format=raw)" > /build/app/openslides/static/client-version.txt

FROM nginx
COPY --from=nodejs /build/app/openslides/static /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
