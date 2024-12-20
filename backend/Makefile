include ../Makefile.base

TCLDIR ?= xdc
CLK ?= rdma_clock
OOC ?= 1

BACKENDDIR ?= $(shell readlink -f ./)
QUARTUS_BACKEND_DIR ?= $(BACKENDDIR)/quartus

QUARTUS_WORKDIR ?= $(BACKENDDIR)/quartus_workdir_$(shell date +"%Y-%m-%d-%H-%M-%S-%N")
RTL_DIRS ?= $(BACKENDDIR)/verilog/*.v\
			$(BACKENDDIR)/../src/verilog/*.v \
			$(BACKENDDIR)/../src/verilog/**/*.v \
			$(BACKENDDIR)/quartus/rtl/*.v

QUARTUS_SDC_DIRS ?= $(QUARTUS_BACKEND_DIR)/sdc/*.sdc

BRAM_INIT_FILE_DIRS ?= $(BACKENDDIR)/$(BUILDDIR)/*.bin
			
LOGFILE ?= run.log
RUNTOPHASE ?= all # synth place route all
DEVICE ?= AGIB027R29B1E2V
FAMILY ?= Agilex 7



# TARGETFILE ?= ../test/TestFullyPipelinedUpdateBram.bsv
# BSV_TOP_MODULE ?= mkTestFullyPipelinedBackendTimingTest

# TARGETFILE ?= ../test/TestFullyPipelinedUpdateBram.bsv
# BSV_TOP_MODULE ?= mkTestFullyPipelinedUpdateBramFunctionalTest

# TARGETFILE ?= ../test/TestSdpBramWrapper.bsv
# BSV_TOP_MODULE ?= mkTestSdpBramWrapperConflictReadWriteTest

# TARGETFILE ?= ../test/TestSdpBramWrapper.bsv
# BSV_TOP_MODULE ?= mkTestAcxBram72kSdpConflictRW

# TARGETFILE ?= ../test/TestButterflyMerge.bsv
# BSV_TOP_MODULE ?= mkTestFourChannelButterflyMergeTimingTest

# TARGETFILE ?= ../test/TestNapWrapper.bsv
# BSV_TOP_MODULE ?= mkTestEthernetNapLoopBack

# TARGETFILE ?= ../test/TestEthernetFrameIO.bsv
# BSV_TOP_MODULE ?= mkTestEthernetFrameIoTiming

# TARGETFILE ?= ../test/TestAddressChunker.bsv
# BSV_TOP_MODULE ?= mkTestAddressChunkerTiming

# TARGETFILE ?= ../test/TestPayloadGenAndCon.bsv
# BSV_TOP_MODULE ?= mkTestPayloadGenAndConTiming

# TARGETFILE ?= ../test/TestPsnContinousChecker.bsv
# BSV_TOP_MODULE ?= mkTestBitmapWindowStorageTiming

# TARGETFILE ?= ../test/TestAutoAckGenerator.bsv
# BSV_TOP_MODULE ?= mkTestAutoAckGeneratorTiming

# TARGETFILE ?= ../src/RTilePcieAdaptor.bsv
# BSV_TOP_MODULE ?= mkRTilePcieAdaptor

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestPcieRxStreamSegmentForkTimingTest

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestPcieHwCpltBufferAllocatorTimingTest

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestPcieCompletionBufferTimingTest

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestRtilePcieAdaptorTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestFtileMacRxPingPongSingleChannelProcessorTimingTest

# TARGETFILE ?= ../src/FTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkFtileMacRxPingPongChannelMetaJoin

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestFtileMacRxPingPongChannelMetaJoinTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestFtileMacAdaptorTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestRotateTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestMimoTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestFtileMacTxPingPongForkTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# BSV_TOP_MODULE ?= mkTestFtileMacCocotbLoopBackTest

# TARGETFILE ?= ../test/TestDtldStream.bsv
# BSV_TOP_MODULE ?= mkTestDtldStreamConcatorTimingTest

# TARGETFILE ?= ../test/TestDtldStream.bsv
# BSV_TOP_MODULE ?= mkTestDtldStreamSpliterTimingTest


TARGETFILE ?= ../src/Top.bsv
BSV_TOP_MODULE ?= mkBsvTop
TOP = bluerdma_top



MAX_NET_PATH_NUM ?= 10000
TOP ?= $(BSV_TOP_MODULE)

export QUARTUS_WORKDIR
export QUARTUS_BACKEND_DIR
export BRAM_INIT_FILE_DIRS
export PROJ_NAME = $(BSV_TOP_MODULE)
export REV_NAME = rev1
export TOP
export RTL_DIRS
export QUARTUS_SDC_DIRS
export DEVICE
export FAMILY
export DIR_BSV_GENERATED = $(BACKENDDIR)/verilog



gen_bram_hex:
	mkdir -p $(BUILDDIR)	
	python3 ../scripts/gen_bram_init_file.py $(BUILDDIR)

compile: gen_bram_hex
	mkdir -p $(BUILDDIR)
	bsc -elab -verilog -verbose $(BLUESIMFLAGS) $(DEBUGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(SCHEDFLAGS) $(TRANSFLAGS) -g $(BSV_TOP_MODULE) $(TARGETFILE)

verilog: compile 
	mkdir -p $(DIR_BSV_GENERATED)
	bsc $(VERILOGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(TRANSFLAGS) -g $(BSV_TOP_MODULE) $(TARGETFILE)
	bluetcl listVlogFiles.tcl -bdir $(BUILDDIR) -vdir $(BUILDDIR) $(BSV_TOP_MODULE) $(BSV_TOP_MODULE) | grep -i '\.v' | xargs -I {} cp {} $(DIR_BSV_GENERATED)

vivado: verilog
	vivado -mode tcl -nolog -nojournal -source ./build_top.tcl 2>&1 | tee $(LOGFILE)

vivado_ooc:
	vivado -mode tcl -nolog -nojournal -source ./build_top.tcl 2>&1 | tee $(LOGFILE)

quartus:
	cd quartus && \
	quartus_sh -t non-project-build.tcl

clean:
	rm -rf $(BUILDDIR) $(WORK_DIR) $(DIR_BSV_GENERATED) $(DIR_BSV_GENERATED_STUB) .Xil *.jou *.log

.PHONY: verilog vivado clean quartus
.DEFAULT_GOAL := verilog
