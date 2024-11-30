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
        Alias#(Bit#(szBitIdx), tBitIdx),
        Alias#(Bit#(szBitCnt), tBitCnt),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(szByteIdx, 1), szByteCnt),
        NumAlias#(TAdd#(szByteIdx, BIT_BYTE_CONVERT_SHIFT_NUM), szBitIdx),
        NumAlias#(TAdd#(szByteCnt, BIT_BYTE_CONVERT_SHIFT_NUM), szBitCnt),
        NumAlias#(TDiv#(szDataInByte, TExp#(nLogOfByteAlign)), nAlignBlockPerBeat),
        NumAlias#(TSub#(TLog#(szDataInByte), nLogOfByteAlign), szAlignBlockIdx),
        NumAlias#(TAdd#(szAlignBlockIdx, 1), szAlignBlockCnt)
    );
    FIFOF#(DtldStreamData#(tData))  dataPipeInQueue                 <- mkFIFOF;
    FIFOF#(Bool)                    isLastStreamFlagPipeInQueue     <- mkFIFOF;
    FIFOF#(DtldStreamData#(tData))  dataPipeOutQueue                <- mkFIFOF;

    Reg#(DtldStreamConcatorState)       curStateReg                 <- mkReg(DtldStreamConcatorStateIdle);

    Reg#(Bool)                          isWholeOutputFirstBeatReg                   <- mkReg(True);
    Reg#(Bool)                          isFirstStreamReg                            <- mkReg(True);
    Reg#(Bool)                          isLastStreamReg                             <- mkRegU;
    Reg#(tAlignBlockIdx)                shiftAlignBlockCntReg                       <- mkReg(0);
    Reg#(DtldStreamData#(tData))        previousDsReg                               <- mkRegU;
    Reg#(tByteCnt)                      previousBeatByteLeftReg                     <- mkRegU;

    rule idleState if (curStateReg == DtldStreamConcatorStateIdle);
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        Bool isFirstStream      = isFirstStreamReg;
        let isLastStream = isLastStreamFlagPipeInQueue.first;
        isLastStreamFlagPipeInQueue.deq;
        if (dsIn.isLast && isLastStream) begin
            // for only beat in only stream
            immAssert(
                dsIn.isFirst && isWholeOutputFirstBeatReg && isFirstStreamReg,
                "must be first",
                $format( "dsIn.isFirst=", fshow(dsIn.isFirst),
                         ", isFirstStreamReg=", fshow(isFirstStreamReg),
                         ", isWholeOutputFirstBeatReg=", fshow(isWholeOutputFirstBeatReg))
            );
            dataPipeOutQueue.enq(dsIn);
        end
        else begin
            curStateReg <= DtldStreamConcatorStateOutputMore;
            previousDsReg <= dsIn;
            isLastStreamReg <= isLastStream;
            previousBeatByteLeftReg <= dsIn.byteNum;

            if (dsIn.isLast && isFirstStream) begin
                isFirstStream = False;
                shiftAlignBlockCntReg <=  truncate((fromInteger(valueOf(szDataInByte) - 1) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx)) >> valueOf(nLogOfByteAlign)) + 1;
            end
            
            immAssert(
                pack(zeroExtend(dsIn.startByteIdx) + dsIn.byteNum)[1:0] == 2'b0,
                "not aligned",
                $format("dsIn=", fshow(dsIn))
            );
        end

        isFirstStreamReg <= isFirstStream;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamConcator idleState"),
        //     toBlue(", dsIn="), fshow(dsIn),
        //     toBlue(", isFirstStreamReg="), fshow(isFirstStreamReg),
        //     toBlue(", isLastStreamReg="), fshow(isLastStreamReg),
        //     toBlue(", isLastStream="), fshow(isLastStream)
        // );
    endrule

    rule outputState if (curStateReg == DtldStreamConcatorStateOutputMore);
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        Bool isFirstStream      = isFirstStreamReg;
        Bool isLastStream       = isLastStreamReg;
        Bool newIsLastStream    = isLastStreamReg; 
        if (dsIn.isFirst) begin
            newIsLastStream = isLastStreamFlagPipeInQueue.first;
            isLastStreamFlagPipeInQueue.deq;
            isLastStreamReg <= newIsLastStream;
        end

        if (!(dsIn.isLast && newIsLastStream)) begin
            immAssert(
                pack(zeroExtend(dsIn.startByteIdx) + dsIn.byteNum)[1:0] == 2'b0,
                "not aligned",
                $format("dsIn=", fshow(dsIn))
            );
        end


        tAlignBlockIdx curDsAlignBlockRightShiftCnt = shiftAlignBlockCntReg;
        tAlignBlockCnt curDsAlignBlockLeftShiftCnt  = fromInteger(valueOf(nAlignBlockPerBeat)) - zeroExtend(shiftAlignBlockCntReg);
        
        tByteIdx curDsByteRightShiftCnt = zeroExtend(curDsAlignBlockRightShiftCnt) << valueOf(nLogOfByteAlign);
        tByteCnt curDsByteLeftShiftCnt  = zeroExtend(curDsAlignBlockLeftShiftCnt)  << valueOf(nLogOfByteAlign);

        tBitIdx curDsBitRightShiftCnt = zeroExtend(curDsByteRightShiftCnt) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        tBitCnt curDsBitLeftShiftCnt  = zeroExtend(curDsByteLeftShiftCnt)  << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        
        tData dataClearMask = unpack(-1);
        dataClearMask = dataClearMask >> (curDsBitRightShiftCnt);

        let curOutBeatData = (previousDsReg.data & dataClearMask) | (dsIn.data << curDsBitLeftShiftCnt);
        let nextBeatPrevDs = dsIn;
        nextBeatPrevDs.data = nextBeatPrevDs.data >> curDsBitRightShiftCnt;
        previousDsReg <= nextBeatPrevDs;


        let isFirst = isWholeOutputFirstBeatReg;
        let isLast = False;

        let isDsInOnly = dsIn.isFirst && dsIn.isLast;

        tByteCnt previousBeatEmptyByteCnt = zeroExtend(curDsByteRightShiftCnt);
        
        // `isLastStream` comes from the register so it doesn't reflact the newest packet's state.
        // if the last stream only has one beat, then we must consult the newest isLastStream info.
        if ((isLastStream && dsIn.isLast) || (isDsInOnly && newIsLastStream)) begin
            if (previousBeatEmptyByteCnt >= dsIn.byteNum) begin
                isLast = True;
                curStateReg <= DtldStreamConcatorStateIdle;
            end
            else begin
                curStateReg <= DtldStreamConcatorStateOutputExtra;
            end
        end

        let startByteIdx = isFirst ? previousDsReg.startByteIdx : 0;

        let byteNum;
        if (isFirst && isLast) begin
            // byteNum = previousDsReg.byteNum + dsIn.byteNum;
            byteNum = dsIn.byteNum + previousBeatByteLeftReg;
        end
        else if (isLast) begin
            // byteNum = dsIn.byteNum + (fromInteger(valueOf(szDataInByte)) - previousBeatEmptyByteCnt);
            byteNum = dsIn.byteNum + previousBeatByteLeftReg;
        end
        else begin
            byteNum = fromInteger(valueOf(szDataInByte)) - zeroExtend(startByteIdx);
        end

        previousBeatByteLeftReg <= previousBeatByteLeftReg + dsIn.byteNum - byteNum;

        let ds = DtldStreamData {
            data: curOutBeatData,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };
        dataPipeOutQueue.enq(ds);

        isWholeOutputFirstBeatReg <= isLast;

        tAlignBlockIdx newshiftAlignBlockCnt = shiftAlignBlockCntReg;
        if (dsIn.isLast && isFirstStream) begin
            isFirstStream = False;
            newshiftAlignBlockCnt =  truncate((fromInteger(valueOf(szDataInByte) - 1) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx)) >> valueOf(nLogOfByteAlign)) + 1;
        end

        if (isLast) begin
            newshiftAlignBlockCnt = 0;
            isFirstStream = True;
        end
        shiftAlignBlockCntReg <= newshiftAlignBlockCnt;
        isFirstStreamReg <= isFirstStream;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamConcator outputState"),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", dsIn="), fshow(dsIn),
        //     toBlue(", dsOut="), fshow(ds),
        //     toBlue(", dataClearMask="), fshow(dataClearMask),
        //     toBlue(", curDsAlignBlockRightShiftCnt="), fshow(curDsAlignBlockRightShiftCnt),
        //     toBlue(", curDsAlignBlockLeftShiftCnt="), fshow(curDsAlignBlockLeftShiftCnt),
        //     toBlue(", curDsByteRightShiftCnt="), fshow(curDsByteRightShiftCnt),
        //     toBlue(", curDsByteLeftShiftCnt="), fshow(curDsByteLeftShiftCnt),
        //     toBlue(", isFirstStreamReg="), fshow(isFirstStreamReg),
        //     toBlue(", isLastStreamReg="), fshow(isLastStreamReg),
        //     toBlue(", shiftAlignBlockCntReg="), fshow(shiftAlignBlockCntReg),
        //     toBlue(", previousBeatEmptyByteCnt="), fshow(previousBeatEmptyByteCnt),
        //     toBlue(", previousBeatByteLeftReg="), fshow(previousBeatByteLeftReg)
        // );
    endrule

    rule outputExtraState if (curStateReg == DtldStreamConcatorStateOutputExtra);
        tAlignBlockIdx shiftAlignBlockCnt = 0;
        Bool isFirstStream = True;

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

                if (dsIn.isLast && isFirstStream) begin
                    isFirstStream = False;
                    shiftAlignBlockCnt = truncate((fromInteger(valueOf(szDataInByte) - 1) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx)) >> valueOf(nLogOfByteAlign)) + 1;
                end

                isLastStreamReg <= isLastStream;
                previousDsReg <= dsIn;
                curStateReg <= DtldStreamConcatorStateOutputMore;
                previousBeatByteLeftReg <= dsIn.byteNum;
            end
        end
        else begin
            curStateReg <= DtldStreamConcatorStateIdle;
        end

        let byteNum = previousBeatByteLeftReg;
        let ds = DtldStreamData {
            data: previousDsReg.data,
            byteNum: byteNum,
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        };
        dataPipeOutQueue.enq(ds);

        shiftAlignBlockCntReg <= shiftAlignBlockCnt;
        isFirstStreamReg    <= isFirstStream;
        isWholeOutputFirstBeatReg <= True;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamConcator outputExtraState"),
        //     toBlue(", shiftAlignBlockCntReg="), fshow(shiftAlignBlockCntReg),
        //     toBlue(", dsIn="), fshow(ds)
        // );
    endrule

    interface dataPipeIn                = toPipeIn(dataPipeInQueue);
    interface isLastStreamFlagPipeIn    = toPipeIn(isLastStreamFlagPipeInQueue);
    interface dataPipeOut               = toPipeOut(dataPipeOutQueue);
