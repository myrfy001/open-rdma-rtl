include ../Makefile.base

TESTFILE ?= TestExtractAndPrependPipeOut.bsv
TOPMODULE ?= mkTestHeaderAndDataStreamConversion
DIR_BSV_GENERATED ?= $(BUILDDIR)

SIMSCRIPT_NAME = ./$(TOPMODULE).sh

MISCFLAGS += -D IS_DEBUG=True -D USE_MOCK_HOST=True

ZERO_BRAM_HEX_FILE ?= zero_bram.hex

gen_bram_hex:
	python3 ../scripts/gen_zero_bram_init_file.py $(BUILDDIR)/bram_zero_128x512.bin 128 512

compile: gen_bram_hex
	mkdir -p $(BUILDDIR)
	bsc -elab -sim -verbose $(BLUESIMFLAGS) $(DEBUGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(SCHEDFLAGS) $(TRANSFLAGS) -g $(TOPMODULE) $(TESTFILE)

link: compile
	bsc -sim $(BLUESIMFLAGS) $(DIRFLAGS) $(RECOMPILEFLAGS) $(SCHEDFLAGS) $(TRANSFLAGS) -e $(TOPMODULE) -o $(BUILDDIR)/$(SIMSCRIPT_NAME) $(BSV_C_EXT_FILES)

simulate: link
	cd $(BUILDDIR) && $(SIMSCRIPT_NAME)

clean:
	rm -rf $(BUILDDIR)

.PHONY: compile link simulate clean
.DEFAULT_GOAL := simulate
