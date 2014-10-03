# Generate a bunch of faux JPEGs

# 2^2 .. 2^10 (size in KB)
RANDSIZES=$(shell perl -e 'print join(" ", map {2 ** $$_} (2 .. 13))')
RANDFILES=$(foreach R,$(RANDSIZES),random$(R)k.jpg)

.PHONY: all clean

all: $(RANDFILES)

random%k.jpg:
	dd if=/dev/urandom of="$@" bs=1k count=$*

clean:
	$(RM) $(RANDFILES)
