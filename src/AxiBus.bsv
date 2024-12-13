import Vector :: *;
import FIFOF :: *;
import PrimUtils :: *;
import Arbiter :: *;

import ConnectableF :: *;
import BasicDataTypes :: *;

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




interface AxiMmArbiterSlave#(numeric type channelCnt, type tAxiData);
    interface Vector#(channelCnt, AxiSlavePipes#(tAxiData))     slaveIfcVec;
    interface AxiMasterPipes#(tAxiData)                         masterIfc;
endinterface


module mkAxiMmArbiterSlave#(Integer depth)(AxiMmArbiterSlave#(channelCnt, tAxiData)) provisos (
        Bits#(tAxiData, sztAxiData),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx)
    );

    Vector#(channelCnt, AxiSlavePipes#(tAxiData))     slaveIfcVecInst = newVector;

    Vector#(channelCnt, FIFOF#(AxiMmBeatAw))            slaveSideQueueVecAw     <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(AxiMmBeatW#(tAxiData)))  slaveSideQueueVecW      <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(AxiMmBeatB))             slaveSideQueueVecB      <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(AxiMmBeatAr))            slaveSideQueueVecAr     <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(AxiMmBeatR#(tAxiData)))  slaveSideQueueVecR      <- replicateM(mkFIFOF);

    FIFOF#(AxiMmBeatAw)            masterSideQueueAw   <-  mkFIFOF;
    FIFOF#(AxiMmBeatW#(tAxiData))  masterSideQueueW    <-  mkFIFOF;
    FIFOF#(AxiMmBeatB)             masterSideQueueB    <-  mkFIFOF;
    FIFOF#(AxiMmBeatAr)            masterSideQueueAr   <-  mkFIFOF;
    FIFOF#(AxiMmBeatR#(tAxiData))  masterSideQueueR    <-  mkFIFOF;

    Arbiter_IFC#(channelCnt) writeArbiter <- mkArbiter(False);
    Arbiter_IFC#(channelCnt) readArbiter  <- mkArbiter(False);

    Reg#(Bool) isWriteFirstBeatReg <- mkReg(True);

    Reg#(tChannelIdx) curWriteChannelIdxReg <- mkRegU;

    FIFOF#(tChannelIdx) writeKeepOrderQueue <- mkSizedFIFOF(depth);
    FIFOF#(tChannelIdx) readKeepOrderQueue <- mkSizedFIFOF(depth);

    rule sendWriteArbitReq if (isWriteFirstBeatReg);
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (slaveSideQueueVecAw[channelIdx].notEmpty && slaveSideQueueVecW[channelIdx].notEmpty) begin
                writeArbiter.clients[channelIdx].request;
            end
        end
    endrule

    rule recvWriteArbitResp if (isWriteFirstBeatReg);
        Maybe#(AxiMmBeatAw) awMaybe = tagged Invalid;
        AxiMmBeatW#(tAxiData) w;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (writeArbiter.clients[channelIdx].grant) begin
                awMaybe = tagged Valid slaveSideQueueVecAw[channelIdx].first;
                w       = slaveSideQueueVecW[channelIdx].first;
                slaveSideQueueVecAw[channelIdx].deq;
                slaveSideQueueVecW[channelIdx].deq;

                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (awMaybe matches tagged Valid .aw) begin
            masterSideQueueAw.enq(aw);
            masterSideQueueW.enq(w);
            isWriteFirstBeatReg <= w.wlast;
            curWriteChannelIdxReg <= curChannelIdx;
            writeKeepOrderQueue.enq(curChannelIdx);
        end
    endrule

    rule forwardMoreWriteBeat if (!isWriteFirstBeatReg);
        let w  = slaveSideQueueVecW[curWriteChannelIdxReg].first;
        slaveSideQueueVecW[curWriteChannelIdxReg].deq;
        masterSideQueueW.enq(w);
        isWriteFirstBeatReg <= w.wlast;
    endrule

    rule forwardWriteResp;
        let b = masterSideQueueB.first;
        masterSideQueueB.deq;

        let channelIdx = writeKeepOrderQueue.first;
        writeKeepOrderQueue.deq;
        slaveSideQueueVecB[channelIdx].enq(b);
    endrule

    rule sendReadArbitReq;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (slaveSideQueueVecAr[channelIdx].notEmpty) begin
                readArbiter.clients[channelIdx].request;
            end
        end
    endrule

    rule recvReadArbitResp;
        Maybe#(AxiMmBeatAr) arMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (readArbiter.clients[channelIdx].grant) begin
                arMaybe = tagged Valid slaveSideQueueVecAr[channelIdx].first;
                slaveSideQueueVecAr[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (arMaybe matches tagged Valid .ar) begin
            masterSideQueueAr.enq(ar);
            readKeepOrderQueue.enq(curChannelIdx);
        end
    endrule

    rule forwardReadResp;
        let r = masterSideQueueR.first;
        masterSideQueueR.deq;

        let channelIdx = readKeepOrderQueue.first;
        slaveSideQueueVecR[channelIdx].enq(r);

        if (r.rlast) begin
            readKeepOrderQueue.deq;
        end
    endrule


    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        slaveIfcVecInst[channelIdx] = (
            interface AxiSlavePipes 
                interface AxiSlaveWritePipes writePipeIfc;
                    interface  writeAddrPipeIn  = toPipeIn(slaveSideQueueVecAw[channelIdx]);
                    interface  writeDataPipeIn  = toPipeIn(slaveSideQueueVecW[channelIdx]);
                    interface  writeRespPipeOut = toPipeOut(slaveSideQueueVecB[channelIdx]);
                endinterface

                interface AxiSlaveReadPipes readPipeIfc;
                    interface  readAddrPipeIn  = toPipeIn(slaveSideQueueVecAr[channelIdx]);
                    interface  readRespPipeOut = toPipeOut(slaveSideQueueVecR[channelIdx]);
                endinterface
            endinterface);
    end

    interface slaveIfcVec = slaveIfcVecInst;
    interface AxiMasterPipes masterIfc;
        interface AxiMasterWritePipes writePipeIfc;
            interface  writeAddrPipeOut  = toPipeOut(masterSideQueueAw);
            interface  writeDataPipeOut  = toPipeOut(masterSideQueueW);
            interface  writeRespPipeIn   = toPipeIn(masterSideQueueB);
        endinterface

        interface AxiMasterReadPipes readPipeIfc;
            interface  readAddrPipeOut  = toPipeOut(masterSideQueueAr);
            interface  readRespPipeIn   = toPipeIn(masterSideQueueR);
        endinterface
    endinterface
endmodule

