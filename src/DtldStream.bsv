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

interface DtldStreamBiDirSlavePipes#(type tData, type tAddr, type tLen);
    interface DtldStreamSlaveWritePipes#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamSlaveReadPipes#(tData, tAddr, tLen)   readPipeIfc;
endinterface




interface DtldStreamArbiterSlave#(numeric type channelCnt, type tData, type tAddr, type tLen);
    interface Vector#(channelCnt, DtldStreamBiDirSlavePipes#(tData, tAddr, tLen))       slaveIfcVec;
    interface DtldStreamMasterPipes#(tData, tAddr, tLen)                                masterIfc;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                         writeSourceChannelIdPipeOut;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                         readSourceChannelIdPipeOut;
endinterface


module mkDtldStreamArbiterSlave#(Integer depth, Bool needReadResp)(DtldStreamArbiterSlave#(channelCnt, tData, tAddr, tLen)) provisos (
        Bits#(tData, szData),
        Bits#(DtldStreamMemAccessMeta#(tAddr, tLen), szMeta),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx)
    );

    Vector#(channelCnt, DtldStreamBiDirSlavePipes#(tData, tAddr, tLen))     slaveIfcVecInst = newVector;

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
            interface DtldStreamBiDirSlavePipes 
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


// This concator can concat one or more datastream fragments into a single big datastream.
// The first (or only) fragment's first (or only) beat can have startByteIdx != 0
// The first (or only) fragment's last (or only) beat can have invalid bytes at the tail, i.e., (startByteIdx + byteNum < byte_nume_per_beat)
// The last (or only) fragment's last beat can have invalid bytes at the tail, i.e., (startByteIdx + byteNum < byte_nume_per_beat)
// All the other fragments's beats must be full, i.e., startByteIdx == 0 && startByteIdx == byte_nume_per_beat
interface DtldStreamConcator#(type tData, numeric type nLogOfAlign);
    interface PipeIn#(DtldStreamData#(tData))                    dataPipeIn;
    interface PipeIn#(Bool)                                      isLastStreamFlagPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                   dataPipeOut;
endinterface

typedef enum {
    DtldStreamConcatorStateIdle,
    DtldStreamConcatorStateOutputMore,
    DtldStreamConcatorStateOutputExtra
} DtldStreamConcatorState deriving(Eq, FShow, Bits);

