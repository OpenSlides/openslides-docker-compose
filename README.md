# Docker Compose-based OpenSlides Suite

## NOTICE

*Please note that this is the legacy branch of the OpenSlides Docker deployment
repository.  It contains the original Docker Compose-only setup.  If you would
like to update to the new setup, please refer to the migration section below.*

### Migrating Legacy Instances

This branch contains the legacy setup of OpenSlides.  The new deployment setup
differs significantly from the setup created by the present configuration.

For this reason, there is, unfortunately, no straight upgrade path.  Instead,
it is recommended that you create a fresh instance using the new setup method
and migrate your data over to it.

A script, `./contrib/openslides-legacy-export.sh`, is provided to export data
from legacy instances.


## Introduction

The ```docker-compose.yml``` describes a full system setup with every component
detached from the other.

The suite consists of the following...

...services:

* ```prioserver``` (Server of OpenSlides, the base image, database migration and
  creation of the settings is created here)
* ```server``` (Server of OpenSlides, Service tasked with handling most users)
* ```client``` (Client of OpenSlides)
* ```postgres``` (Database)
* ```redis``` (Cache Database)
* ```rediscache``` (Cache Database)
* ```postfix``` (Mail sending system)

...networks:

* ```front``` (just for nginx)
* ```back``` (for everything else in the backend)

...volumes:

* ```dbdata``` (the data of the ```postgres``` container)
* ```personaldata``` (static files and settings of OpenSlides)
* ```staticfiles``` (files to deliver the OpenSlides ```client```)
* ```redisdata``` (files of ```redis```)


## How to Use

Each copy of this directory represents one OpenSlides instance, so to begin,
clone (or copy) this repository to, e.g.,
```/srv/openslides/openslides1.example.com/```. 

Next, create a docker-compose.yml from the template:

    cp docker-compose.yml.example docker-compose.yml

Build the OpenSlides ```server``` image:

    ./server/build.sh

By default, the admin user's login password is `admin`.  You can and should
change it before you start the instance.  To do so, make a copy of the example
configuration file and add a secure password:

    cp -p ./secrets/adminsecret.env.example ./secrets/adminsecret.env

To build and start the instance, run:

    docker-compose build
    docker-compose up -d 

To shut down the instance you simply type

    docker-compose down

## Persistent Data

The database cluster is stored in a volume.  It's path can be identified with:

    docker inspect --format '{{range .Mounts}}{{.Source}}{{end}}' \
      "$(docker-compose ps -q postgres)"

## Additional Management Scripts

```contrib``` contains tools that should come in handy if you are running
multiple OpenSlides instances:

  - `osinstancectl.sh`: instance management tool
  - `rosinstancectl.sh`: wrapper around clustershell to run `osinstancectl` on
    multiple hosts
  - `openslides-docker-pg-dump.sh`: creates SQL dumps for all instances
  - `openslides-logwatch.sh`: Traceback monitoring
