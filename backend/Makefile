include ../Makefile.base

TCLDIR ?= xdc
CLK ?= rdma_clock
OOC ?= 1

BACKENDDIR ?= $(shell readlink -f ./)
QUARTUS_BACKENDD_IR ?= $(BACKENDDIR)/quartus

QUARTUS_WORKDIR ?= $(BACKENDDIR)/quartus_workdir_$(shell date +"%Y-%m-%d-%H-%M-%S-%N")
RTL_DIRS ?= $(BACKENDDIR)/verilog/*.v\
			$(BACKENDDIR)/../src/verilog/*.v \
			$(BACKENDDIR)/../src/verilog/**/*.v

QUARTUS_SDC_DIRS ?= $(QUARTUS_BACKENDD_IR)/sdc/*.sdc
			
LOGFILE ?= run.log
RUNTOPHASE ?= all # synth place route all
DEVICE ?= AGIB027R29B1E2V
FAMILY ?= Agilex 7



# TARGETFILE ?= ../test/TestFullyPipelinedUpdateBram.bsv
# TOPMODULE ?= mkTestFullyPipelinedBackendTimingTest

# TARGETFILE ?= ../test/TestFullyPipelinedUpdateBram.bsv
# TOPMODULE ?= mkTestFullyPipelinedUpdateBramFunctionalTest

# TARGETFILE ?= ../test/TestSdpBramWrapper.bsv
# TOPMODULE ?= mkTestSdpBramWrapperConflictReadWriteTest

# TARGETFILE ?= ../test/TestSdpBramWrapper.bsv
# TOPMODULE ?= mkTestAcxBram72kSdpConflictRW

# TARGETFILE ?= ../test/TestButterflyMerge.bsv
# TOPMODULE ?= mkTestFourChannelButterflyMergeTimingTest

# TARGETFILE ?= ../test/TestNapWrapper.bsv
# TOPMODULE ?= mkTestEthernetNapLoopBack

# TARGETFILE ?= ../test/TestEthernetFrameIO.bsv
# TOPMODULE ?= mkTestEthernetFrameIoTiming

# TARGETFILE ?= ../test/TestAddressChunker.bsv
# TOPMODULE ?= mkTestAddressChunkerTiming

# TARGETFILE ?= ../test/TestPayloadGenAndCon.bsv
# TOPMODULE ?= mkTestPayloadGenAndConTiming

# TARGETFILE ?= ../test/TestPsnContinousChecker.bsv
# TOPMODULE ?= mkTestBitmapWindowStorageTiming

# TARGETFILE ?= ../src/AutoAckGenerator.bsv
# TOPMODULE ?= mkAutoAckGenerator

# TARGETFILE ?= ../src/RTilePcieAdaptor.bsv
# TOPMODULE ?= mkRTilePcieAdaptor

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# TOPMODULE ?= mkTestPcieRxStreamSegmentForkTimingTest

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# TOPMODULE ?= mkTestPcieHwCpltBufferAllocatorTimingTest

# TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
# TOPMODULE ?= mkTestPcieCompletionBufferTimingTest

TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
TOPMODULE ?= mkTestRtilePcieAdaptorTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestFtileMacRxPingPongSingleChannelProcessorTimingTest

# TARGETFILE ?= ../src/FTileMacAdaptor.bsv
# TOPMODULE ?= mkFtileMacRxPingPongChannelMetaJoin

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestFtileMacRxPingPongChannelMetaJoinTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestFtileMacAdaptorTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestRotateTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestMimoTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestFtileMacTxPingPongForkTimingTest

# TARGETFILE ?= ../test/TestFTileMacAdaptor.bsv
# TOPMODULE ?= mkTestFtileMacCocotbLoopBackTest

# TARGETFILE ?= ../test/TestDtldStream.bsv
# TOPMODULE ?= mkTestDtldStreamConcatorTimingTest

# TARGETFILE ?= ../test/TestDtldStream.bsv
# TOPMODULE ?= mkTestDtldStreamSpliterTimingTest



# TARGETFILE ?= ../test/TestTop.bsv
# TOPMODULE ?= mkTestTopTiming


MAX_NET_PATH_NUM ?= 10000
VERILOG_TOPMODULE ?= top


export QUARTUS_WORKDIR
export QUARTUS_BACKENDD_IR
export PROJ_NAME = $(TOPMODULE)
export REV_NAME = rev1
export TOP = $(TOPMODULE)
export RTL_DIRS
export QUARTUS_SDC_DIRS
export DEVICE
export FAMILY
export DIR_BSV_GENERATED = $(BACKENDDIR)/verilog

# export TOP = $(TOPMODULE)
# export DIR_RTL = $(VLOGDIR)
# export DIR_XDC = $(TCLDIR)
# export DIR_OOC_SCRIPTS = $(BACKENDDIR)/ooc_tcl_and_xdc
# export DIR_IPS = $(BACKENDDIR)/ips
# export DIR_IP_GENERATED = $(BUILDDIR)/ips

# export VERILOG_TOPMODULE
# export TARGET_CLOCKS = $(CLK)
# export DIR_OUTPUT = $(OUTPUTDIR)
# export OOCSYNTH = $(OOC)
# export RUNTO = $(RUNTOPHASE)
# export PART = $(PARTNAME)
# export MAX_NET_PATH_NUM



compile:
	mkdir -p $(BUILDDIR)
	bsc -elab -verilog -verbose $(BLUESIMFLAGS) $(DEBUGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(SCHEDFLAGS) $(TRANSFLAGS) -g $(TOPMODULE) $(TARGETFILE)

verilog: compile 
	mkdir -p $(DIR_BSV_GENERATED)
	bsc $(VERILOGFLAGS) $(DIRFLAGS) $(MISCFLAGS) $(RECOMPILEFLAGS) $(RUNTIMEFLAGS) $(TRANSFLAGS) -g $(TOPMODULE) $(TARGETFILE)
	bluetcl listVlogFiles.tcl -bdir $(BUILDDIR) -vdir $(BUILDDIR) $(TOPMODULE) $(TOPMODULE) | grep -i '\.v' | xargs -I {} cp {} $(DIR_BSV_GENERATED)

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
