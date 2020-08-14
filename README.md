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


## Importing Data from Legacy Instances

There is no straight migration path for upgrades from legacy setups.  Instead,
please create a fresh instance and import the legacy instance's data into it.
A script to export data from legacy instances is provided in the legacy branch.

To import the exported legacy data, use `./contrib/legacy-import.sh`.