endmodule




interface DtldStreamSplitor#(type tData, type tStreamAlignBlockCount, numeric type nLogOfAlign);
    interface PipeIn#(DtldStreamData#(tData))                    dataPipeIn;
    interface PipeIn#(tStreamAlignBlockCount)                    streamAlignBlockCountPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                   dataPipeOut;
endinterface


typedef enum {
    DtldStreamSplitorStateOutput,
    DtldStreamSplitorStateOutputLastStream
} DtldStreamSplitorState deriving(Eq, FShow, Bits);



        
module mkDtldStreamSplitor(DtldStreamSplitor#(tData, tStreamAlignBlockCount, nLogOfByteAlign)) provisos(
        Bits#(tData, szData),
        Bitwise#(tData),
        Bits#(tStreamAlignBlockCount, szStreamAlignBlockCount),
        FShow#(DtldStream::DtldStreamData#(tData)),
        Alias#(Bit#(szAlignBlockIdx), tAlignBlockIdx),
        Alias#(Bit#(szAlignBlockCnt), tAlignBlockCnt),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteCnt), tByteCnt),
        Alias#(Bit#(szBitIdx), tBitIdx),
        Alias#(Bit#(szBitCnt), tBitCnt),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(1, szByteIdx), szByteCnt),
        NumAlias#(TAdd#(szByteIdx, BIT_BYTE_CONVERT_SHIFT_NUM), szBitIdx),
        NumAlias#(TAdd#(szByteCnt, BIT_BYTE_CONVERT_SHIFT_NUM), szBitCnt),
        NumAlias#(TDiv#(szDataInByte, TExp#(nLogOfByteAlign)), nAlignBlockPerBeat),
        NumAlias#(TSub#(TLog#(szDataInByte), nLogOfByteAlign), szAlignBlockIdx),
        NumAlias#(TAdd#(1, szAlignBlockIdx), szAlignBlockCnt),
        Ord#(tStreamAlignBlockCount),
        Add#(a__, szAlignBlockCnt, szStreamAlignBlockCount),
        Add#(b__, szByteCnt, szStreamAlignBlockCount),
        Eq#(tStreamAlignBlockCount),
        Arith#(tStreamAlignBlockCount),
        FShow#(tStreamAlignBlockCount)
    );
    FIFOF#(DtldStreamData#(tData))  dataPipeInQueue                     <- mkFIFOF;
    FIFOF#(tStreamAlignBlockCount)  streamAlignBlockCountPipeInQueue    <- mkFIFOF;
    FIFOF#(DtldStreamData#(tData))  dataPipeOutQueue                    <- mkFIFOF;

    Reg#(DtldStreamSplitorState)       curStateReg                 <- mkReg(DtldStreamSplitorStateOutput);

    Reg#(Bool)  isSubStreamFirstReg     <- mkReg(True);
    
    Reg#(DtldStreamData#(tData))        previousDsReg                               <- mkReg(unpack(0));
    Reg#(tAlignBlockCnt)                shiftAlignBlockCntReg                       <- mkReg(fromInteger(valueOf(nAlignBlockPerBeat)));
    Reg#(tStreamAlignBlockCount)        alignBlockCntLeftForSubDsReg                <- mkRegU;


    function tAlignBlockCnt getAlignBlockCountFromDs(DtldStreamData#(tData) ds);
        tByteCnt lastByteIdx = ds.byteNum + zeroExtend(ds.startByteIdx) - 1;
        tAlignBlockCnt alignBlockCnt = truncate(lastByteIdx >> valueOf(nLogOfByteAlign)) + 1;
        return alignBlockCnt;
    endfunction

    rule outputState if (curStateReg == DtldStreamSplitorStateOutput);
        let subDsAlignBlockCount = alignBlockCntLeftForSubDsReg;
        if (isSubStreamFirstReg) begin
            subDsAlignBlockCount = streamAlignBlockCountPipeInQueue.first;
            streamAlignBlockCountPipeInQueue.deq;
        end
        
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        let previousDs = previousDsReg;
        if (dsIn.isFirst) begin
            // only clear important bits, data will be masked out, so no need to clear. save a lot of mux
            previousDs.byteNum = 0;
            previousDs.startByteIdx = 0;
        end

        let alignBlockCntOfInputDs = getAlignBlockCountFromDs(dsIn);
        let alignBlockCntOfPrevDs = getAlignBlockCountFromDs(previousDs);
        let totalAvailableBlockCnt = alignBlockCntOfInputDs + alignBlockCntOfPrevDs;

        tAlignBlockCnt curDsAlignBlockRightShiftCnt = shiftAlignBlockCntReg;
        tAlignBlockCnt curDsAlignBlockLeftShiftCnt  = fromInteger(valueOf(nAlignBlockPerBeat)) - zeroExtend(shiftAlignBlockCntReg);
        
        tByteCnt curDsByteRightShiftCnt = zeroExtend(curDsAlignBlockRightShiftCnt) << valueOf(nLogOfByteAlign);
        tByteCnt curDsByteLeftShiftCnt  = zeroExtend(curDsAlignBlockLeftShiftCnt)  << valueOf(nLogOfByteAlign);

        tBitCnt curDsBitRightShiftCnt = zeroExtend(curDsByteRightShiftCnt) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        tBitCnt curDsBitLeftShiftCnt  = zeroExtend(curDsByteLeftShiftCnt)  << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);

        tData dataClearMask = unpack(-1);
        dataClearMask = dataClearMask >> (curDsBitRightShiftCnt);

        tData dataForOutput = ( previousDs.data & dataClearMask ) | (dsIn.data << curDsBitLeftShiftCnt);

        let isFirst = isSubStreamFirstReg;
        let isLast = subDsAlignBlockCount <= unpack(fromInteger(valueOf(nAlignBlockPerBeat)));

        isSubStreamFirstReg <= isLast;
        
        let byteNumAvaliableNow = previousDs.byteNum + dsIn.byteNum;

        // since this already last beat of sub stream, then the subDsAlignBlockCount must be small enough. the higher bits can be truncated.
        tAlignBlockCnt alignBlockCntSmallForLastBeatOfSubStream = truncate(pack(subDsAlignBlockCount));
        tAlignBlockCnt alignBlockCntOfOutputBeat = isLast ? alignBlockCntSmallForLastBeatOfSubStream : fromInteger(valueOf(nAlignBlockPerBeat));

        tByteCnt byteNum = ?;
        tByteIdx startByteIdx = dsIn.isFirst ? dsIn.startByteIdx : 0;
        if (dsIn.isFirst && dsIn.isLast) begin
            immAssert(
                isFirst && isLast,
                "if input stream is a only one, then output beat must also be a only one. the required sub-stream is too long",
                $format("dsIn=", fshow(dsIn), 
                        "subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
            );

            immAssert(
                subDsAlignBlockCount <= unpack(zeroExtend(totalAvailableBlockCnt)),
                "required sub stream is longer than original input stream",
                $format("alignBlockCntSmallForLastBeatOfSubStream=", fshow(alignBlockCntSmallForLastBeatOfSubStream), ", totalAvailableBlockCnt=", fshow(totalAvailableBlockCnt))
            );

            tByteCnt bytesNeededIfAllAlignBlockIsFull = zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign);
            if (alignBlockCntSmallForLastBeatOfSubStream == totalAvailableBlockCnt) begin
                immAssert(isLast, "must be isLast here", $format(""));
                byteNum = byteNumAvaliableNow;
            end
            else begin
                // still have a tail, need goto next rule
                byteNum = bytesNeededIfAllAlignBlockIsFull - zeroExtend(dsIn.startByteIdx);
                curStateReg <= DtldStreamSplitorStateOutputLastStream;
            end
        end
        else if (dsIn.isFirst) begin
            immAssert(
                isFirst,
                "output must also be first beat",
                $format("dsIn=", fshow(dsIn), 
                        "subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
            );

            if (isLast) begin
                byteNum = (zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign)) - zeroExtend(dsIn.startByteIdx);
            end
            else begin
                byteNum = dsIn.byteNum;
            end
        end
        else if (dsIn.isLast) begin
            if (isLast) begin
                immAssert(
                    subDsAlignBlockCount <= unpack(zeroExtend(totalAvailableBlockCnt)),
                    "required sub stream is longer than original input stream",
                    $format("alignBlockCntSmallForLastBeatOfSubStream=", fshow(alignBlockCntSmallForLastBeatOfSubStream), ", totalAvailableBlockCnt=", fshow(totalAvailableBlockCnt))
                );
                tByteCnt bytesNeededIfAllAlignBlockIsFull = zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign);
                if (alignBlockCntSmallForLastBeatOfSubStream == totalAvailableBlockCnt) begin
                    byteNum = byteNumAvaliableNow;
                end
                else begin
                    // still have a tail, need goto next rule
                    byteNum = bytesNeededIfAllAlignBlockIsFull;
                    curStateReg <= DtldStreamSplitorStateOutputLastStream;
                end
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
                curStateReg <= DtldStreamSplitorStateOutputLastStream;
            end
        end
        else begin
            if (isLast) begin
                byteNum = zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign);
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
            end
        end

        let ds = DtldStreamData {
            data: dataForOutput,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };
        dataPipeOutQueue.enq(ds);


        alignBlockCntLeftForSubDsReg <= subDsAlignBlockCount - unpack(zeroExtend(alignBlockCntOfOutputBeat));

        tAlignBlockCnt usedAlignBlockCntOfThisInputBeat = alignBlockCntOfOutputBeat - alignBlockCntOfPrevDs;

        tByteCnt inDsByteRightShiftCnt = zeroExtend(usedAlignBlockCntOfThisInputBeat) << valueOf(nLogOfByteAlign);
        tBitCnt inDsBitRightShiftCnt   = zeroExtend(inDsByteRightShiftCnt) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);

        dsIn.data = dsIn.data >> inDsBitRightShiftCnt;
        dsIn.startByteIdx = 0; // when using as previous beat, the first maybe unaligned block must already been consumed.
        dsIn.byteNum = byteNumAvaliableNow - byteNum;
        
        previousDsReg <= dsIn;

        shiftAlignBlockCntReg <= dsIn.isLast ? fromInteger(valueOf(nAlignBlockPerBeat)) : usedAlignBlockCntOfThisInputBeat;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamSplitor outputState"),
        //     toBlue(", subDsAlignBlockCount="), fshow(subDsAlignBlockCount),
        //     toBlue(", alignBlockCntOfInputDs="), fshow(alignBlockCntOfInputDs),
        //     toBlue(", curDsAlignBlockRightShiftCnt="), fshow(curDsAlignBlockRightShiftCnt),
        //     toBlue(", curDsAlignBlockLeftShiftCnt="), fshow(curDsAlignBlockLeftShiftCnt),
        //     toBlue(", dataClearMask="), fshow(dataClearMask),
        //     toBlue(", byteNumAvaliableNow="), fshow(byteNumAvaliableNow),
        //     toBlue(", alignBlockCntOfOutputBeat="), fshow(alignBlockCntOfOutputBeat),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", dsIn="), fshow(dsIn),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule outputLastStreamState if (curStateReg == DtldStreamSplitorStateOutputLastStream);
        let subDsAlignBlockCount = streamAlignBlockCountPipeInQueue.first;
        streamAlignBlockCountPipeInQueue.deq;


        immAssert(
            unpack(zeroExtend(((previousDsReg.byteNum-1) >> valueOf(nLogOfByteAlign)) + 1)) == subDsAlignBlockCount,
            "last sub stream doesn't match input stream length",
            $format("previousDsReg=", fshow(previousDsReg), ", subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
        );

        let ds = DtldStreamData {
            data: previousDsReg.data,
            byteNum: previousDsReg.byteNum,
            startByteIdx: 0,
            isFirst: True,
            isLast: True
        };
        dataPipeOutQueue.enq(ds);

        curStateReg <= DtldStreamSplitorStateOutput;
        
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamSplitor outputLastStreamState"),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface dataPipeIn                    = toPipeIn(dataPipeInQueue);
    interface streamAlignBlockCountPipeIn   = toPipeIn(streamAlignBlockCountPipeInQueue);
    interface dataPipeOut                   = toPipeOut(dataPipeOutQueue);
endmodule