module mkDtldStreamConcator(DtldStreamConcator#(tData, nLogOfByteAlign)) provisos(
        Bits#(tData, szData),
        Bitwise#(tData),
        FShow#(DtldStream::DtldStreamData#(tData)),
        Alias#(Bit#(szAlignBlockIdx), tAlignBlockIdx),
        Alias#(Bit#(szAlignBlockCnt), tAlignBlockCnt),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteCnt), tByteCnt),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(szByteIdx, 1), szByteCnt),
        NumAlias#(TDiv#(szDataInByte, TExp#(nLogOfByteAlign)), nAlignBlockPerBeat),
        NumAlias#(TSub#(TLog#(szDataInByte), nLogOfByteAlign), szAlignBlockIdx),
        NumAlias#(TAdd#(szAlignBlockIdx, 1), szAlignBlockCnt)
    );
    FIFOF#(DtldStreamData#(tData))  dataPipeInQueue                 <- mkLFIFOF;
    FIFOF#(Bool)                    isLastStreamFlagPipeInQueue     <- mkLFIFOF;
    FIFOF#(DtldStreamData#(tData))  dataPipeOutQueue                <- mkLFIFOF;

    Reg#(DtldStreamConcatorState)       curStateReg                 <- mkReg(DtldStreamConcatorStateIdle);

    Reg#(Bool)                          isWholeOutputFirstBeatReg                   <- mkReg(True);
    Reg#(Bool)                          isLastStreamReg                             <- mkRegU;
    Reg#(tAlignBlockIdx)                shiftAlignBlockCntReg                       <- mkReg(0);
    Reg#(DtldStreamData#(tData))        previousDsReg                               <- mkRegU;

    rule idleState if (curStateReg == DtldStreamConcatorStateIdle);
        let ds = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        let isLastStream = isLastStreamFlagPipeInQueue.first;
        isLastStreamFlagPipeInQueue.deq;

        if (ds.isLast && isLastStream) begin
            // for only beat in only stream
            immAssert(
                ds.isFirst && isWholeOutputFirstBeatReg,
                "must be first",
                $format( "ds.isFirst=", fshow(ds.isFirst),
                         ", isWholeOutputFirstBeatReg=", fshow(isWholeOutputFirstBeatReg))
            );
            dataPipeOutQueue.enq(ds);
        end
        else begin
            curStateReg <= DtldStreamConcatorStateOutputMore;
            previousDsReg <= ds;
            isLastStreamReg <= isLastStream;


            immAssert(
                pack(zeroExtend(ds.startByteIdx) + ds.byteNum)[1:0] == 2'b0,
                "not aligned",
                $format("startByteIdx=", fshow(ds.startByteIdx), ", byteNum=", fshow(ds.byteNum))
            );
        end
    endrule

    rule outputState if (curStateReg == DtldStreamConcatorStateOutputMore);
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        if (!(dsIn.isLast && isLastStreamReg)) begin
            immAssert(
                pack(zeroExtend(dsIn.startByteIdx) + dsIn.byteNum)[1:0] == 2'b0,
                "not aligned",
                $format("startByteIdx=", fshow(dsIn.startByteIdx), ", byteNum=", fshow(dsIn.byteNum))
            );
        end

        tAlignBlockIdx curDsAlignBlockRightShiftCnt = shiftAlignBlockCntReg;
        tAlignBlockCnt curDsAlignBlockLeftShiftCnt  = fromInteger(valueOf(nAlignBlockPerBeat)) - zeroExtend(shiftAlignBlockCntReg);
        
        tByteIdx curDsByteRightShiftCnt = zeroExtend(curDsAlignBlockRightShiftCnt) << valueOf(nLogOfByteAlign);
        tByteCnt curDsByteLeftShiftCnt  = zeroExtend(curDsAlignBlockLeftShiftCnt)  << valueOf(nLogOfByteAlign);
        
        tData dataClearMask = unpack(-1);
        dataClearMask = dataClearMask >> (curDsByteRightShiftCnt);

        let curOutBeatData = (previousDsReg.data & dataClearMask) | (dsIn.data << curDsByteLeftShiftCnt);
        let nextBeatPrevDs = dsIn;
        nextBeatPrevDs.data = nextBeatPrevDs.data >> curDsByteRightShiftCnt;
        previousDsReg <= nextBeatPrevDs;


        let isFirst = isWholeOutputFirstBeatReg;
        let isLast = False;
        tByteCnt previousBeatEmptyByteCnt = zeroExtend(curDsByteRightShiftCnt);
        if (isLastStreamReg && dsIn.isLast) begin
            if (previousBeatEmptyByteCnt >= dsIn.byteNum) begin
                isLast = True;
                curStateReg <= DtldStreamConcatorStateIdle;
            end
            else begin
                curStateReg <= DtldStreamConcatorStateOutputMore;
            end
        end

        let startByteIdx = isFirst ? previousDsReg.startByteIdx : 0;

        let byteNum;
        if (isFirst && isLast) begin
            immFail(
                "should not reach here. only beat should be handled by idleState", 
                $format("dsIn=", fshow(dsIn), ", previousDsReg=", fshow(previousDsReg))
            );
            byteNum = 0;
        end
        else if (isLast) begin
            byteNum = dsIn.byteNum - previousBeatEmptyByteCnt;
        end
        else begin
            byteNum = fromInteger(valueOf(szDataInByte)) - zeroExtend(startByteIdx);
        end

        let ds = DtldStreamData {
            data: curOutBeatData,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };

        isWholeOutputFirstBeatReg <= isLast;

        if (isLast) begin
            shiftAlignBlockCntReg <= 0;
        end
    endrule

    rule outputExtraState if (curStateReg == DtldStreamConcatorStateOutputExtra);
        if (dataPipeInQueue.notEmpty && isLastStreamFlagPipeInQueue.notEmpty) begin
            let dsIn = dataPipeInQueue.first;
            let isLastStream = isLastStreamFlagPipeInQueue.first;

            if (dsIn.isLast && isLastStream) begin
                // only stream, let DtldStreamConcatorStateIdle state to handle it. 
                curStateReg <= DtldStreamConcatorStateIdle;
            end
            else begin
                dataPipeInQueue.deq;
                isLastStreamFlagPipeInQueue.deq;

                isLastStreamReg <= isLastStream;
                previousDsReg <= dsIn;
                curStateReg <= DtldStreamConcatorStateOutputMore;
            end
        end
        else begin
            curStateReg <= DtldStreamConcatorStateIdle;
        end

        tByteIdx previousBeatEmptyByteCnt = zeroExtend(shiftAlignBlockCntReg) << valueOf(nLogOfByteAlign);
        let byteNum = previousDsReg.byteNum - zeroExtend(previousBeatEmptyByteCnt);
        let ds = DtldStreamData {
            data: previousDsReg.data,
            byteNum: byteNum,
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        };

        shiftAlignBlockCntReg <= 0;
    endrule

    interface dataPipeIn                = toPipeIn(dataPipeInQueue);
    interface isLastStreamFlagPipeIn    = toPipeIn(isLastStreamFlagPipeInQueue);
    interface dataPipeOut               = toPipeOut(dataPipeOutQueue);
endmodule

