# =========================================================
# xsocket Makefile (Meson-independent optional build layer)
# =========================================================

PROJECT     := xsocket
VERSION     := 1.2

PREFIX      ?= /usr
LIBDIR      ?= $(PREFIX)/lib
INCLUDEDIR  ?= $(PREFIX)/include
BINDIR      ?= $(PREFIX)/bin
SYSTEMD_DIR ?= $(PREFIX)/lib/systemd/system
SYSUSERS_DIR?= $(PREFIX)/lib/sysusers.d

CC          ?= cc
AR          ?= ar
PKG_CONFIG  ?= pkg-config

CFLAGS      += -std=gnu11 -fPIC -Wall -Wextra -D_GNU_SOURCE
LDFLAGS     += -ldl

DEBUG       ?= 0
SYSTEMD     ?= auto
PYTHON      ?= python3

# ---------------------------------------------------------
# Sources
# ---------------------------------------------------------

COMMON_SRC := \
	cleanup.c \
	socket.c \
	protocol.c \
	switch.c

SERVER_SRC := server.c
LIB_SRC    := xsocket.c
HOOK_SRC   := hook.c

COMMON_OBJ := $(COMMON_SRC:.c=.o)
SERVER_OBJ := $(SERVER_SRC:.c=.o)
LIB_OBJ    := $(LIB_SRC:.c=.o)
HOOK_OBJ   := $(HOOK_SRC:.c=.o)

# ---------------------------------------------------------
# Build flags
# ---------------------------------------------------------

ifeq ($(DEBUG),1)
	CFLAGS += -O0 -g -D_DEBUG
else
	CFLAGS += -O2 -DNDEBUG
endif

# systemd detection
SYSTEMD_FOUND := $(shell $(PKG_CONFIG) --exists libsystemd && echo yes || echo no)

ifeq ($(SYSTEMD),auto)
	ifeq ($(SYSTEMD_FOUND),yes)
		CFLAGS += -DXSOCKET_SYSTEMD
		LDFLAGS += $(shell $(PKG_CONFIG) --libs libsystemd)
	endif
else ifeq ($(SYSTEMD),1)
	CFLAGS += -DXSOCKET_SYSTEMD
	LDFLAGS += $(shell $(PKG_CONFIG) --libs libsystemd)
endif

# ---------------------------------------------------------
# Targets
# ---------------------------------------------------------

.PHONY: all clean install uninstall distclean check dirs

all: dirs \
	libxsocket.so \
	libxbind.so \
	xsocket-server \
	libxsocket.a

dirs:
	@mkdir -p build

# ---------------------------------------------------------
# Objects
# ---------------------------------------------------------

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# ---------------------------------------------------------
# Static lib
# ---------------------------------------------------------

libxsocket.a: $(COMMON_OBJ)
	$(AR) rcs $@ $^

# ---------------------------------------------------------
# Shared core library
# ---------------------------------------------------------

libxsocket.so: $(COMMON_OBJ) $(LIB_OBJ)
	$(CC) -shared -o $@ $^ $(LDFLAGS)

# ---------------------------------------------------------
# LD_PRELOAD hook library
# ---------------------------------------------------------

libxbind.so: $(HOOK_OBJ) $(COMMON_OBJ)
	$(CC) -shared -o $@ $^ $(LDFLAGS)

# ---------------------------------------------------------
# Server daemon
# ---------------------------------------------------------

xsocket-server: $(SERVER_OBJ) $(COMMON_OBJ)
	$(CC) -o $@ $^ $(LDFLAGS)

# ---------------------------------------------------------
# Python binding install (optional)
# ---------------------------------------------------------

install-python:
	@echo "Installing Python module..."
	$(PYTHON) -m pip install .

# ---------------------------------------------------------
# Install
# ---------------------------------------------------------

install: all
	install -Dm755 xsocket-server $(DESTDIR)$(BINDIR)/xsocket-server
	install -Dm755 libxsocket.so $(DESTDIR)$(LIBDIR)/libxsocket.so
	install -Dm755 libxbind.so $(DESTDIR)$(LIBDIR)/libxbind.so
	install -Dm644 xsocket.h $(DESTDIR)$(INCLUDEDIR)/xsocket.h

	# systemd integration (if enabled)
ifeq ($(SYSTEMD),1)
	install -Dm644 xsocket.service $(DESTDIR)$(SYSTEMD_DIR)/xsocket.service
	install -Dm644 xsocket.sysusers $(DESTDIR)$(SYSUSERS_DIR)/xsocket.conf
endif

# ---------------------------------------------------------
# Uninstall
# ---------------------------------------------------------

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/xsocket-server
	rm -f $(DESTDIR)$(LIBDIR)/libxsocket.so
	rm -f $(DESTDIR)$(LIBDIR)/libxbind.so
	rm -f $(DESTDIR)$(INCLUDEDIR)/xsocket.h
	rm -f $(DESTDIR)$(SYSTEMD_DIR)/xsocket.service
	rm -f $(DESTDIR)$(SYSUSERS_DIR)/xsocket.conf

# ---------------------------------------------------------
# Cleanup
# ---------------------------------------------------------

clean:
	rm -f *.o *.so *.a xsocket-server

distclean: clean
	rm -rf build

# ---------------------------------------------------------
# Basic sanity checks
# ---------------------------------------------------------

check: all
	@echo "Checking dynamic dependencies..."
	ldd xsocket-server || true
	ldd libxsocket.so || true
	ldd libxbind.so || true

# ---------------------------------------------------------
# Debug run helper
# ---------------------------------------------------------

run-server: xsocket-server
	./xsocket-server /run/xsocket/default

# ---------------------------------------------------------
# LD_PRELOAD test
# ---------------------------------------------------------

test-hook: libxbind.so
	LD_PRELOAD=./libxbind.so XBIND="3000 8080" nc -l -p 3000

# ---------------------------------------------------------
# Container-friendly build
# ---------------------------------------------------------

container-build:
	podman build --target=build -f Containerfile .

container-package:
	podman build --target=package -f Containerfile .

# ---------------------------------------------------------
# Print config
# ---------------------------------------------------------

print:
	@echo "PREFIX=$(PREFIX)"
	@echo "SYSTEMD=$(SYSTEMD)"
	@echo "DEBUG=$(DEBUG)"
