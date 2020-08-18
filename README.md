# OpenSlides Docker Images

This repository manages services required for *dockerized*
[OpenSlides](https://openslides.org) 3 deployments that are not managed in the
[main repository](https://github.com/OpenSlides/OpenSlides/).

Currently, these services are:

  - openslides-repmgr
  - openslides-pgbouncer
  - openslides-postfix


## Usage

You can build the Docker images using the provided `build.sh` script.

You can no longer start OpenSlides based on these images or this repository
alone, however.  Instead, you need to use OpenSlides' [main
repository](https://github.com/OpenSlides/OpenSlides/) as a starting point.


## Management Resources

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

## Legacy Instances

### Exporting Configuration from the Database to .env

Legacy instances stored their configuration files in the database which is no
longer true for the current configuration concept.  Instead, instances are
configured through variables in .env.

Migration steps:

1. Make a backup of your instance directory
2. Update the management environment
    1. Clone the main OpenSlides repository to /srv/openslides/OpenSlides/
    2. Follow the included instructions for building new server and client images
    3. Update osinstancectl/osstackctl from this repository
3. Run `./contrib/export-db-settings.sh <instance directory>`
4. Update server and client to the new images
5. Remove the instance's deprecated prioserver service


### Importing Data from Compose-only Legacy Instances

The migration path for the initial type of Compose-only instances has become
incompatible with the current setup.  To migrate very old instances, you will
have to go through an intermediate version such as 168646d first, and then
follow the above instructions to migrate them to the most current setup.
