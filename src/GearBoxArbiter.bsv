import Vector :: *;
import FIFOF :: *;
import Cntrs :: * ;

import ConnectableF :: *;
import DataTypes :: *;
import PrimUtils :: *;
import AxiBus :: *;

typedef 4   GEARBOX_LOGIC_SIDE_CHANNEL_CNT;
typedef 4   GEARBOX_WIDTH_RATIO;

typedef 8   GEARBOX_INTERNAL_BANK_CNT;
typedef 64  GEARBOX_INTERNAL_BANK_DEPTH;

typedef TMul#(GEARBOX_INTERNAL_BANK_CNT, GEARBOX_INTERNAL_BANK_DEPTH)           GEARBOX_INTERNAL_BRAM_ROW_CNT;
typedef TLog#(GEARBOX_INTERNAL_BRAM_ROW_CNT)                                    GEARBOX_INTERNAL_BRAM_ADDR_WIDTH;
typedef Bit#(GEARBOX_INTERNAL_BRAM_ADDR_WIDTH)                                  GearBoxInternalBramAddr;
typedef Bit#(TLog#(GEARBOX_INTERNAL_BANK_CNT))                                  GearBoxInternalBankIdx;
typedef Bit#(TLog#(TAdd#(1, GEARBOX_INTERNAL_BANK_CNT)))                        GearBoxInternalBankCnt;
typedef Bit#(TLog#(GEARBOX_WIDTH_RATIO))                                        GearBoxInternalBankColIdx;
typedef Bit#(TLog#(GEARBOX_INTERNAL_BANK_DEPTH))                                GearBoxInternalBankRowIdx;


interface AxiGearBox4To1MM;
    interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, AxiSlavePipes#(AxiDataForLogic))   axiSlaveVec;
    interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, AxiMasterPipes#(AxiDataForHip))    axiMasterVec;
endinterface


typedef enum {
    GearBoxInternalWriteStateHandleFirst = 0,
    GearBoxInternalWriteStateHandleMore = 1
} GearBoxInternalWriteState deriving(FShow, Bits, Eq);

