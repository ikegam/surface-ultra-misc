# SPDX-License-Identifier: GPL-2.0
# Surface Laptop Ultra (N1X) OS-initiated CPU idle. The module list is in Kbuild.
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
