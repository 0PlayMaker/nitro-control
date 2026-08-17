# Lives at the tree root, not in src/, because DKMS runs `make` from the root
# of the source tree it copies into /var/lib/dkms/<name>/<ver>/build.

obj-m     := src/nitro_kbd_timeout.o

KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD       := $(shell pwd)

all: default

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

install:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules_install

clean:
	rm -rf src/*.o src/*~ src/.*.cmd src/*.ko src/*.mod src/*.mod.c \
		.tmp_versions modules.order Module.symvers

.PHONY: all default install clean