module mkAxiGearBox4To1MM(AxiGearBox4To1MM);

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatAw))                     axiPipeQueueForLogicVecAw   <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatW#(AxiDataForLogic)))    axiPipeQueueForLogicVecW    <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatB))                      axiPipeQueueForLogicVecB    <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatAr))                     axiPipeQueueForLogicVecAr   <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatR#(AxiDataForLogic)))    axiPipeQueueForLogicVecR    <- replicateM(mkFIFOF);

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatAw))                     axiPipeQueueForHipVecAw   <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatW#(AxiDataForHip)))      axiPipeQueueForHipVecW    <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatB))                      axiPipeQueueForHipVecB    <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatAr))                     axiPipeQueueForHipVecAr   <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatR#(AxiDataForHip)))      axiPipeQueueForHipVecR    <- replicateM(mkFIFOF);

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, AxiSlavePipes#(AxiDataForLogic)) axiSlaveVecInst  = newVector;
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, AxiMasterPipes#(AxiDataForHip))  axiMasterVecInst = newVector;
    for (Integer idx = 0; idx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); idx = idx + 1) begin
        axiSlaveVecInst[idx] = (interface AxiSlavePipes;
            interface AxiSlaveWritePipes writePipeIfc;
                interface writeAddrPipeIn   = toPipeIn(axiPipeQueueForLogicVecAw[idx]);
                interface writeDataPipeIn   = toPipeIn(axiPipeQueueForLogicVecW[idx]);
                interface writeRespPipeOut  = toPipeOut(axiPipeQueueForLogicVecB[idx]);
            endinterface

            interface AxiSlaveReadPipes  readPipeIfc;
                interface readAddrPipeIn    = toPipeIn(axiPipeQueueForLogicVecAr[idx]);
                interface readRespPipeOut   = toPipeOut(axiPipeQueueForLogicVecR[idx]);
            endinterface
        endinterface);

        axiMasterVecInst[idx] = (interface AxiMasterPipes;
            interface AxiMasterWritePipes writePipeIfc;
                interface writeAddrPipeOut      = toPipeOut(axiPipeQueueForHipVecAw[idx]);
                interface writeDataPipeOut      = toPipeOut(axiPipeQueueForHipVecW[idx]);
                interface writeRespPipeIn       = toPipeIn(axiPipeQueueForHipVecB[idx]);
            endinterface
    
            interface AxiMasterReadPipes  readPipeIfc;
                interface readAddrPipeOut   = toPipeOut(axiPipeQueueForHipVecAr[idx]);
                interface readRespPipeIn    = toPipeIn(axiPipeQueueForHipVecR[idx]);
            endinterface
        endinterface);
    end


    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(AxiAwlen))                         axiAwLenCounterForLogicSideRegVec       <- replicateM(mkRegU);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(AxiMmBeatAw))                      axiWriteReqMetaForLogicSideRegVec       <- replicateM(mkRegU);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankIdx))           axiWriteBankIdxForLogicSideRegVec       <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankColIdx))        axiWriteBankColIdxForLogicSideRegVec    <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankRowIdx))        axiWriteBankRowIdxForLogicSideRegVec    <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Count#(GearBoxInternalBankCnt))         axiWriteValidBankCntForLogicSideVec     <- replicateM(mkCount(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalWriteState))        axiWriteStatusForLogicSideRegVec        <- replicateM(mkReg(GearBoxInternalWriteStateHandleFirst));
    
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(AxiAwlen))                         axiAwLenCounterForHipSideRegVec         <- replicateM(mkRegU);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatAw))                    axiWriteStatusForHipSideAwQueueVec      <- replicateM(mkSizedFIFOF(valueOf(GEARBOX_INTERNAL_BANK_CNT)));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankIdx))           axiWriteBankIdxForHipSideRegVec         <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankRowIdx))        axiWriteBankRowIdxForHipSideRegVec      <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalWriteState))        axiWriteStatusForHipSideRegVec          <- replicateM(mkReg(GearBoxInternalWriteStateHandleFirst));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(Bool))                           axiWriteBramReadMetaForHipSideQueueVec  <- replicateM(mkSizedFIFOF(3));


    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(AxiMmBeatAr))                    axiInflightReadReqMetaQueueVec          <- replicateM(mkSizedFIFOF(16));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(AxiArlen))                         axiArLenCounterForHipSideRegVec         <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankIdx))           axiReadBankIdxForHipSideRegVec          <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankRowIdx))        axiReadBankRowIdxForHipSideRegVec       <- replicateM(mkReg(0));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Count#(GearBoxInternalBankCnt))         axiReadValidBankCntForHipSideVec        <- replicateM(mkCount(0));

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(Bool))                             isFirstBeatForLogicSideRegVec           <- replicateM(mkReg(True));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(AxiArlen))                         axiArLenCounterForLogicSideRegVec       <- replicateM(mkRegU);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Reg#(GearBoxInternalBankColIdx))        axiReadBankColIdxForLogicSideRegVec     <- replicateM(mkReg(0));
    
    


    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, 
        Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, 
            AutoInferBramQueuedOutput#(GearBoxInternalBramAddr, AxiMmBeatW#(AxiDataForLogic)))) storageForWrite <- replicateM(replicateM(mkAutoInferBramQueuedOutput(False, "")));

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT,  
        FIFOF#(AxiMmBeatR#(AxiDataForHip))) storageForRead  <- replicateM(mkSizedFIFOF(valueOf(GEARBOX_INTERNAL_BRAM_ROW_CNT)));
    
    
    for (Integer idx = 0; idx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); idx = idx + 1) begin
        rule handleLogicSideFirstWriteBeat if (axiWriteStatusForLogicSideRegVec[idx] == GearBoxInternalWriteStateHandleFirst &&
                                 axiWriteValidBankCntForLogicSideVec[idx] < fromInteger(valueOf(GEARBOX_INTERNAL_BANK_CNT)));

            let reqAw = axiPipeQueueForLogicVecAw[idx].first;
            axiPipeQueueForLogicVecAw[idx].deq;
            let reqW = axiPipeQueueForLogicVecW[idx].first;
            axiPipeQueueForLogicVecW[idx].deq;

            GearBoxInternalBankColIdx startAddrColIdx = truncate(reqAw.awaddr >> valueOf(TLog#(TDiv#(SizeOf#(AxiDataForLogic), BYTE_WIDTH))));
            GearBoxInternalBramAddr writeBramAddr = pack({axiWriteBankIdxForLogicSideRegVec[idx], 0});

            storageForWrite[idx][startAddrColIdx].write(writeBramAddr, reqW);

            immAssert(
                reqAw.awsize == pack(AxiSize32B) && reqAw.awburst == pack(AxiBurstIncr),
                "Axi write request awsize or awburst not supported, awsize must be AxiSize32B and awburst must be AxiBurstIncr",
                $format("reqAw=", fshow(reqAw))
            );

            if (reqAw.awlen != 0) begin
                axiWriteBankRowIdxForLogicSideRegVec[idx] <= startAddrColIdx == maxBound ? 1 : 0;
                axiWriteBankColIdxForLogicSideRegVec[idx] <= startAddrColIdx + 1;
                axiAwLenCounterForLogicSideRegVec[idx] <= reqAw.awlen - 1;
                axiWriteStatusForLogicSideRegVec[idx] <= GearBoxInternalWriteStateHandleMore;
                axiWriteReqMetaForLogicSideRegVec[idx] <= reqAw;
            end
            else begin
                axiWriteBankIdxForLogicSideRegVec[idx] <= axiWriteBankIdxForLogicSideRegVec[idx] + 1;
                axiPipeQueueForLogicVecB[idx].enq(AxiMmBeatB {
                    bid: unpack(pack(reqAw.awid)),
                    bresp: 0
                });
                axiWriteValidBankCntForLogicSideVec[idx].incr(1);
                axiWriteStatusForHipSideAwQueueVec[idx].enq(AxiMmBeatAw {
                    awid: reqAw.awid,
                    awaddr: reqAw.awaddr,
                    awlen: 0,
                    awsize: pack(AxiSize128B),
                    awburst: pack(AxiBurstIncr),
                    awlock: False, 
                    awqos: 0
                });
            end
        endrule

        rule handleLogicSideMoreWriteBeat if (axiWriteStatusForLogicSideRegVec[idx] == GearBoxInternalWriteStateHandleMore);
            let reqW = axiPipeQueueForLogicVecW[idx].first;
            axiPipeQueueForLogicVecW[idx].deq;

            let reqAw = axiWriteReqMetaForLogicSideRegVec[idx];

            GearBoxInternalBramAddr writeBramAddr = pack({axiWriteBankIdxForLogicSideRegVec[idx], axiWriteBankRowIdxForLogicSideRegVec[idx]});
            storageForWrite[idx][axiWriteBankColIdxForLogicSideRegVec[idx]].write(writeBramAddr, reqW);

            axiWriteBankColIdxForLogicSideRegVec[idx] <= axiWriteBankColIdxForLogicSideRegVec[idx] + 1;
            if (axiWriteBankColIdxForLogicSideRegVec[idx] == maxBound) begin
                axiWriteBankRowIdxForLogicSideRegVec[idx] <= axiWriteBankRowIdxForLogicSideRegVec[idx] + 1;
            end

            
            if (axiAwLenCounterForLogicSideRegVec[idx] == 0) begin
                axiWriteStatusForLogicSideRegVec[idx] <= GearBoxInternalWriteStateHandleFirst;
                axiWriteBankIdxForLogicSideRegVec[idx] <= axiWriteBankIdxForLogicSideRegVec[idx] + 1;
                axiPipeQueueForLogicVecB[idx].enq(AxiMmBeatB {
                    bid: unpack(pack(reqAw.awid)),
                    bresp: 0
                });
                axiWriteValidBankCntForLogicSideVec[idx].incr(1);

                axiWriteStatusForHipSideAwQueueVec[idx].enq(AxiMmBeatAw {
                    awid    : reqAw.awid,
                    awaddr  : reqAw.awaddr,
                    awlen   : reqAw.awlen >> valueOf(TLog#(NUMERIC_TYPE_FOUR)),
                    awsize  : pack(AxiSize128B),
                    awburst : pack(AxiBurstIncr),
                    awlock  : False, 
                    awqos   : 0
                });
            end
            axiAwLenCounterForLogicSideRegVec[idx] <= axiAwLenCounterForLogicSideRegVec[idx] - 1;
        endrule

        rule forwardWriteFromLogicSideToHipSideFirstBeat if (axiWriteStatusForHipSideRegVec[idx] == GearBoxInternalWriteStateHandleFirst);
            let reqAw = axiWriteStatusForHipSideAwQueueVec[idx].first;
            axiWriteStatusForHipSideAwQueueVec[idx].deq;

            axiPipeQueueForHipVecAw[idx].enq(reqAw);

            GearBoxInternalBramAddr bramAddr = pack({axiWriteBankIdxForHipSideRegVec[idx], 0});
            for (Integer colIdx = 0; colIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); colIdx = colIdx + 1) begin
                storageForWrite[idx][colIdx].putReadReq(bramAddr);
            end

            if (reqAw.awlen != 0) begin
                axiWriteStatusForHipSideRegVec[idx] <= GearBoxInternalWriteStateHandleMore;
                axiWriteBankRowIdxForHipSideRegVec[idx] <= 1;
                axiAwLenCounterForHipSideRegVec[idx] <= reqAw.awlen - 1;
                Bool isLastBeat = False;
                axiWriteBramReadMetaForHipSideQueueVec[idx].enq(isLastBeat);
            end
            else begin
                axiWriteBankIdxForHipSideRegVec[idx] <= axiWriteBankIdxForHipSideRegVec[idx] + 1;
                Bool isLastBeat = True;
                axiWriteBramReadMetaForHipSideQueueVec[idx].enq(isLastBeat);
            end
        endrule

        rule forwardWriteFromLogicSideToHipSideMoreBeat if (axiWriteStatusForHipSideRegVec[idx] == GearBoxInternalWriteStateHandleMore);
            GearBoxInternalBramAddr bramAddr = pack({axiWriteBankIdxForHipSideRegVec[idx], axiWriteBankRowIdxForHipSideRegVec[idx]});
            for (Integer colIdx = 0; colIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); colIdx = colIdx + 1) begin
                storageForWrite[idx][colIdx].putReadReq(bramAddr);
            end
            axiWriteBankRowIdxForHipSideRegVec[idx] <= axiWriteBankRowIdxForHipSideRegVec[idx] + 1;
            axiAwLenCounterForHipSideRegVec[idx] <= axiAwLenCounterForHipSideRegVec[idx] - 1;

            if (axiAwLenCounterForHipSideRegVec[idx] != 0) begin
                Bool isLastBeat = False;
                axiWriteBramReadMetaForHipSideQueueVec[idx].enq(isLastBeat);
            end
            else begin
                axiWriteStatusForHipSideRegVec[idx] <= GearBoxInternalWriteStateHandleFirst;
                axiWriteBankIdxForHipSideRegVec[idx] <= axiWriteBankIdxForHipSideRegVec[idx] + 1;
                Bool isLastBeat = True;
                axiWriteBramReadMetaForHipSideQueueVec[idx].enq(isLastBeat);
            end
        endrule

        rule handleLogicToHipBramReadResp;
            Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, AxiDataForLogic) combinedDataTmpVec = newVector;
            Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, Bit#(TDiv#(SizeOf#(AxiDataForLogic), BYTE_WIDTH)))combinedStrbTmpVec = newVector;

            let isLast = axiWriteBramReadMetaForHipSideQueueVec[idx].first;
            axiWriteBramReadMetaForHipSideQueueVec[idx].deq;

            for (Integer colIdx = 0; colIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); colIdx = colIdx + 1) begin
                let chunk = storageForWrite[idx][colIdx].readRespPipeOut.first;
                storageForWrite[idx][colIdx].readRespPipeOut.deq;
                combinedDataTmpVec[colIdx] = chunk.wdata;
                combinedStrbTmpVec[colIdx] = chunk.wstrb;
            end

            axiPipeQueueForHipVecW[idx].enq(AxiMmBeatW {
                    wdata: pack(combinedDataTmpVec),
                    wstrb: pack(combinedStrbTmpVec),
                    wlast: isLast
                }
            );
        endrule

        rule discardWriteRespForHip;
            axiPipeQueueForHipVecB[idx].deq;
        endrule


        rule handleLogicSideReadReq;
            let reqIn = axiPipeQueueForLogicVecAr[idx].first;
            axiPipeQueueForLogicVecAr[idx].deq;

            immAssert(
                reqIn.arlen <= 15,
                "max burst size supported is 16 beat",
                $format("reqIn=", fshow(reqIn))
            );

            GearBoxInternalBankColIdx startAddrColIdx = truncate(reqIn.araddr >> valueOf(TLog#(TDiv#(SizeOf#(AxiDataForLogic), BYTE_WIDTH))));
            AxiArlen arlenTmp = zeroExtend(startAddrColIdx) + reqIn.arlen;
            AxiArlen arlen = arlenTmp >> valueOf(TLog#(GEARBOX_WIDTH_RATIO));

            let reqOut = AxiMmBeatAr {
                arid: reqIn.arid,
                araddr: reqIn.araddr,
                arlen: arlen,
                arsize: pack(AxiSize128B),
                arburst: pack(AxiBurstIncr),
                arlock: False,
                arqos: 0
            };

            axiPipeQueueForHipVecAr[idx].enq(reqOut);
            axiInflightReadReqMetaQueueVec[idx].enq(reqIn);
        endrule

        rule handleReadRespHipSide if (axiReadValidBankCntForHipSideVec[idx] < fromInteger(valueOf(GEARBOX_INTERNAL_BANK_CNT)));

            let respIn = axiPipeQueueForHipVecR[idx].first;
            axiPipeQueueForHipVecR[idx].deq;
            storageForRead[idx].enq(respIn);
            
            if (respIn.rlast) begin
                axiReadBankIdxForHipSideRegVec[idx] <= axiReadBankIdxForHipSideRegVec[idx] + 1;
                axiReadBankRowIdxForHipSideRegVec[idx] <= 0;
                axiReadValidBankCntForHipSideVec[idx].incr(1);
            end
            else begin
                axiReadBankRowIdxForHipSideRegVec[idx] <= axiReadBankRowIdxForHipSideRegVec[idx] + 1;
            end
            
        endrule

        rule handleAxiReadRespLogicSide;

            let rawReadReq = axiInflightReadReqMetaQueueVec[idx].first;
            Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, AxiDataForLogic) combinedDataTmpVec = unpack(pack(storageForRead[idx].first.rdata));

            if (isFirstBeatForLogicSideRegVec[idx]) begin

                Bool isLast = rawReadReq.arlen == 0;
                GearBoxInternalBankColIdx startAddrColIdx = truncate(rawReadReq.araddr >> valueOf(TLog#(TDiv#(SizeOf#(AxiDataForLogic), BYTE_WIDTH))));

                axiPipeQueueForLogicVecR[idx].enq(AxiMmBeatR {
                    rid: pack(rawReadReq.arid),
                    rdata: combinedDataTmpVec[startAddrColIdx],
                    rresp: 0,
                    rlast: isLast
                });

                axiReadBankColIdxForLogicSideRegVec[idx] <= startAddrColIdx + 1;
                isFirstBeatForLogicSideRegVec[idx] <= isLast ? True : False;

                if (isLast || startAddrColIdx == maxBound) begin
                    storageForRead[idx].deq;
                end

                if (isLast) begin
                    axiInflightReadReqMetaQueueVec[idx].deq;
                end

                axiArLenCounterForLogicSideRegVec[idx] <= rawReadReq.arlen - 1;
            end
            else begin
                Bool isLast = axiArLenCounterForLogicSideRegVec[idx] == 0;
                axiArLenCounterForLogicSideRegVec[idx] <= axiArLenCounterForLogicSideRegVec[idx] - 1;

                axiPipeQueueForLogicVecR[idx].enq(AxiMmBeatR {
                    rid: pack(rawReadReq.arid),
                    rdata: combinedDataTmpVec[axiReadBankColIdxForLogicSideRegVec[idx]],
                    rresp: 0,
                    rlast: isLast
                });

                if (isLast || axiReadBankColIdxForLogicSideRegVec[idx] == maxBound) begin
                    storageForRead[idx].deq;
                end

                if (isLast) begin
                    axiInflightReadReqMetaQueueVec[idx].deq;
                end

                axiReadBankColIdxForLogicSideRegVec[idx] <= axiReadBankColIdxForLogicSideRegVec[idx] + 1;

                if (isLast) begin
                    immAssert(
                        storageForRead[idx].first.rlast,
                        "rlast must also be True",
                        $format("")
                    );
                end
            end
        endrule
    end

    interface axiSlaveVec = axiSlaveVecInst;
    interface axiMasterVec = axiMasterVecInst;
endmodule
