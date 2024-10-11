import Vector :: *;
import FIFOF :: *;
import PrimUtils :: *;
import Arbiter :: *;

import ConnectableF :: *;
import DataTypes :: *;


typedef struct {
    tAddr                                               addr;
    tLen                                                totalLen;
} DtldStreamMemAccessMeta#(type tAddr, type tLen) deriving(Bits, FShow);

typedef struct {
    tData                                                       data;
    Bit#(TAdd#(1, TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH))))    byteNum;
    Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))              startByteIdx;
    Bool                                                        isFirst;
    Bool                                                        isLast;
} DtldStreamData#(type tData) deriving (FShow, Bits);



interface DtldStreamMasterWritePipes#(type tData, type tAddr, type tLen);
    interface PipeOut#(DtldStreamMemAccessMeta#(tAddr, tLen))   writeMetaPipeOut;
    interface PipeOut#(DtldStreamData#(tData))                  writeDataPipeOut;
endinterface

interface DtldStreamMasterReadPipes#(type tData, type tAddr, type tLen);
    interface PipeOut#(DtldStreamMemAccessMeta#(tAddr, tLen))   readMetaPipeOut;
    interface PipeIn#(DtldStreamData#(tData))                   readDataPipeIn;
endinterface

interface DtldStreamMasterPipes#(type tData, type tAddr, type tLen);
    interface DtldStreamMasterWritePipes#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamMasterReadPipes#(tData, tAddr, tLen)   readPipeIfc;
endinterface

interface DtldStreamSlaveWritePipes#(type tData, type tAddr, type tLen);
    interface PipeIn#(DtldStreamMemAccessMeta#(tAddr, tLen))    writeMetaPipeIn;
    interface PipeIn#(DtldStreamData#(tData))                   writeDataPipeIn;
endinterface

interface DtldStreamSlaveReadPipes#(type tData, type tAddr, type tLen);
    interface PipeIn#(DtldStreamMemAccessMeta#(tAddr, tLen))     readMetaPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                   readDataPipeOut;
endinterface

interface DtldStreamSlavePipes#(type tData, type tAddr, type tLen);
    interface DtldStreamSlaveWritePipes#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamSlaveReadPipes#(tData, tAddr, tLen)   readPipeIfc;
endinterface




interface DtldStreamArbiterSlave#(numeric type channelCnt, type tData, type tAddr, type tLen);
    interface Vector#(channelCnt, DtldStreamSlavePipes#(tData, tAddr, tLen))     slaveIfcVec;
    interface DtldStreamMasterPipes#(tData, tAddr, tLen)                         masterIfc;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                  writeSourceChannelIdPipeOut;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                  readSourceChannelIdPipeOut;
endinterface


