import ConnectableF :: *;
import DataTypes :: *;

// Common ==================
typedef 8 AXI_AXLEN_WIDTH;
typedef Bit#(AXI_AXLEN_WIDTH) AxiAxlen;

typedef 1024 AXI_DATA_WIDTH_FOR_HIP;
typedef Bit#(AXI_DATA_WIDTH_FOR_HIP) AxiDataForHip;

typedef 256 AXI_DATA_WIDTH_FOR_LOGIC;
typedef Bit#(AXI_DATA_WIDTH_FOR_LOGIC) AxiDataForLogic;


// AW channel ==============
typedef 8 AXI_AWID_WIDTH;
typedef Bit#(AXI_AWID_WIDTH) AxiAwid;

typedef 64 AXI_AWADDR_WIDTH;
typedef Bit#(AXI_AWADDR_WIDTH) AxiAwaddr;

typedef AXI_AXLEN_WIDTH AXI_AWLEN_WIDTH;
typedef Bit#(AXI_AWLEN_WIDTH) AxiAwlen;

typedef 3 AXI_AWSIZE_WIDTH;
typedef Bit#(AXI_AWSIZE_WIDTH) AxiAwsize;

typedef 2 AXI_AWBURST_WIDTH;
typedef Bit#(AXI_AWBURST_WIDTH) AxiAwburst;

typedef 4 AXI_AWQOS_WIDTH;
typedef Bit#(AXI_AWQOS_WIDTH) AxiAwqos;

// W channel ==============
    // defined in common part above.

// B channel ==============
typedef 8 AXI_BID_WIDTH;
typedef Bit#(AXI_BID_WIDTH) AxiBid;

typedef 2 AXI_BRESP_WIDTH;
typedef Bit#(AXI_BRESP_WIDTH) AxiBresp;

// AR channel ==============
typedef 8 AXI_ARID_WIDTH;
typedef Bit#(AXI_ARID_WIDTH) AxiArid;

typedef 64 AXI_ARADDR_WIDTH;
typedef Bit#(AXI_ARADDR_WIDTH) AxiAraddr;

typedef AXI_AXLEN_WIDTH AXI_ARLEN_WIDTH;
typedef Bit#(AXI_ARLEN_WIDTH) AxiArlen;

typedef 3 AXI_ARSIZE_WIDTH;
typedef Bit#(AXI_ARSIZE_WIDTH) AxiArsize;

typedef 2 AXI_ARBURST_WIDTH;
typedef Bit#(AXI_ARBURST_WIDTH) AxiArburst;

typedef 4 AXI_ARQOS_WIDTH;
typedef Bit#(AXI_ARQOS_WIDTH) AxiArqos;

// R channel ==============
typedef 8 AXI_RID_WIDTH;
typedef Bit#(AXI_RID_WIDTH) AxiRid;

typedef 2 AXI_RRESP_WIDTH;
typedef Bit#(AXI_RRESP_WIDTH) AxiRresp;

typedef enum {
    AxiSize1B   = 0,
    AxiSize2B   = 1,
    AxiSize4B   = 2,
    AxiSize8B   = 3,
    AxiSize16B  = 4,
    AxiSize32B  = 5,
    AxiSize64B  = 6,
    AxiSize128B = 7
} AxiSize deriving(Bits, FShow, Eq);

typedef enum {
    AxiBurstFixed  = 0,
    AxiBurstIncr   = 1,
    AxiBurstWrap   = 2
} AxiBurst deriving(Bits, FShow, Eq);

typedef struct {
    AxiAwid awid;
    AxiAwaddr awaddr;
    AxiAwlen awlen;
    AxiAwsize awsize;
    AxiAwburst awburst;
    Bool awlock;  
    AxiAwqos awqos;
} AxiMmBeatAw deriving(Bits, FShow);

typedef struct {
    tAxiWdata wdata;
    Bit#(TDiv#(SizeOf#(tAxiWdata), BYTE_WIDTH)) wstrb;
    Bool wlast;
} AxiMmBeatW#(type tAxiWdata) deriving(Bits, FShow);

typedef struct {
    AxiBid bid;
    AxiBresp bresp;
} AxiMmBeatB deriving(Bits, FShow);

typedef struct {
    AxiArid arid;
    AxiAraddr araddr;
    AxiArlen arlen;
    AxiArsize arsize;
    AxiArburst arburst;
    Bool arlock;
    AxiArqos arqos;
} AxiMmBeatAr deriving(Bits, FShow);

typedef struct {
    AxiRid rid;
    tAxiRdata rdata;
    AxiRresp rresp;
    Bool rlast;
} AxiMmBeatR#(type tAxiRdata) deriving(Bits, FShow);



interface AxiMasterWritePipes#(type tAxiWdata);
    interface PipeOut#(AxiMmBeatAw)              writeAddrPipeOut;
    interface PipeOut#(AxiMmBeatW#(tAxiWdata))   writeDataPipeOut;
    interface PipeIn#(AxiMmBeatB)                writeRespPipeIn;
endinterface

interface AxiMasterReadPipes#(type tAxiRdata);
    interface PipeOut#(AxiMmBeatAr)              readAddrPipeOut;
    interface PipeIn#(AxiMmBeatR#(tAxiRdata))    readRespPipeIn;
endinterface

interface AxiMasterPipes#(type tAxiData);
    interface AxiMasterWritePipes#(tAxiData)  writePipeIfc;
    interface AxiMasterReadPipes#(tAxiData)   readPipeIfc;
endinterface


interface AxiSlaveWritePipes#(type tAxiWdata);
    interface PipeIn#(AxiMmBeatAw)              writeAddrPipeIn;
    interface PipeIn#(AxiMmBeatW#(tAxiWdata))   writeDataPipeIn;
    interface PipeOut#(AxiMmBeatB)              writeRespPipeOut;
endinterface

interface AxiSlaveReadPipes#(type tAxiRdata);
    interface PipeIn#(AxiMmBeatAr)              readAddrPipeIn;
    interface PipeOut#(AxiMmBeatR#(tAxiRdata))  readRespPipeOut;
endinterface

interface AxiSlavePipes#(type tAxiData);
    interface AxiSlaveWritePipes#(tAxiData)  writePipeIfc;
    interface AxiSlaveReadPipes#(tAxiData)   readPipeIfc;
endinterface