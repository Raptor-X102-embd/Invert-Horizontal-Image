# ============================================================
# Tools
# ============================================================
VERILATOR ?= verilator
PYTHON    ?= python3
GTKWAVE   ?= gtkwave

# ============================================================
# Directories
# ============================================================
BUILD_DIR   := build
RTL_SRC_DIR := rtl/src
RTL_HDR_DIR := rtl/headers
TB_DIR      := tb
IMG_DIR     := images
PY_DIR      := python

# ============================================================
# Sources
# ============================================================
TB_SRC ?= $(TB_DIR)/tb_top.sv
TB_TOP ?= $(basename $(notdir $(TB_SRC)))

RTL_SRCS := $(wildcard $(RTL_SRC_DIR)/*.sv)
RTL_HDRS := $(wildcard $(RTL_HDR_DIR)/*.svh)

INCDIRS  := -I$(RTL_HDR_DIR)

SIM_BIN  := $(BUILD_DIR)/$(TB_TOP)
WAVE_VCD := $(BUILD_DIR)/wave.vcd

# ============================================================
# Runtime plusargs (можно переопределить на команде: make run IN=... OUT=...)
# ============================================================
IN  ?= $(IMG_DIR)/lemme_chex.raw
OUT ?= $(IMG_DIR)/lemme_chex_inv.raw

# ============================================================
# Image conversion
# ============================================================
JPG_IN  := $(IMG_DIR)/lemme_chex.jpg
RAW_IN  := $(IMG_DIR)/lemme_chex.raw
IMG2RAW ?= $(PY_DIR)/img2raw.py

# ============================================================
# Verilator flags
# ============================================================
VERILATOR_FLAGS  = -sv --timing --trace --trace-structs --binary -Wall
VERILATOR_FLAGS += -Wno-fatal
VERILATOR_FLAGS += -Wno-TIMESCALEMOD
VERILATOR_FLAGS += -Wno-IMPORTSTAR
VERILATOR_FLAGS += -Wno-DECLFILENAME
VERILATOR_FLAGS += -Wno-WIDTHEXPAND
VERILATOR_FLAGS += -Wno-WIDTHTRUNC
VERILATOR_FLAGS += -Wno-UNUSEDSIGNAL
VERILATOR_FLAGS += -Wno-UNUSEDPARAM
VERILATOR_FLAGS += -Wno-PINCONNECTEMPTY
VERILATOR_FLAGS += $(INCDIRS)

# ============================================================
# Phony
# ============================================================
.PHONY: all sim run wave prepare clean distclean help

all: sim

help:
	@echo "Targets:"
	@echo "  prepare    - JPEG -> RAW ($(RAW_IN))"
	@echo "  sim        - build only ($(SIM_BIN))"
	@echo "  run        - run simulation with +IN_FILE/+OUT_FILE"
	@echo "  wave       - open GTKWave ($(WAVE_VCD))"
	@echo "  clean      - remove build artifacts"
	@echo "  distclean  - clean + remove generated RAW files"
	@echo ""
	@echo "Run with custom paths:"
	@echo "  make run IN=images/foo.raw OUT=images/foo_inv.raw"
	@echo ""
	@echo "Override TB:"
	@echo "  make sim TB_SRC=tb/tb_other.sv"

# ============================================================
# Build
# ============================================================
sim: $(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(RTL_HDRS) $(TB_SRC)
	@mkdir -p $(BUILD_DIR)
	@echo ">>> Verilator build (top=$(TB_TOP))"
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module $(TB_TOP) \
		--Mdir $(BUILD_DIR) \
		-o $(TB_TOP) \
		$(RTL_SRCS) $(TB_SRC)

# ============================================================
# Run (assumes build already done)
# ============================================================
run: $(SIM_BIN)
	@echo "========================================="
	@echo " Running $(TB_TOP)"
	@echo "   IN  = $(IN)"
	@echo "   OUT = $(OUT)"
	@echo "========================================="
	@mkdir -p $(BUILD_DIR) $(dir $(OUT))
	./$(SIM_BIN) +IN_FILE=$(IN) +OUT_FILE=$(OUT)

# ============================================================
# Image preparation
# ============================================================
prepare: $(RAW_IN)

$(RAW_IN): $(JPG_IN) $(IMG2RAW)
	@echo ">>> Convert $(JPG_IN) -> $(RAW_IN)"
	$(PYTHON) $(IMG2RAW) $(JPG_IN) -o $(RAW_IN)

# ============================================================
# Waveform
# ============================================================
wave:
	@if [ ! -f $(WAVE_VCD) ]; then \
		echo "No $(WAVE_VCD) yet — run 'make run' first"; exit 1; \
	fi
	$(GTKWAVE) $(WAVE_VCD) &

# ============================================================
# Clean
# ============================================================
clean:
	rm -rf $(BUILD_DIR) obj_dir

distclean: clean
	rm -f $(RAW_IN) $(OUT)