module mkDtldStreamArbiterSlave#(Integer depth, Bool needReadResp)(DtldStreamArbiterSlave#(channelCnt, tData, tAddr, tLen)) provisos (
        Bits#(tData, szData),
        Bits#(DtldStreamMemAccessMeta#(tAddr, tLen), szMeta),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx)
    );

    Vector#(channelCnt, DtldStreamSlavePipes#(tData, tAddr, tLen))     slaveIfcVecInst = newVector;

    Vector#(channelCnt, FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen)))            slaveSideQueueVecWm     <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(DtldStreamData#(tData)))                           slaveSideQueueVecWd     <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen)))            slaveSideQueueVecRm     <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(DtldStreamData#(tData)))                           slaveSideQueueVecRd     <- replicateM(mkFIFOF);

    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))            masterSideQueueWm   <-  mkFIFOF;
    FIFOF#(DtldStreamData#(tData))                           masterSideQueueWd   <-  mkFIFOF;
    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))            masterSideQueueRm   <-  mkFIFOF;
    FIFOF#(DtldStreamData#(tData))                           masterSideQueueRd   <-  mkFIFOF;

    FIFOF#(tChannelIdx)     writeSourceChannelIdPipeOutQueue <- mkFIFOF;
    FIFOF#(tChannelIdx)     readSourceChannelIdPipeOutQueue  <- mkFIFOF;


    Arbiter_IFC#(channelCnt) writeArbiter <- mkArbiter(False);
    Arbiter_IFC#(channelCnt) readArbiter  <- mkArbiter(False);

    Reg#(Bool) isWriteFirstBeatReg <- mkReg(True);

    Reg#(tChannelIdx) curWriteChannelIdxReg <- mkRegU;

    FIFOF#(tChannelIdx) readKeepOrderQueue  <- mkSizedFIFOF(depth);

    rule sendWriteArbitReq if (isWriteFirstBeatReg);
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (slaveSideQueueVecWm[channelIdx].notEmpty && slaveSideQueueVecWd[channelIdx].notEmpty) begin
                writeArbiter.clients[channelIdx].request;
            end
        end
    endrule

    rule recvWriteArbitResp if (isWriteFirstBeatReg);
        Maybe#(DtldStreamMemAccessMeta#(tAddr, tLen)) wmMaybe = tagged Invalid;
        DtldStreamData#(tData) wd = ?;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (writeArbiter.clients[channelIdx].grant) begin
                wmMaybe = tagged Valid slaveSideQueueVecWm[channelIdx].first;
                wd      = slaveSideQueueVecWd[channelIdx].first;
                slaveSideQueueVecWm[channelIdx].deq;
                slaveSideQueueVecWd[channelIdx].deq;

                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (wmMaybe matches tagged Valid .wm) begin
            masterSideQueueWm.enq(wm);
            masterSideQueueWd.enq(wd);
            isWriteFirstBeatReg <= wd.isLast;
            curWriteChannelIdxReg <= curChannelIdx;
            writeSourceChannelIdPipeOutQueue.enq(curChannelIdx);
        end
    endrule

    rule forwardMoreWriteBeat if (!isWriteFirstBeatReg);
        let wd  = slaveSideQueueVecWd[curWriteChannelIdxReg].first;
        slaveSideQueueVecWd[curWriteChannelIdxReg].deq;
        masterSideQueueWd.enq(wd);
        isWriteFirstBeatReg <= wd.isLast;
    endrule

    rule sendReadArbitReq;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (slaveSideQueueVecRm[channelIdx].notEmpty) begin
                readArbiter.clients[channelIdx].request;
            end
        end
    endrule

    rule recvReadArbitResp;
        Maybe#(DtldStreamMemAccessMeta#(tAddr, tLen)) rmMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (readArbiter.clients[channelIdx].grant) begin
                rmMaybe = tagged Valid slaveSideQueueVecRm[channelIdx].first;
                slaveSideQueueVecRm[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (rmMaybe matches tagged Valid .rm) begin
            masterSideQueueRm.enq(rm);
            if (needReadResp) begin
                readKeepOrderQueue.enq(curChannelIdx);
            end
            readSourceChannelIdPipeOutQueue.enq(curChannelIdx);
        end
    endrule

    if (needReadResp) begin
        rule forwardReadResp;
            let rd = masterSideQueueRd.first;
            masterSideQueueRd.deq;

            let channelIdx = readKeepOrderQueue.first;
            slaveSideQueueVecRd[channelIdx].enq(rd);

            if (rd.isLast) begin
                readKeepOrderQueue.deq;
            end
        endrule
    end


    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        slaveIfcVecInst[channelIdx] = (
            interface DtldStreamSlavePipes 
                interface DtldStreamSlaveWritePipes writePipeIfc;
                    interface  writeMetaPipeIn  = toPipeIn(slaveSideQueueVecWm[channelIdx]);
                    interface  writeDataPipeIn  = toPipeIn(slaveSideQueueVecWd[channelIdx]);
                endinterface

                interface DtldStreamSlaveReadPipes readPipeIfc;
                    interface  readMetaPipeIn  = toPipeIn(slaveSideQueueVecRm[channelIdx]);
                    interface  readDataPipeOut = toPipeOut(slaveSideQueueVecRd[channelIdx]);
                endinterface
            endinterface);
    end

    interface slaveIfcVec = slaveIfcVecInst;
    interface DtldStreamMasterPipes masterIfc;
        interface DtldStreamMasterWritePipes writePipeIfc;
            interface  writeMetaPipeOut  = toPipeOut(masterSideQueueWm);
            interface  writeDataPipeOut  = toPipeOut(masterSideQueueWd);
        endinterface

        interface DtldStreamMasterReadPipes readPipeIfc;
            interface  readMetaPipeOut  = toPipeOut(masterSideQueueRm);
            interface  readDataPipeIn   = toPipeIn(masterSideQueueRd);
        endinterface
    endinterface

    interface writeSourceChannelIdPipeOut = toPipeOut(writeSourceChannelIdPipeOutQueue);
    interface readSourceChannelIdPipeOut  = toPipeOut(readSourceChannelIdPipeOutQueue);
endmodule

