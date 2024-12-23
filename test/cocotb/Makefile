SHELL := /bin/bash

ROOT_DIR = $(abspath ../../)
BACKEND_DIR = $(ROOT_DIR)/backend
SRC_DIR = $(ROOT_DIR)/src
TB_DIR = $(abspath ./)
include $(ROOT_DIR)/Makefile.base
VBUILD_DIR = $(BACKEND_DIR)/build 
GENERATED_VSRC_DIR = $(BACKEND_DIR)/verilog

# TOP_BSV_SRC_FILE ?= ../src/RTilePcieAdaptor.bsv
# TOP_MODULE ?= mkRTilePcieWithRawIfc
# TB_FILE = tb_simple_root_complex.py

# TOP_BSV_SRC_FILE ?= ../test/TestRTilePcieAdaptor.bsv
# TOP_MODULE ?= mkTestRTilePcieByCocotbTest
# TB_FILE = tb_simple_root_complex.py

# TOP_BSV_SRC_FILE ?= ../test/TestFTileMacAdaptor.bsv
# TOP_MODULE ?= mkTestFtileMacCocotbLoopBackTest
# TB_FILE = tb_ftile_mac_loopback.py

# TOP_BSV_SRC_FILE ?= ../test/TestPayloadGenAndCon.bsv
# TOP_MODULE ?= mkTestCocotbPayloadGenAndCon
# TB_FILE = tb_payload_con_and_gen.py

# TOP_BSV_SRC_FILE ?= ../test/TestPacketGenAndParse.bsv
# TOP_MODULE ?= mkTestCocotbPacketGenAndParse
# TB_FILE = tb_packet_gen_and_parse.py

# TOP_BSV_SRC_FILE ?= ../test/TestPsnContinousChecker.bsv
# TOP_MODULE ?= mkTestCocotbPsnPerMergeAndStorage
# TB_FILE = tb_psn_per_merge_and_storage.py

TOP_BSV_SRC_FILE ?= ../src/Top.bsv
TOP_MODULE ?= mkBsvTopWithoutHardIpInstance
TB_FILE = tb_top_without_hard_ip.py




TOP_FILE = $(TOP_MODULE).v
VLOG_FILE = $(TB_DIR)/$(TOP_FILE)


DATE = $(shell date "+%Y%m%d")
LOG_FILE = $(TB_DIR)/log/$(DATE)_$(TOP_MODULE).log

gen_bram_hex:
	cd $(BACKEND_DIR) && python3 ../scripts/gen_bram_init_file.py $(GENERATED_VSRC_DIR)


verilog: gen_bram_hex
	cd $(BACKEND_DIR) && make TARGETFILE=${TOP_BSV_SRC_FILE} BSV_TOP_MODULE=${TOP_MODULE} verilog

prepare:
	sed -i '1i `timescale 1ns/1ps' $(GENERATED_VSRC_DIR)/$(TOP_FILE)

run:
	cd $(TB_DIR)
	mkdir -p log

	set -o pipefail; \
	COCOTB_VERILOG_DIR=$(SRC_DIR)/verilog:$(GENERATED_VSRC_DIR) COCOTB_DUT=$(TOP_MODULE) python3 $(TB_FILE) 2>&1 | tee $(LOG_FILE)

cocotb:clean verilog prepare run

clean:
	cd $(BACKEND_DIR) && make clean
	cd $(TB_DIR) && rm -rf $(VLOG_FILE) __pycache__ .pytest_cache sim_build *.log 
	