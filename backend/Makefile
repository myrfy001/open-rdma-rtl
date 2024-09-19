include ../Makefile.base

TCLDIR ?= xdc
CLK ?= rdma_clock
OOC ?= 1
VLOGDIR ?= ../src/third_party/verilog
OUTPUTDIR ?= output
LOGFILE ?= run.log
RUNTOPHASE ?= all # synth place route all
PARTNAME = xcvu13p-fhgb2104-2-i
# PARTNAME = xcvu23p-vsva1365-2L-e


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

TARGETFILE ?= ../test/TestRTilePcieAdaptor.bsv
TOPMODULE ?= mkTestExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStreamTimingTest


# TARGETFILE ?= ../test/TestTop.bsv
# TOPMODULE ?= mkTestTopTiming

BACKENDDIR ?= .
MAX_NET_PATH_NUM ?= 10000
VERILOG_TOPMODULE ?= top


export TOP = $(TOPMODULE)
export DIR_RTL = $(VLOGDIR)
export DIR_XDC = $(TCLDIR)
export DIR_OOC_SCRIPTS = $(BACKENDDIR)/ooc_tcl_and_xdc
export DIR_IPS = $(BACKENDDIR)/ips
export DIR_IP_GENERATED = $(BUILDDIR)/ips
export DIR_BSV_GENERATED = $(BACKENDDIR)/verilog
export VERILOG_TOPMODULE
export TARGET_CLOCKS = $(CLK)
export DIR_OUTPUT = $(OUTPUTDIR)
export OOCSYNTH = $(OOC)
export RUNTO = $(RUNTOPHASE)
export PART = $(PARTNAME)
export MAX_NET_PATH_NUM

export DIR_BSV_GENERATED_STUB = $(BACKENDDIR)/verilog/stub


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

clean:
	rm -rf $(BUILDDIR) $(OUTPUTDIR) $(DIR_BSV_GENERATED) $(DIR_BSV_GENERATED_STUB) .Xil *.jou *.log

.PHONY: verilog vivado clean
.DEFAULT_GOAL := verilog
