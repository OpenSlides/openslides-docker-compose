# Docker-based OpenSlides Suite

This repository provides the basis for *dockerized*
[OpenSlides](https://openslides.org) 3 deployments.

It is suitable for both Docker Compose and Swarm setups.  All required images
can be built using docker-compose and the server build script.  The included
`docker-compose.yml.m4` and `docker-stack.yml.m4` files need little tweaking
before starting an instance.

## Usage Example: Docker Compose

Each copy of this repository represents one OpenSlides instance; so, to begin,
clone (or copy) this repository to, e.g.,
`/srv/openslides/docker-instances/openslides1.example.com/`.

Next, create `docker-compose.yml` from the template:

    m4 docker-compose.yml.m4 > docker-compose.yml

Build the OpenSlides `server` and `client` images:

    ./build.sh server client

By default, the admin user's login password is `admin`.  You can and should
change it before starting the instance:

    editor ./secrets/adminsecret.env

To build the remaining services and start the instance, run:

    docker-compose build
    docker-compose up --detach


## Docker Swarm Mode

OpenSlides may also be deployed in Swarm mode.  Distributing instances over
multiple nodes may increase performance and offer failure resistance.

An example configuration file, `docker-stack.yml.m4`, is provided.  Unlike
the Docker Compose setup, this configuration will most likely need to be
customized, especially its placement constraints and database-related
preferences.

Before deploying an instance on Swarm, please see [Database
Configuration](#database-configuration) and [Backups](#backups), and review
your `docker-stack.yml`.


## Configuration

### Database Configuration

It is fairly easy to get an OpenSlides instance up an running; however, for
production setups it is strongly advised to review the database configuration.

By default, the primary database cluster will archive all WAL files in its
volume.  Regularly pruning old data is left up to the host system, i.e., you.
Alternatively, you may disable WAL archiving by setting
`PGNODE_WAL_ARCHIVING=off` in `.env` before starting the instance.

The provided `docker-stack.yml.m4` file includes additional database
services which can act as hot standby clusters with automatic failover
functionality.  To take advantage of this setup, the database services need to
be configured with proper placement constraints.  Before relying on this setup,
please familiarize yourself with [repmgr](https://repmgr.org/).

### Updates to OpenSlides' Configuration

Configuration files are kept in the database `instancecfg`.  Any configuration
changes that need to be available to all OpenSlides server containers must be
added to the database.  This affects, at the very least, OpenSlides'
`settings.py`.

To make changes to, e.g., `settings.py`, enter an OpenSlides server container
with `docker exec` and make the desired changes.  Use the `openslides-config`
command to push the updated file to the database, e.g., `openslides-config add
~/personal_data/var/settings.py` .  At this point, you may exit the container
and redeploy all server containers.


## Backups

All important data is stored in the database.  Additionally, the project
directory should be included in backups to ensure a smooth recovery.

The primary database usually runs in the `pgnode1` service (but see [Database
Configuration](#database-configuration) above).

In some cases, it may be sufficient to generate SQL dumps with `pg_dump`
through `docker exec` to create backups.  However, for proper incremental
backups, the host system can backup the cluster's data directory and WAL
archives.

The cluster's data directory is available as a volume on the host system.
Additionally, the database archives its WAL files in the same volume by
default.  This way, the host system can include the database volume in its
regular filesystem-based backup routine and create efficient database backups
suitable for point-in-time recovery.

The `openslides-pg-mgr.sh` script is provided to enable Postgres' backup mode
in all OpenSlides database containers.

In Swarm mode, the primary database cluster may get placed on a number of
nodes.  It is, therefore, crucial to restrict the placement of database
services to nodes on which appropriate backups have been configured.


## Multi-Instance Deployments

### Contrib Scripts

The `contrib` directory contains scripts and other resources to help manage
multi-instance setups.  `osinstancectl`/`osstackctl` handles most regular
management tasks.  Additional scripts are included to, inter alia, manage
backup mode on database clusters.

### HAProxy & Let's Encrypt

An HAProxy configuration file (`haproxy.cfg.example`) illustrates a possible
setup for hosting multiple instances.  It assumes a setup with Let's Encrypt
provided by [acmetool](https://hlandau.github.io/acmetool/).

With this setup, `osinstancectl`/`osstackctl` can add instances, configure
HAProxy, and generate TLS certificates.


## Importing Data from Legacy Instances

There is no straight migration path for upgrades from legacy setups.  Instead,
please create a fresh instance and import the legacy instance's data into it.
A script to export data from legacy instances is provided in the legacy branch.

To import the exported legacy data, use `./contrib/legacy-import.sh`.


## Requirements

Building the client image requires a significant amount of RAM, probably at
least 8GB.
