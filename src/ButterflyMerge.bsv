import Vector :: *;
import ClientServer :: *;
import GetPut :: *;
import Connectable :: *;
import FIFOF :: *;
import PAClib :: *;

import FullyPipelinedUpdateBram :: *;
import BluerdmaConsts :: *;
import SdpBramWrapper :: *;
import PrimUtils :: *;

typedef 4 FourChannel;


typedef struct {
    tRowAddr rowAddr;
    tBankAddr bankAddr;
    tData data;
    tTag tag;
} ButterflyMergeReq#(type tRowAddr, type tBankAddr, type tData, type tTag) deriving(Bits, FShow);

typedef struct {
    tRowAddr rowAddr;
    tBankAddr bankAddr;
    tData data;
    tTag tag;
} ButterflyMergeResp#(type tRowAddr, type tBankAddr, type tData, type tTag) deriving(Bits, FShow);

typedef struct {
    tData data;
    tTag tag;
} ButterflyMergeRowContent#(type tData, type tTag) deriving(Bits, FShow);

typedef Server#(
    ButterflyMergeReq#(tRowAddr, tBankAddr, tData, tTag), 
    ButterflyMergeResp#(tRowAddr, tBankAddr, tData, tTag)
) ButterflyMergeServer#(type tRowAddr, type tBankAddr, type tData, type tTag);

interface FourChannelButterflyMerge#(type tRowAddr, type tBankAddr, type tData, type tTag, type tBramEntry);
    interface Vector#(FourChannel, ButterflyMergeServer#(tRowAddr, tBankAddr, tData, tTag)) mergeSrvs;
endinterface

