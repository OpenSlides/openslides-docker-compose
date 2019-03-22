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
* ```postfix``` (Mail sending system)

...networks:

* ```front``` (just for nginx)
* ```back``` (for everything else in the backend)

...volumes:

* ```dbdata``` (the data of the ```postgres``` container)
* ```personaldata``` (static files and settings of OpenSlides)
* ```staticfiles``` (files to deliver the OpenSlides ```client```)
* ```redisdata``` (files of ```redis```)


## ```handle_instance.sh```

The ```handle_instance.sh``` script wraps the most important functions. Invoke
it with ```-h``` the get some help-text.

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

To build and start the instance, run:

    docker-compose build
    docker-compose up -d 

To shut down the instance you simply type

    docker-compose down

## Volumes and Persistent Data

The volumes (see above) will hold your persistent data.  To find out where they
have been linked in your filesystem, list them with:

    docker volume ls

Your output will look like this (or ```$PROJECT_NAME_certs``` if you specified
a project name):

    # docker volume ls
    DRIVER              VOLUME NAME
    local               5cbbf750b3d52a2e19615c96276c1144b27d637ec85ac46488f1f8fb86e259f3
    local               85dc5658e1b7c01f77590f8c0adcb4a23b02eeaef2f76fb83f95fef3efb61082
    local               88d855132874e6af0a5545e099626029a4dfb0501930454895d1846aba6da8fd
    local               a88d6a57b9bc7c43433273421261de32a981d15f997678e94b40ec36f3d14f59
    local               openslides1examplecom_dbdata
    local               openslides1examplecom_personaldata
    local               openslides1examplecom_redisdata
    local               openslides1examplecom_staticfiles

The last few volumes belong to the OpenSlides instance with the project name,
i.e. directory name, "openslides1.example.com".
You can read the mount point in the local filesystem:

    # docker volume inspect openslidesdocker_dbdata
    [
      {
        "CreatedAt": "2018-04-16T15:07:33+02:00",
        "Driver": "local",
        "Labels": {
            "com.docker.compose.project": "openslides1examplecom",
            "com.docker.compose.volume": "dbdata"
        },
        "Mountpoint": "/var/lib/docker/volumes/openslides1examplecom_dbdata/_data",
        "Name": "openslides1examplecom_dbdata",
        "Options": {},
        "Scope": "local"
      }
    ]

## Performance Optimizations

This setup tries to find good defaults for fairly large instances/events but
other configurations are possible.  See, for example, the "command" and
"sysctl" settings in the server configuraion in docker-compose.yml.

[openslides-performance](https://github.com/OpenSlides/openslides-performance)
is a stress testing tool for OpenSlides instances.  You may find that the
"server" service needs to be tweaked to handle very large numbers of
connections.
