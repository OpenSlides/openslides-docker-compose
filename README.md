# Docker-Compose-based OpenSlides Suite

The ```docker-compose.yml``` describes a full system setup with every component
detached from the other.

The suite consists of the following...

...services:

* ```server``` (Server of OpenSlides, the base image, database migration and
  creation of the settings is created here)
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
```/srv/openslides/openslides1.example.com/```.  The directory name determines
your project name (also $PROJECT_NAME below).  By choosing descriptive names,
e.g., the URL of the instance, it should be relatively easy to find containers
and volumes belonging to a particular instance.

Next, create a docker-compose.yml from the template:

    cp docker-compose.yml.example docker-compose.yml

To specify a special git repository of OpenSlides, a certain Branch and/or
a certain commit, you should change the following entries at the ```server``
service:

    args:
      # Change according to your details
      REPOSITORY_URL: https://github.com/OpenSlides/OpenSlides.git
      GIT_CHECKOUT: f9c4f01f06bba0ab911735d383ac85b693203161

By default, the admin user's login password is "admin".  You can and should
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

## Performance Optimizations

This setup tries to find good defaults for fairly large instances/events but
other configurations are possible.  See, for example, the ```command``` and
```sysctl``` settings in the server configuraion in docker-compose.yml as well
as the ```worker_connections``` setting in client/nginx.conf.

[openslides-performance](https://github.com/OpenSlides/openslides-performance)
is a stress testing tool for OpenSlides instances.  You may find that the
"server" service needs to be tweaked to handle very large numbers of
connections.

## Additional Management Scripts

```contrib``` contains tools that should come in handy if you are running
multiple OpenSlides instances:

  - osinstancectl.sh: instance management tool
  - rosinstancectl.sh: wrapper around clustershell to run osinstancectl on
    multiple hosts
  - openslides-docker-pg-dump.sh: creates SQL dumps for all instances
