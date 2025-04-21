PRIV_DIR := $(MIX_APP_PATH)/priv
NIF_PATH := $(PRIV_DIR)/libexsrt.so
C_SRC := $(shell pwd)/c_src/ex_libsrt

CPPFLAGS := -shared -fPIC -fvisibility=hidden -std=c++17 -Wall -Wextra -pthread
CPPFLAGS += -I$(ERTS_INCLUDE_DIR) -I$(FINE_INCLUDE_DIR)

# Use pkg-config to get the flags necessary for compiling and linking
PKG_CONFIG := pkg-config
LIBS := srt openssl
CPPFLAGS += $(shell $(PKG_CONFIG) --cflags $(LIBS))
LDFLAGS := $(shell $(PKG_CONFIG) --libs $(LIBS))

ifdef DEBUG
	CPPFLAGS += -g
else
	CPPFLAGS += -O3
endif

ifndef TARGET_ABI
  TARGET_ABI := $(shell uname -s | tr '[:upper:]' '[:lower:]')
endif

ifeq ($(TARGET_ABI),darwin)
	CPPFLAGS += -undefined dynamic_lookup -flat_namespace
endif

SOURCES := $(wildcard $(C_SRC)/*.cpp $(C_SRC)/client/*.cpp $(C_SRC)/server/*.cpp $(C_SRC)/common/*.cpp)

all: $(NIF_PATH)
	@ echo > /dev/null # Dummy command to avoid the default output "Nothing to be done"

$(NIF_PATH): $(SOURCES)
	@ mkdir -p $(PRIV_DIR)
	$(CXX) $(CPPFLAGS) $(SOURCES) $(LDFLAGS) -o $(NIF_PATH)