module mkFourChannelButterflyMerge#(
        function Tuple2#(tTag, tData) updateLogic1(tTag oldTag, tData oldValue, tTag newTag, tData newValue),
        function Tuple2#(tTag, tData) updateLogic2(tTag oldTag, tData oldValue, tTag newTag, tData newValue)
    )(FourChannelButterflyMerge#(tRowAddr, tBankAddr, tData, tTag, tBramEntry)) provisos(
        Bits#(tRowAddr, szRowAddr),
        Bits#(tBankAddr, szBankAddr),
        Bits#(tData, szData),
        Bits#(tTag, szTag),
        Bits#(tBramEntry, szBramEntry),
        Eq#(tRowAddr),
        FShow#(tRowAddr),
        FShow#(tBramEntry),
        FShow#(Tuple2#(tRowAddr, tBramEntry)),
        FShow#(Tuple2#(tRowAddr, tBankAddr)),
        FShow#(FullyPipelinedUpdateBramUpdateResp#(tRowAddr, tBankAddr, tBramEntry)),
        PrimIndex#(tBankAddr, a__),
        Add#(b__, szRowAddr, ACX_BRAM72K_SDP_ADDR_WIDTH),
        Add#(c__, szBramEntry, BITS_COUNT_72K),
        Add#(d__, TAdd#(szTag, szData), szBramEntry)
    );
    
    Vector#(FourChannel, Vector#(2, Integer)) firstStageTwistTable = newVector;
    firstStageTwistTable[0][0] = 0;
    firstStageTwistTable[0][1] = 1;
    firstStageTwistTable[1][0] = 1;
    firstStageTwistTable[1][1] = 0;
    firstStageTwistTable[2][0] = 2;
    firstStageTwistTable[2][1] = 3;
    firstStageTwistTable[3][0] = 3;
    firstStageTwistTable[3][1] = 2;

    Vector#(FourChannel, Vector#(2, Integer)) secondStageTwistTable = newVector;
    secondStageTwistTable[0][0] = 0;
    secondStageTwistTable[0][1] = 2;
    secondStageTwistTable[1][0] = 1;
    secondStageTwistTable[1][1] = 3;
    secondStageTwistTable[2][0] = 2;
    secondStageTwistTable[2][1] = 0;
    secondStageTwistTable[3][0] = 3;
    secondStageTwistTable[3][1] = 1;

    function Tuple2#(tTag, tData) splitTagAndDataFromRawStorageContent(tBramEntry rawData);
        return unpack(truncate(pack(rawData)));
    endfunction

    function tBramEntry mergeTagAndDataFromRawStorageContent(tTag tag, tData value);
        return unpack(zeroExtend(pack(tuple2(tag, value))));
    endfunction

    function tBramEntry bramUpdateFunctionAdapter(Integer stageIdx, tBramEntry oldRawData, tBramEntry newRawData);
        let {oldTag, oldValue} = splitTagAndDataFromRawStorageContent(oldRawData);
        let {newTag, newValue} = splitTagAndDataFromRawStorageContent(newRawData);

        Tuple2#(tTag, tData) updatedEntry;
        if (stageIdx == 0) begin
            updatedEntry = updateLogic1(oldTag, oldValue, newTag, newValue);
        end
        else begin
            updatedEntry = updateLogic2(oldTag, oldValue, newTag, newValue);
        end

        let {updatedTag, updatedValue} = updatedEntry;
        return mergeTagAndDataFromRawStorageContent(updatedTag, updatedValue);
    endfunction



    Vector#(FourChannel, FullyPipelinedUpdateBram2#(tRowAddr, tBankAddr, tBramEntry)) firstStageBramVec <- replicateM(mkFullyPipelinedUpdateBram2(False, bramUpdateFunctionAdapter(0)));
    Vector#(FourChannel, FullyPipelinedUpdateBram2#(tRowAddr, tBankAddr, tBramEntry)) secondStageBramVec <- replicateM(mkFullyPipelinedUpdateBram2(False, bramUpdateFunctionAdapter(1)));


    Vector#(FourChannel, FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tRowAddr, tBankAddr, tBramEntry))) firstStageSelfChannelInputQueueVec <- replicateM(mkFIFOF);
    Vector#(FourChannel, FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tRowAddr, tBankAddr, tBramEntry))) firstStageOtherChannelInputQueueVec <- replicateM(mkFIFOF);

    Vector#(FourChannel, FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tRowAddr, tBankAddr, tBramEntry))) secondStageSelfChannelInputQueueVec <- replicateM(mkFIFOF);
    Vector#(FourChannel, FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tRowAddr, tBankAddr, tBramEntry))) secondStageOtherChannelInputQueueVec <- replicateM(mkFIFOF);


    // Vector#(FourChannel, FIFOF#(Tuple2#(tRowAddr, tBankAddr))) firstStageUpdateInflightReqMetaQueueVec <- replicateM(mkSizedFIFOF(5));
    // Vector#(FourChannel, FIFOF#(Tuple2#(tRowAddr, tBankAddr))) secondStageUpdateInflightReqMetaQueueVec <- replicateM(mkSizedFIFOF(5));

    Vector#(FourChannel, FIFOF#(ButterflyMergeResp#(tRowAddr, tBankAddr, tData, tTag))) outputFifoVec <- replicateM(mkFIFOF);
    
    rule debugRule;
        for (Integer idx = 0; idx < valueOf(FourChannel); idx = idx + 1) begin
            if (!firstStageSelfChannelInputQueueVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: firstStageSelfChannelInputQueueVec[%0d]", idx);
            if (!firstStageOtherChannelInputQueueVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: firstStageOtherChannelInputQueueVec[%0d]", idx);
            if (!secondStageSelfChannelInputQueueVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: secondStageSelfChannelInputQueueVec[%0d]", idx);
            if (!secondStageOtherChannelInputQueueVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: secondStageOtherChannelInputQueueVec[%0d]", idx);
            // if (!firstStageUpdateInflightReqMetaQueueVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: firstStageUpdateInflightReqMetaQueueVec[%0d]", idx);
            // if (!secondStageUpdateInflightReqMetaQueueVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: secondStageUpdateInflightReqMetaQueueVec[%0d]", idx);
            if (!outputFifoVec[idx].notFull) $display("time=%0t, ", $time, "FullQueue: outputFifoVec[%d]", idx);
        end
    endrule


    // Connect stage one input buffer to BRAM.
    for (Integer idx = 0; idx < valueOf(FourChannel); idx = idx + 1) begin
        // give other channel higher priority
        let firstStageInputArbiter <- mkFixPriorityTwoInputArbiterNoOutputBufferPipeOut(
            toPipeOut(firstStageOtherChannelInputQueueVec[idx]),
            toPipeOut(firstStageSelfChannelInputQueueVec[idx])
        );
        mkConnection(toGet(firstStageInputArbiter), firstStageBramVec[idx].updateSrv.request);
    end

    // Connect first stage output to second stage input buffer.
    for (Integer idx = 0; idx < valueOf(FourChannel); idx = idx + 1) begin
        let twistTableEntry = secondStageTwistTable[idx];
        let selfChannelIdx = twistTableEntry[0];
        let otherChannelIdx = twistTableEntry[1];
        rule doFirstStageToSecondStageReq;
            let firstStageUpdateResult <- firstStageBramVec[idx].updateSrv.response.get;
            // let {rowAddr, bankAddr} = firstStageUpdateInflightReqMetaQueueVec[idx].first;
            // firstStageUpdateInflightReqMetaQueueVec[idx].deq;


            let bramReq1 = FullyPipelinedUpdateBramUpdateReq {
                generateResp: True,
                address: firstStageUpdateResult.address,
                bankAddress: firstStageUpdateResult.bankAddress,
                data: firstStageUpdateResult.data
            };

            // req1 and req2 only different in generate resp or not.
            let bramReq2 = bramReq1;
            bramReq2.generateResp = False;

            secondStageSelfChannelInputQueueVec[selfChannelIdx].enq(bramReq1);
            secondStageOtherChannelInputQueueVec[otherChannelIdx].enq(bramReq2);

            // secondStageUpdateInflightReqMetaQueueVec[selfChannelIdx].enq(tuple2(rowAddr, bankAddr));

            $display(
                "time=%0t, ", $time,
                toGreen("doFirstStageToSecondStageReq[%0d], "), idx,
                "firstStageUpdateResult=", fshow(firstStageUpdateResult)
            );
        endrule
    end


    // Connect stage two input buffer to BRAM.
    for (Integer idx = 0; idx < valueOf(FourChannel); idx = idx + 1) begin
        // give other channel higher priority
        let secondStageInputArbiter <- mkFixPriorityTwoInputArbiterNoOutputBufferPipeOut(
            toPipeOut(secondStageOtherChannelInputQueueVec[idx]),
            toPipeOut(secondStageSelfChannelInputQueueVec[idx])
        );
        mkConnection(toGet(secondStageInputArbiter), secondStageBramVec[idx].updateSrv.request);
    end

    // Connect second stage output to module final output
    for (Integer idx = 0; idx < valueOf(FourChannel); idx = idx + 1) begin
        rule moveSecondStageOutputToModuleFinalOutput;
            let secondStageUpdateResult <- secondStageBramVec[idx].updateSrv.response.get;
            let {tag, data} = splitTagAndDataFromRawStorageContent(secondStageUpdateResult.data);
            // let {rowAddr, bankAddr} = secondStageUpdateInflightReqMetaQueueVec[idx].first;
            // secondStageUpdateInflightReqMetaQueueVec[idx].deq;

            outputFifoVec[idx].enq(ButterflyMergeResp{
                rowAddr: secondStageUpdateResult.address,
                bankAddr: secondStageUpdateResult.bankAddress,
                data: data,
                tag: tag
            });
        endrule
    end

    
    function ButterflyMergeServer#(tRowAddr, tBankAddr, tData, tTag) genButterflyMergeServerIfc(Integer chIdx1, Integer chIdx2);

        return (interface Server;
            interface Put request;
                method Action put(ButterflyMergeReq#(tRowAddr, tBankAddr, tData, tTag) req);
                    let bramReq1 = FullyPipelinedUpdateBramUpdateReq {
                        generateResp: True,
                        address:req.rowAddr,
                        bankAddress: req.bankAddr,
                        data: mergeTagAndDataFromRawStorageContent(req.tag, req.data)
                    };

                    // req1 and req2 only different in generate resp or not.
                    let bramReq2 = bramReq1;
                    bramReq2.generateResp = False;

                    firstStageSelfChannelInputQueueVec[chIdx1].enq(bramReq1);
                    firstStageOtherChannelInputQueueVec[chIdx2].enq(bramReq2);

                    // firstStageUpdateInflightReqMetaQueueVec[chIdx1].enq(tuple2(req.rowAddr, req.bankAddr));
                endmethod
            endinterface

            interface response = toGet(outputFifoVec[chIdx1]);
        endinterface);
    endfunction

    Vector#(FourChannel, ButterflyMergeServer#(tRowAddr, tBankAddr, tData, tTag)) ifc;
    for (Integer idx = 0; idx < valueOf(FourChannel); idx = idx + 1) begin
        let twistTableEntry = firstStageTwistTable[idx];
        ifc[idx] = genButterflyMergeServerIfc(twistTableEntry[0], twistTableEntry[1]);
    end
    
    interface mergeSrvs = ifc;
endmodule

