SHELL := bash
.DEFAULT_GOAL := all

INSTALL=install
PREFIX=/usr/local
BINDIR=$(PREFIX)/bin

dest_bindir := $(DESTDIR)$(BINDIR)

all:
	@echo "Available target: 'install'"

install:
	$(INSTALL) -d $(dest_bindir)
	$(INSTALL) -pm 0755 osinstancectl.sh $(dest_bindir)/osinstancectl
