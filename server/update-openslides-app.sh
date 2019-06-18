#!/bin/bash

# This script copies the OpenSlides installation of the image to the shared
# volume, so Nginx can pick them up.
#
# This is a separate script so it can be run as root (via sudo by openslides)
# while keeping the Docker USER set to openslides.

echo "Updating /app from pre-built files..."
rsync -a /build/app/ /app/
chown -R openslides:openslides /app/

# Make image git commit info available through web server
GIT_COMMIT_INFO="/build/image-version.txt"
if [[ -f "$GIT_COMMIT_INFO" ]]; then
  cp --preserve=timestamps "$GIT_COMMIT_INFO" /app/openslides/static/
fi
