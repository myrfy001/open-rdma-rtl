import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import ConfigReg :: * ;

import PrimUtils :: *;
import DataTypes :: *;

import RdmaHeaders :: *;


import ConnectableF :: *;

typedef 4 CPSN_CHECKER_CHANNEL_NUM;
typedef Bit#(TLog#(CPSN_CHECKER_CHANNEL_NUM)) CpsnCheckerChannelIdx;

// typedef struct {
//     PSN psn;
//     QPN qpn;
//     Bool needAck;
// } PsnContinousCheckerReq deriving(Bits, FShow);

// typedef struct {
//     QPN qpn;
//     PSN cpsn;
//     Maybe#(BitmapPerBank) evictedBitmapMaybe;
// } PsnContinousCheckerResp deriving(Bits, FShow);

// typedef struct {
//     BitmapBankTag   tag;
//     BitmapBankIdx   bankIdx;
//     BitmapBitIdx    bitIdx;
// } PsnAsBitmapIndex deriving(Bits, FShow);

// interface PsnContinousCheckerAndAckAutoGen;
//     interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVec;
//     interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(PsnContinousCheckerResp)) respPipeOutVec;
// endinterface


// (* synthesize *)
// module mkPsnContinousCheckerAndAckAutoGen(PsnContinousCheckerAndAckAutoGen);
//     Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVecInst = newVector;
//     Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(PsnContinousCheckerResp)) respPipeOutVecInst = newVector;
//     Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);
//     Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerResp)) respPipeOutQueueVec <- replicateM(mkFIFOF);







//     for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
//         reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
//         respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
//     end
//     interface reqPipeInVec = reqPipeInVecInst;
//     interface respPipeOutVec = respPipeOutVecInst;
// endmodule






typedef TSub#(PSN_WIDTH, TLog#(OOO_WINDOW_STRIDE)) PSN_MERGE_WINDOW_BOUNDARY_WIDTH;
typedef Bit#(PSN_MERGE_WINDOW_BOUNDARY_WIDTH) PsnMergeWindowBoundary;
typedef Bit#(TLog#(OOO_WINDOW_SIZE)) PsnMergeWindowBitOffset;


typedef struct {
    PSN psn;
    QPN qpn;
} FourChannelPsnBitmapPreMergeReq deriving(Bits, FShow);

typedef struct {
    QPN qpn;
    PSN psn;  // for debug use
    PsnMergeWindowBoundary maxLeftBoundary;
    OooWindowBitmap  bitmap;
} FourChannelPsnBitmapPreMergeResp deriving(Bits, FShow);

typedef struct {
    PSN psn;
    QPN qpn;
    PsnMergeWindowBoundary maxLeftBoundary;
} FourChannelPsnBitmapPreMergeGetMaxPsnInternalState deriving(Bits, FShow);

typedef struct {
    QPN qpn;
    PSN psn;  // for debug use
    PsnMergeWindowBoundary maxLeftBoundary;
    Bool isOverflow;
    PsnMergeWindowBitOffset shiftOffset;
} FourChannelPsnBitmapPreMergeOnehotGenInternalState deriving(Bits, FShow);

interface FourChannelPsnBitmapPreMerge;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(FourChannelPsnBitmapPreMergeReq)) reqPipeInVec;
    interface PipeOut#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeResp))) respPipeOut;
endinterface

typedef TAdd#(1, CPSN_CHECKER_CHANNEL_NUM) GET_MAX_PSN_PIPELINE_STAGE_CNT;

module mkFourChannelPsnBitmapPreMerge(FourChannelPsnBitmapPreMerge);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(FourChannelPsnBitmapPreMergeReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(FourChannelPsnBitmapPreMergeReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);
    FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeResp))) respPipeOutQueue <- mkFIFOF;


    // Pipeline Queues 
    FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx)))) bitonicSortQpnInputPipelineQueue <- mkFIFOF;
    FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx)))) bitonicSortQpnOutputPipelineQueue <- mkSizedFIFOF(5);
    FIFOF#(Bit#(3)) channelQpnEqualMapPipelineQueue <- mkFIFOF;

    Vector#(GET_MAX_PSN_PIPELINE_STAGE_CNT, FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState)))) maxPsnBroadcastPipelineQueueVec <- replicateM(mkLFIFOF);
    FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState))) reorderedFourChannelReqWithMaxPsnPipelineQueue <- mkFIFOF;
    FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeOnehotGenInternalState))) onehotGenMetaCalcPipelineQueue <- mkLFIFOF;
    FIFOF#(Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeResp))) onehotGenToOnehotMergePipelineQueue <- mkLFIFOF;

    Reg#(Bool) evenOddCounterReg <- mkReg(False);

    function Bool canUpadteCh2ToCh1Boundary(
            Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState) ch1InfoMaybe,
            Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState) ch2InfoMaybe
        );
        
        let ch1Info = fromMaybe(?, ch1InfoMaybe);
        let ch2Info = fromMaybe(?, ch2InfoMaybe);

        PsnMergeWindowBoundary leftBoundCh1 = truncateLSB(ch1Info.psn);
        PsnMergeWindowBoundary leftBoundCh2 = truncateLSB(ch2Info.psn);

        let canUpdata = isValid(ch1InfoMaybe) && isValid(ch2InfoMaybe) && (ch1Info.qpn == ch2Info.qpn) && (msb(leftBoundCh1 - leftBoundCh2) == 0) ;
        return canUpdata;
    endfunction

    function Tuple2#(Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx)), Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx))) bitonicAscSwap(
            Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx)) inMaybe1,
            Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx)) inMaybe2
        );
        // we treat maybe as +inf, so after sort, it will be at the end of the vector
        if (inMaybe1 matches tagged Valid .in1 &&& inMaybe2 matches tagged Valid .in2) begin
            let {val1, tag1} = in1;
            let {val2, tag2} = in2;
            if (in1 <= in2) begin
                return tuple2(inMaybe1, inMaybe2);
            end
            else begin
                return tuple2(inMaybe2, inMaybe1);
            end
        end
        else begin
            // in this branch, at most one channel is Valid, so only move the valid one to first and another to last;
            // if both channel is Invalid, swap will also happen, but that doesn't matter.
            if (isValid(inMaybe1)) begin
                return tuple2(inMaybe1, inMaybe2);
            end
            else begin
                return tuple2(inMaybe2, inMaybe1);
            end
        end
    endfunction

    rule handleInputReqEveryTwoBeta;
        evenOddCounterReg <= !evenOddCounterReg;

        if (evenOddCounterReg) begin
            Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState)) outVec = newVector;
            Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(Tuple2#(QPN, CpsnCheckerChannelIdx))) bitonicSortQpnPipelineEntryOutVec = newVector;

            for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
                if (reqPipeInQueueVec[idx].notEmpty) begin
                    reqPipeInQueueVec[idx].deq;

                    let psn = reqPipeInQueueVec[idx].first.psn;
                    let qpn = reqPipeInQueueVec[idx].first.qpn;

                    let outItem = FourChannelPsnBitmapPreMergeGetMaxPsnInternalState{
                        psn:                psn,
                        qpn:                qpn,
                        maxLeftBoundary:    truncateLSB(psn)
                    };
                    outVec[idx] = tagged Valid outItem;

                    bitonicSortQpnPipelineEntryOutVec[idx] = tagged Valid tuple2(qpn, fromInteger(idx));
                end
                else begin
                    outVec[idx] = tagged Invalid;
                    bitonicSortQpnPipelineEntryOutVec[idx] = tagged Invalid;
                end
            end
            maxPsnBroadcastPipelineQueueVec[0].enq(outVec);
            bitonicSortQpnInputPipelineQueue.enq(bitonicSortQpnPipelineEntryOutVec);
        end
    endrule

    // generate four stage compare, and broadcast max PSN to each channel
    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        rule broadcastChannelPsn;
            let pipelineEntryIn = maxPsnBroadcastPipelineQueueVec[idx].first;
            maxPsnBroadcastPipelineQueueVec[idx].deq;

            Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState)) pipelineEntryOut = pipelineEntryIn;
            
            Vector#(CPSN_CHECKER_CHANNEL_NUM, FourChannelPsnBitmapPreMergeGetMaxPsnInternalState) chInfoVec = newVector;

            for (Integer idxInner = 0; idxInner < valueOf(CPSN_CHECKER_CHANNEL_NUM); idxInner = idxInner + 1) begin
                chInfoVec[idxInner] = fromMaybe(?, pipelineEntryIn[idxInner]);
            end

            for (Integer idxInner = 0; idxInner < valueOf(CPSN_CHECKER_CHANNEL_NUM); idxInner = idxInner + 1) begin

                if (idx != idxInner) begin
                    if (canUpadteCh2ToCh1Boundary(pipelineEntryIn[idx], pipelineEntryIn[idxInner])) begin
                        chInfoVec[idxInner].maxLeftBoundary = chInfoVec[idx].maxLeftBoundary;
                        pipelineEntryOut[idxInner] = tagged Valid chInfoVec[idxInner];
                    end
                end
            end

            maxPsnBroadcastPipelineQueueVec[idx+1].enq(pipelineEntryOut);
        endrule
    end

    rule bitonicSortQpn;

        let pipelineEntryIn = bitonicSortQpnInputPipelineQueue.first;
        bitonicSortQpnInputPipelineQueue.deq;
        // first swap
        let {v00, v01} = bitonicAscSwap(pipelineEntryIn[0], pipelineEntryIn[1]);
        let {v03, v02} = bitonicAscSwap(pipelineEntryIn[2], pipelineEntryIn[3]);
        // second swap
        let {v10, v12} = bitonicAscSwap(v00, v02);
        let {v11, v13} = bitonicAscSwap(v01, v03);
        // third swap
        let {v20, v21} = bitonicAscSwap(v10, v11);
        let {v22, v23} = bitonicAscSwap(v12, v13);

        bitonicSortQpnOutputPipelineQueue.enq(vec(v20, v21, v22, v23));
    endrule

    rule reorderChannel;
        let sortedInfo = bitonicSortQpnOutputPipelineQueue.first;
        bitonicSortQpnOutputPipelineQueue.deq;

        let pipelineEntryIn = maxPsnBroadcastPipelineQueueVec[valueOf(GET_MAX_PSN_PIPELINE_STAGE_CNT)-1].first;
        maxPsnBroadcastPipelineQueueVec[valueOf(GET_MAX_PSN_PIPELINE_STAGE_CNT)-1].deq;

        Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeGetMaxPsnInternalState)) outVec = newVector;

        for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
            if (sortedInfo[idx] matches tagged Valid .sortInfo) begin
                let chIdx = tpl_2(sortInfo);
                outVec[idx] = pipelineEntryIn[chIdx];
            end
            else begin
                outVec[idx] = tagged Invalid;
            end
        end
        reorderedFourChannelReqWithMaxPsnPipelineQueue.enq(outVec);
    endrule

    // generate one-hot bitmap for each channel
    rule preCalcOneHotBitmapMetaForEachChannel;
        let pipelineEntryIn = reorderedFourChannelReqWithMaxPsnPipelineQueue.first;
        reorderedFourChannelReqWithMaxPsnPipelineQueue.deq;

        Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeOnehotGenInternalState)) outputVec = newVector;
        

        for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
            let channelInfoMaybe = pipelineEntryIn[idx];
            if (channelInfoMaybe matches tagged Valid .channelInfo) begin
                
                // extend lsb and fill lsb with 1
                PSN boundaryPSN = unpack({pack(channelInfo.maxLeftBoundary), -1});
                let shiftDelta = boundaryPSN - channelInfo.psn;

                Bool isOverflow = (shiftDelta >= fromInteger(valueOf(OOO_WINDOW_SIZE)));

                let outInfo = FourChannelPsnBitmapPreMergeOnehotGenInternalState {
                    qpn: channelInfo.qpn,
                    psn: channelInfo.psn,
                    maxLeftBoundary: channelInfo.maxLeftBoundary,
                    isOverflow: isOverflow,
                    shiftOffset:truncate(shiftDelta)
                };
                outputVec[idx] = tagged Valid outInfo;
            end
            else begin
                outputVec[idx] = tagged Invalid;
            end
        end
        onehotGenMetaCalcPipelineQueue.enq(outputVec);
    endrule

    rule genOneHotBitmapForEachChannel;
        let pipelineEntryIn = onehotGenMetaCalcPipelineQueue.first;
        onehotGenMetaCalcPipelineQueue.deq;

        Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeResp)) outputVec = newVector;

        Bool needPrintDebugInfo = False;
        for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
            let channelInfoMaybe = pipelineEntryIn[idx];
            if (channelInfoMaybe matches tagged Valid .channelInfo) begin
                OooWindowBitmap  bitmap = channelInfo.isOverflow ? 0 : swapEndianBit(1 << channelInfo.shiftOffset);

                let outInfo = FourChannelPsnBitmapPreMergeResp {
                    qpn: channelInfo.qpn,
                    psn: channelInfo.psn,
                    maxLeftBoundary: channelInfo.maxLeftBoundary,
                    bitmap: bitmap
                };
                outputVec[idx] = tagged Valid outInfo;
                if (getIndexQP(channelInfo.qpn) == 4) begin
                    needPrintDebugInfo = True;
                end
            end
            else begin
                outputVec[idx] = tagged Invalid;
            end
        end

        onehotGenToOnehotMergePipelineQueue.enq(outputVec);


        let channelEqual01 = False;
        let channelEqual12 = False;
        let channelEqual23 = False;
        if (pipelineEntryIn[0] matches tagged Valid .chA &&& pipelineEntryIn[1] matches tagged Valid .chB &&& chA.qpn == chB.qpn) begin
            channelEqual01 = True;
        end
        if (pipelineEntryIn[1] matches tagged Valid .chA &&& pipelineEntryIn[2] matches tagged Valid .chB &&& chA.qpn == chB.qpn) begin
            channelEqual12 = True;
        end
        if (pipelineEntryIn[2] matches tagged Valid .chA &&& pipelineEntryIn[3] matches tagged Valid .chB &&& chA.qpn == chB.qpn) begin
            channelEqual23 = True;
        end

        let channelQpnEqualMap = {pack(channelEqual01), pack(channelEqual12), pack(channelEqual23)};
        channelQpnEqualMapPipelineQueue.enq(channelQpnEqualMap);
        // if (needPrintDebugInfo) begin
        //     $display("time=%0t", $time, ", mkFourChannelPsnBitmapPreMerge genOneHotBitmapForEachChannel", 
        //         ", pipelineEntryIn=", fshow(pipelineEntryIn),
        //         ", outputVec=", fshow(outputVec),
        //         ", channelQpnEqualMap=", fshow(channelQpnEqualMap)
        //     );
        // end
    endrule

    rule preMergeChannels;
        let oneHotBitmapVec = onehotGenToOnehotMergePipelineQueue.first;
        onehotGenToOnehotMergePipelineQueue.deq;

        let equalBitMap = channelQpnEqualMapPipelineQueue.first;
        channelQpnEqualMapPipelineQueue.deq;

        Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeResp)) outVec = newVector;

        case (equalBitMap)
            3'b000: begin
                outVec[0] = oneHotBitmapVec[0];
                outVec[1] = oneHotBitmapVec[1];
                outVec[2] = oneHotBitmapVec[2];
                outVec[3] = oneHotBitmapVec[3];
            end
            3'b100: begin
                let c0 = fromMaybe(?, oneHotBitmapVec[0]);
                let c1 = fromMaybe(?, oneHotBitmapVec[1]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && c0.qpn == c1.qpn && c0.maxLeftBoundary == c1.maxLeftBoundary,
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c0=", fshow(c0), ", c1=", fshow(c1))
                );

                outVec[0] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c0.qpn,
                    psn: c0.psn,
                    maxLeftBoundary: c0.maxLeftBoundary,
                    bitmap: c0.bitmap | c1.bitmap
                };

                outVec[1] = oneHotBitmapVec[2];
                outVec[2] = oneHotBitmapVec[3];
                outVec[3] = tagged Invalid;
            end
            3'b110: begin
                let c0 = fromMaybe(?, oneHotBitmapVec[0]);
                let c1 = fromMaybe(?, oneHotBitmapVec[1]);
                let c2 = fromMaybe(?, oneHotBitmapVec[2]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && isValid(oneHotBitmapVec[2]) &&
                    c0.qpn == c1.qpn && c1.qpn == c2.qpn && c0.maxLeftBoundary == c1.maxLeftBoundary && c1.maxLeftBoundary == c2.maxLeftBoundary, 
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c0=", fshow(c0), ", c1=", fshow(c1), ", c2=", fshow(c2))
                );

                outVec[0] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c0.qpn,
                    psn: c0.psn,
                    maxLeftBoundary: c0.maxLeftBoundary,
                    bitmap: c0.bitmap | c1.bitmap | c2.bitmap
                };

                outVec[1] = oneHotBitmapVec[3];
                outVec[2] = tagged Invalid;
                outVec[3] = tagged Invalid;
            end
            3'b111: begin
                let c0 = fromMaybe(?, oneHotBitmapVec[0]);
                let c1 = fromMaybe(?, oneHotBitmapVec[1]);
                let c2 = fromMaybe(?, oneHotBitmapVec[2]);
                let c3 = fromMaybe(?, oneHotBitmapVec[3]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && isValid(oneHotBitmapVec[2]) && isValid(oneHotBitmapVec[3]) &&
                    c0.qpn == c1.qpn && c1.qpn == c2.qpn && c2.qpn == c3.qpn &&
                    c0.maxLeftBoundary == c1.maxLeftBoundary && c1.maxLeftBoundary == c2.maxLeftBoundary && c2.maxLeftBoundary == c3.maxLeftBoundary, 
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c0=", fshow(c0), ", c1=", fshow(c1), ", c2=", fshow(c2), ", c3=", fshow(c3))
                );

                outVec[0] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c0.qpn,
                    psn: c0.psn,
                    maxLeftBoundary: c0.maxLeftBoundary,
                    bitmap: c0.bitmap | c1.bitmap | c2.bitmap | c3.bitmap
                };

                outVec[1] = tagged Invalid;
                outVec[2] = tagged Invalid;
                outVec[3] = tagged Invalid;
            end
            3'b101: begin
                let c0 = fromMaybe(?, oneHotBitmapVec[0]);
                let c1 = fromMaybe(?, oneHotBitmapVec[1]);
                let c2 = fromMaybe(?, oneHotBitmapVec[2]);
                let c3 = fromMaybe(?, oneHotBitmapVec[3]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && c0.qpn == c1.qpn && c0.maxLeftBoundary == c1.maxLeftBoundary,
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c0=", fshow(c0), ", c1=", fshow(c1))
                );
                immAssert(
                    isValid(oneHotBitmapVec[2]) && isValid(oneHotBitmapVec[3]) && c2.qpn == c3.qpn && c2.maxLeftBoundary == c3.maxLeftBoundary,
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c2=", fshow(c2), ", c3=", fshow(c3))
                );

                outVec[0] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c0.qpn,
                    psn: c0.psn,
                    maxLeftBoundary: c0.maxLeftBoundary,
                    bitmap: c0.bitmap | c1.bitmap 
                };

                outVec[1] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c2.qpn,
                    psn: c2.psn,
                    maxLeftBoundary: c2.maxLeftBoundary,
                    bitmap:  c2.bitmap | c3.bitmap
                };
                outVec[2] = tagged Invalid;
                outVec[3] = tagged Invalid;
            end
            3'b011: begin
                let c0 = fromMaybe(?, oneHotBitmapVec[0]);
                let c1 = fromMaybe(?, oneHotBitmapVec[1]);
                let c2 = fromMaybe(?, oneHotBitmapVec[2]);
                let c3 = fromMaybe(?, oneHotBitmapVec[3]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && isValid(oneHotBitmapVec[2]) && isValid(oneHotBitmapVec[3]) &&
                    c1.qpn == c2.qpn && c2.qpn == c3.qpn && c1.maxLeftBoundary == c2.maxLeftBoundary && c2.maxLeftBoundary == c3.maxLeftBoundary, 
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c1=", fshow(c1), ", c2=", fshow(c2), ", c3=", fshow(c3))
                );

                outVec[0] = oneHotBitmapVec[0];

                outVec[1] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c1.qpn,
                    psn: c1.psn,
                    maxLeftBoundary: c1.maxLeftBoundary,
                    bitmap:  c1.bitmap | c2.bitmap | c3.bitmap
                };
                outVec[2] = tagged Invalid;
                outVec[3] = tagged Invalid;
            end
            3'b010: begin
                let c1 = fromMaybe(?, oneHotBitmapVec[1]);
                let c2 = fromMaybe(?, oneHotBitmapVec[2]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && isValid(oneHotBitmapVec[2]) && c1.qpn == c2.qpn && c1.maxLeftBoundary == c2.maxLeftBoundary,
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c1=", fshow(c1), ", c2=", fshow(c2))
                );

                outVec[0] = oneHotBitmapVec[0];
                outVec[1] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c1.qpn,
                    psn: c1.psn,
                    maxLeftBoundary: c1.maxLeftBoundary,
                    bitmap: c1.bitmap | c2.bitmap
                };
                outVec[2] = oneHotBitmapVec[3];
                outVec[3] = tagged Invalid;
            end
            3'b001: begin
                let c2 = fromMaybe(?, oneHotBitmapVec[2]);
                let c3 = fromMaybe(?, oneHotBitmapVec[3]);

                immAssert(
                    isValid(oneHotBitmapVec[0]) && isValid(oneHotBitmapVec[1]) && isValid(oneHotBitmapVec[2]) && isValid(oneHotBitmapVec[3]) && 
                    c2.qpn == c3.qpn && c2.maxLeftBoundary == c3.maxLeftBoundary,
                    "QPN and maxLeftBoundary must be equal to do merge",
                    $format("c2=", fshow(c2), ", c3=", fshow(c3))
                );

                outVec[0] = oneHotBitmapVec[0];
                outVec[1] = oneHotBitmapVec[1];
                outVec[2] = tagged Valid FourChannelPsnBitmapPreMergeResp{
                    qpn: c2.qpn,
                    psn: c2.psn,
                    maxLeftBoundary: c2.maxLeftBoundary,
                    bitmap: c2.bitmap | c3.bitmap
                };
                outVec[3] = tagged Invalid;
            end

        endcase
        respPipeOutQueue.enq(outVec);
    endrule



    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
    end
    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOut = toPipeOut(respPipeOutQueue);
endmodule

// Must be 2^N
typedef 128 OOO_WINDOW_SIZE;
typedef 16  OOO_WINDOW_STRIDE;  
typedef Bit#(OOO_WINDOW_SIZE) OooWindowBitmap;

typedef struct {
    tData       data;
    tBoundary   leftBound;
} BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr                                    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) entry;
} BitmapWindowStorageUpdateReq#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr                                    rowAddr;
    Bool                                        isShiftWindow;
    Bool                                        isShiftOutOfBoundary;
    tData                                       windowShiftedOutData;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageUpdateResp#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageOneToTwoPipelineEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageTwoToThreePipelineEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr        rowAddr;
    Bool            isShiftWindow;
    tShiftOffset    shiftAbsValue;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
    tBoundary boundaryDeltaAbs;
} BitmapWindowStorageStageThreeToFourPipelineEntry#(type tRowAddr, type tData, type tBoundary, type tShiftOffset) deriving(Bits, FShow);

typedef struct {
    tRowAddr        rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageFourToFivePipelineEntry#(type tRowAddr, type tData, type tBoundary, type tShiftOffset) deriving(Bits, FShow);


typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) entry;
} BitmapWindowStorageInternalForwardEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

interface BitmapWindowStorage#(type tRowAddr, type tData, type tBoundary, numeric type szStride);
    interface Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)))) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutVec;
    
    interface PipeIn#(tRowAddr) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

module mkBitmapWindowStorage#(String initFile)(BitmapWindowStorage#(tRowAddr, tData, tBoundary, szStride)) provisos (
        Bits#(tRowAddr, szRowAddr),
        Bits#(tData, szData),
        Bitwise#(tData),
        Literal#(tData),
        Bits#(tBoundary, szBoundary),
        Bounded#(tRowAddr),
        Literal#(tRowAddr),
        Eq#(tRowAddr),
        Arith#(tBoundary),
        Bitwise#(tBoundary),
        Ord#(tBoundary),
        Eq#(tBoundary),
        NumAlias#(TLog#(TDiv#(szData, szStride)), szShiftOffset),
        NumAlias#(TAdd#(1, szShiftOffset), szWideShiftOffset),
        Alias#(Bit#(szShiftOffset), tShiftOffset),
        Alias#(Bit#(szWideShiftOffset), tWideShiftOffset),
        Add#(a__, szShiftOffset, szBoundary),
        Add#(b__, szShiftOffset, TLog#(szData)),
        Add#(c__, szWideShiftOffset, szBoundary),
        Add#(d__, szWideShiftOffset, TLog#(szData)),
        FShow#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary))
    );
    Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)))) reqPipeInVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutVecInst = newVector;

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)))) reqPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(NUMERIC_TYPE_TWO, Vector#(NUMERIC_TYPE_TWO, AutoInferBram#(tRowAddr, BitmapWindowStorageEntry#(tData, tBoundary)))) storage <- replicateM(replicateM(mkAutoInferBramWithRwBypassLogicUG(initFile)));

    Vector#(NUMERIC_TYPE_TWO, Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary))))) reorderBuf <- replicateM(replicateM(mkReg(tagged Invalid)));
    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(tRowAddr))) prevReqRowAddrVec <- replicateM(mkReg(tagged Invalid));

    // Forward Registers (use config reg to solve rule schedule order)
    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(BitmapWindowStorageInternalForwardEntry#(tRowAddr, tData, tBoundary)))) forwardRegVec <- replicateM(mkConfigReg(tagged Invalid));

    // Pipeline Queues
    FIFOF#(Bit#(0)) mergeStateOneToTwoPipelineQueue <- mkLFIFOF;  // only used to handle back pressure
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)))) reorderOutputQueueVec <- replicateM(mkLFIFOF);

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageStageOneToTwoPipelineEntry#(tRowAddr, tData, tBoundary)))) stageOneToTwoPipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageStageTwoToThreePipelineEntry#(tRowAddr, tData, tBoundary)))) stageTwoToThreePipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageStageThreeToFourPipelineEntry#(tRowAddr, tData, tBoundary, tWideShiftOffset)))) stageThreeToFourPipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(BitmapWindowStorageStageFourToFivePipelineEntry#(tRowAddr, tData, tBoundary, tWideShiftOffset))) stageFourToFivePipelineQueueVec <- replicateM(mkLFIFOF);

    function Integer getSelfIdx(Integer idx) = idx;
    function Integer getOtherIdx(Integer idx) = 1 - idx;

    FIFOF#(tRowAddr) resetReqPipeInQ <- mkFIFOF;
    FIFOF#(Bit#(0)) resetRespPipeOutQ <- mkFIFOF;

    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(tRowAddr))) curResetReqRegVec <- replicateM(mkConfigReg(tagged Invalid));
    Reg#(Bool) hasPendingResetRequestReg <- mkReg(False);

    function Bool addrConflictCheck(Maybe#(tRowAddr) prevAddrMaybe, Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)) curReqMaybe);
        let prevAddr = fromMaybe(?, prevAddrMaybe);
        let curReq = fromMaybe(?, curReqMaybe);
        return isValid(prevAddrMaybe) && isValid(curReqMaybe) && prevAddr == curReq.rowAddr;
    endfunction

    function Bool addrConflictCheckV2(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)) in1Maybe, Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)) in2Maybe);
        let in1 = fromMaybe(?, in1Maybe);
        let in2 = fromMaybe(?, in2Maybe);
        return isValid(in1Maybe) && isValid(in1Maybe) && in1.rowAddr == in2.rowAddr;
    endfunction

    // reorder Pipeline Stage One
    rule enqueueIntoReorderBuffer;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            if (reqPipeInQueueVec[idx].notEmpty) begin
                let req = reqPipeInQueueVec[idx].first;
                reqPipeInQueueVec[idx].deq;

                reorderBuf[0][selfChannelIdx] <= req;
            end
        end

        mergeStateOneToTwoPipelineQueue.enq(0);
        
        // $display("time=%0t", $time, "mkBitmapWindowStorage enqueueIntoReorderBuffer", 
        //         ", reqPipeInQueueVec=", fshow(reqPipeInQueueVec)
        // );
    endrule

    // reorder Pipeline Stage Two
    // +-----+-----+
    // |  1  |  2  |    <-  reorderBuf[0]
    // +-----+-----+
    // |  3  |  4  |    <-  reorderBuf[1]
    // +-----+-----+
    rule reorderCore;
        mergeStateOneToTwoPipelineQueue.deq;
        

        let confilct1 = addrConflictCheck(prevReqRowAddrVec[0], reorderBuf[0][0]) || addrConflictCheck(prevReqRowAddrVec[1], reorderBuf[0][0]);
        let confilct2 = addrConflictCheck(prevReqRowAddrVec[0], reorderBuf[0][1]) || addrConflictCheck(prevReqRowAddrVec[1], reorderBuf[0][1]);
        let confilct3 = addrConflictCheck(prevReqRowAddrVec[0], reorderBuf[1][0]) || addrConflictCheck(prevReqRowAddrVec[1], reorderBuf[1][0]);
        let confilct4 = addrConflictCheck(prevReqRowAddrVec[0], reorderBuf[1][1]) || addrConflictCheck(prevReqRowAddrVec[1], reorderBuf[1][1]);
        let conflict13 = addrConflictCheckV2(reorderBuf[0][0], reorderBuf[1][0]);
        let conflict24 = addrConflictCheckV2(reorderBuf[0][1], reorderBuf[1][1]);
        let conflict14 = addrConflictCheckV2(reorderBuf[0][0], reorderBuf[1][1]);
        let conflict23 = addrConflictCheckV2(reorderBuf[0][1], reorderBuf[1][0]);

        let channelOutputMaybeA = ?;
        let channelOutputMaybeB = ?;

        case ({pack(confilct3), pack(confilct4)})
            2'b00: begin
                channelOutputMaybeA = reorderBuf[1][0];
                channelOutputMaybeB = reorderBuf[1][1];
                reorderBuf[1][0] <= reorderBuf[0][0];
                reorderBuf[1][1] <= reorderBuf[0][1];
            end
            2'b01: begin
                if (confilct2) begin
                    if (conflict13) begin
                        channelOutputMaybeA = reorderBuf[0][0];
                        channelOutputMaybeB = reorderBuf[0][1];
                    end
                    else begin
                        channelOutputMaybeA = reorderBuf[1][0];
                        channelOutputMaybeB = reorderBuf[0][0];
                        reorderBuf[1][0] <= reorderBuf[0][1];
                    end
                end
                else begin
                    if (conflict23) begin
                        channelOutputMaybeA = reorderBuf[0][0];
                        channelOutputMaybeB = reorderBuf[0][1];
                    end
                    else begin
                        channelOutputMaybeA = reorderBuf[1][0];
                        channelOutputMaybeB = reorderBuf[0][1];
                        reorderBuf[1][0] <= reorderBuf[0][0];
                    end
                end
            end
            2'b10: begin
                if (confilct1) begin
                    if (conflict24) begin
                        channelOutputMaybeA = reorderBuf[0][0];
                        channelOutputMaybeB = reorderBuf[0][1];
                    end
                    else begin
                        channelOutputMaybeA = reorderBuf[0][1];
                        channelOutputMaybeB = reorderBuf[1][1];
                        reorderBuf[1][1] <= reorderBuf[0][0];
                    end
                end
                else begin
                    if (conflict14) begin
                        channelOutputMaybeA = reorderBuf[0][0];
                        channelOutputMaybeB = reorderBuf[0][1];
                    end
                    else begin
                        channelOutputMaybeA = reorderBuf[0][0];
                        channelOutputMaybeB = reorderBuf[1][1];
                        reorderBuf[1][1] <= reorderBuf[0][1];
                    end
                end
            end
            2'b11: begin
                channelOutputMaybeA = reorderBuf[0][0];
                channelOutputMaybeB = reorderBuf[0][1];
            end

        endcase

        reorderOutputQueueVec[0].enq(channelOutputMaybeA);
        reorderOutputQueueVec[1].enq(channelOutputMaybeB);

        let channelOutputA = fromMaybe(?, channelOutputMaybeA);
        let channelOutputB = fromMaybe(?, channelOutputMaybeB);
        prevReqRowAddrVec[0] <= isValid(channelOutputMaybeA) ? tagged Valid channelOutputA.rowAddr : tagged Invalid;
        prevReqRowAddrVec[1] <= isValid(channelOutputMaybeB) ? tagged Valid channelOutputB.rowAddr : tagged Invalid;

        // $display("time=%0t", $time, "mkBitmapWindowStorage reorderCore \n",
        //         fshow(prevReqRowAddrVec[0]),  " , ",  fshow(prevReqRowAddrVec[1]), "\n",
        //         "------------\n",
        //         fshow(reorderBuf[0][0]), " , ",  fshow(reorderBuf[0][1]), "\n",
        //         fshow(reorderBuf[1][0]), " , ",  fshow(reorderBuf[1][1]), "\n",
        //         "------------\n",
        //         fshow(channelOutputMaybeA),  " , ",  fshow(channelOutputMaybeB), "\n"
        // );

        if (channelOutputMaybeA matches tagged Valid .outA &&& channelOutputMaybeB matches tagged Valid .outB) begin
            immAssert(
                outA.rowAddr != outB.rowAddr,
                "two channel has the same row address",
                $format(", outA=", fshow(outA), ", outB=", fshow(outB))
            );
        end

        // if (isValid(channelOutputMaybeA) && channelOutputA.rowAddr == 4) begin
        //     $display("time=%0t", $time, "mkBitmapWindowStorage reorderCore", 
        //              ", out Channel A out=", fshow(channelOutputA)
        //     );
        // end
        // if (isValid(channelOutputMaybeB) && channelOutputB.rowAddr == 4) begin
        //     $display("time=%0t", $time, "mkBitmapWindowStorage reorderCore", 
        //              ", out Channel B out=", fshow(channelOutputB)
        //     );
        // end
    endrule

    // Merge Pipeline Stage One
    rule sendBramQueryReq;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = reorderOutputQueueVec[selfChannelIdx].first;
            reorderOutputQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                storage[selfChannelIdx][0].putReadReq(pipelineEntryIn.rowAddr);
                storage[otherChannelIdx][1].putReadReq(pipelineEntryIn.rowAddr);

                let pipelineEntryOut = BitmapWindowStorageStageOneToTwoPipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    newEntry: pipelineEntryIn.entry
                };
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                // if (pipelineEntryIn.rowAddr == 4) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 1 sendBramQueryReq", 
                //             ", pipelineEntryIn=", fshow(pipelineEntryIn)
                //     );
                // end
            end
            else begin
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Two
    rule getBramQueryRespAndPreMergeThem;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageOneToTwoPipelineQueueVec[selfChannelIdx].first;
            stageOneToTwoPipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                let selfResp <- storage[selfChannelIdx][0].getReadResp;
                let otherResp <- storage[otherChannelIdx][1].getReadResp;

                Maybe#(BitmapWindowStorageEntry#(tData, tBoundary)) forwardedRespMaybe = tagged Invalid;
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;

                    // if (pipelineEntryIn.rowAddr == 4) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 2 getBramQueryRespAndPreMergeThem", 
                    //             ", forwardRegVec[0]=", fshow(forwardRegVec[0])
                    //     );
                    // end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;

                    // if (pipelineEntryIn.rowAddr == 4) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 2 getBramQueryRespAndPreMergeThem", 
                    //             ", forwardRegVec[1]=", fshow(forwardRegVec[1])
                    //     );
                    // end
                end
                
                let delta = selfResp.leftBound - otherResp.leftBound;

                // if forward path has data, then use the newest value from forward path.
                // else, if delta is non-negative, means `selfResp` is newer or equal to `otherResp`, so choose `selfResp`.
                let selectedResp = isValid(forwardedRespMaybe) ? fromMaybe(?, forwardedRespMaybe) : ( msb(delta) == 0 ? selfResp : otherResp);
                if (delta == 0 && !isValid(forwardedRespMaybe)) begin
                    selectedResp.data = selfResp.data | otherResp.data;
                end

                let pipelineEntryOut = BitmapWindowStorageStageTwoToThreePipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: selectedResp,
                    newEntry: pipelineEntryIn.newEntry
                };


                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                // if (pipelineEntryIn.rowAddr == 4) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 2 getBramQueryRespAndPreMergeThem", 
                //             ", pipelineEntryIn=", fshow(pipelineEntryIn),
                //             ", pipelineEntryOut=", fshow(pipelineEntryOut),
                //             ", selfResp=", fshow(selfResp),
                //             ", otherResp=", fshow(otherResp)
                //     );
                // end
            end
            else begin
                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Three
    rule doNewOldPreMerge;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageTwoToThreePipelineQueueVec[selfChannelIdx].first;
            stageTwoToThreePipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin

                let newestAlreadyExistEntry = pipelineEntryIn.oldEntry;

                // if forward path has valid data, then use the forwarded data.
                // Since the request for the same rowAddr can't occur in two channel at the same time, if any channel has 
                // forwarded data, just use it.
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    newestAlreadyExistEntry = forwardedEntry.entry;

                    // if (pipelineEntryIn.rowAddr == 4) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 3 doNewOldPreMerge", 
                    //             ", forwardRegVec[0]=", fshow(forwardRegVec[0])
                    //     );
                    // end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    newestAlreadyExistEntry = forwardedEntry.entry;

                    // if (pipelineEntryIn.rowAddr == 4) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 3 doNewOldPreMerge", 
                    //             ", forwardRegVec[1]=", fshow(forwardRegVec[1])
                    //     );
                    // end
                end

                tBoundary boundaryDelta = pipelineEntryIn.newEntry.leftBound - newestAlreadyExistEntry.leftBound;
                tBoundary boundaryDeltaAbs = getAbsValue(boundaryDelta);


                let isShiftWindow = msb(boundaryDelta) == 0;

                tWideShiftOffset shiftOffset = unpack(truncate(pack(boundaryDeltaAbs)));
                let pipelineEntryOut = BitmapWindowStorageStageThreeToFourPipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: newestAlreadyExistEntry,
                    newEntry: pipelineEntryIn.newEntry,
                    isShiftWindow: isShiftWindow,
                    boundaryDeltaAbs: boundaryDeltaAbs,
                    shiftAbsValue: shiftOffset
                };

                stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                // if (pipelineEntryIn.rowAddr == 4) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 3 doNewOldPreMerge", 
                //             ", pipelineEntryIn=", fshow(pipelineEntryIn),
                //             ", pipelineEntryOut=", fshow(pipelineEntryOut)
                //     );
                // end
            end
            else begin
                stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Four
    rule doMerge;

        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageThreeToFourPipelineQueueVec[selfChannelIdx].first;
            stageThreeToFourPipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                let alreadyExistEntry = pipelineEntryIn.oldEntry;
                let newEntry = pipelineEntryIn.newEntry;
                tData windowShiftedOutData = -1;

                let isShiftOutOfBoundary = pipelineEntryIn.boundaryDeltaAbs > fromInteger(valueOf(TDiv#(szData, szStride)));

                if (pipelineEntryIn.isShiftWindow) begin
                    alreadyExistEntry.leftBound = newEntry.leftBound;
                end
                else begin
                    newEntry.leftBound = alreadyExistEntry.leftBound;
                end


                Bit#(TLog#(szData)) bitShiftCnt = zeroExtend(pipelineEntryIn.shiftAbsValue) << valueOf(TLog#(szStride));
                tData allOneData = unpack(-1);
                if (pipelineEntryIn.isShiftWindow) begin
                    let tmpToShift = {pack(alreadyExistEntry.data), pack(allOneData)};
                    tmpToShift = tmpToShift >> bitShiftCnt;
                    alreadyExistEntry.data = unpack(truncateLSB(tmpToShift));
                    windowShiftedOutData = unpack(truncate(tmpToShift));
                end
                else begin 
                    newEntry.data = newEntry.data >> bitShiftCnt;
                end


                newEntry.data = newEntry.data | alreadyExistEntry.data;

                let forwardEntry = BitmapWindowStorageInternalForwardEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    entry: newEntry
                };
                forwardRegVec[selfChannelIdx] <= tagged Valid forwardEntry;

                let resp = BitmapWindowStorageUpdateResp {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: pipelineEntryIn.oldEntry,
                    windowShiftedOutData: windowShiftedOutData,
                    isShiftOutOfBoundary: isShiftOutOfBoundary,
                    isShiftWindow: pipelineEntryIn.isShiftWindow,
                    newEntry: newEntry
                };
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Valid resp);

                let bramWriteBackReq = BitmapWindowStorageStageFourToFivePipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    newEntry: newEntry
                };
                stageFourToFivePipelineQueueVec[selfChannelIdx].enq(bramWriteBackReq);

                // if (pipelineEntryIn.rowAddr == 4) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 4 doMerge", 
                //             ", pipelineEntryIn=", fshow(pipelineEntryIn),
                //             ", resp=", fshow(resp)
                //     );
                // end

            end
            else begin
                forwardRegVec[selfChannelIdx] <= tagged Invalid;
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Five
    (* conflict_free = "doBramWriteBack, handleResetRequest" *)
    rule doBramWriteBack;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);
            if (stageFourToFivePipelineQueueVec[idx].notEmpty) begin
                let writeBackReq = stageFourToFivePipelineQueueVec[idx].first;
                stageFourToFivePipelineQueueVec[idx].deq;

                storage[selfChannelIdx][0].write(writeBackReq.rowAddr, writeBackReq.newEntry);
                storage[selfChannelIdx][1].write(writeBackReq.rowAddr, writeBackReq.newEntry);

                // if (writeBackReq.rowAddr == 4) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 5 doBramWriteBack", 
                //             ", writeBackReq=", fshow(writeBackReq)
                //     );
                // end
            end
            else begin
                // Reset is low priority.
                if (curResetReqRegVec[selfChannelIdx] matches tagged Valid .resetReqAddr) begin
                    let resetValue = BitmapWindowStorageEntry{
                        leftBound: -1,
                        data: -1
                    };
                    storage[selfChannelIdx][0].write(resetReqAddr, resetValue);
                    storage[selfChannelIdx][1].write(resetReqAddr, resetValue);
                    curResetReqRegVec[selfChannelIdx] <= tagged Invalid;
                end
            end
        end
    endrule

    rule handleResetRequest;
        if (!hasPendingResetRequestReg) begin
            if ( (!isValid(curResetReqRegVec[0])) && (!isValid(curResetReqRegVec[1])) ) begin
                if (resetReqPipeInQ.notEmpty) begin
                    curResetReqRegVec[0] <= tagged Valid resetReqPipeInQ.first;
                    curResetReqRegVec[1] <= tagged Valid resetReqPipeInQ.first;
                    resetReqPipeInQ.deq;
                    hasPendingResetRequestReg <= True;
                end
            end
        end
        else begin
            if ( (!isValid(curResetReqRegVec[0])) && (!isValid(curResetReqRegVec[1])) ) begin
                hasPendingResetRequestReg <= False;
                resetRespPipeOutQ.enq(0);
            end
        end
    endrule

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQ);
    interface resetRespPipeOut = toPipeOut(resetRespPipeOutQ);
endmodule


typedef struct {
    BitmapWindowStorageEntry#(tData, tBoundary) bitmapEntry;
} CpsnCounterReq#(type tData, type tBoundary) deriving(FShow, Bits);



interface CpsnCounter#(type tData, type tBoundary, numeric type szStride);
    interface PipeIn#(CpsnCounterReq#(tData, tBoundary)) reqPipeIn;
    interface PipeOut#(PSN) respPipeOut;
endinterface

module mkCpsnCounter(CpsnCounter#(tData, tBoundary, szStride)) provisos (
    Bits#(tData, szData),
    NumAlias#(32, szCompareBlock),
    Alias#(Bit#(szCompareBlock), tCompareBlock),
    NumAlias#(TLog#(TAdd#(szData, 1)), szDataBitCount),
    Alias#(Bit#(szDataBitCount), tDataBitCount),
    NumAlias#(TDiv#(szData, szCompareBlock), nCompareBlockCount),
    NumAlias#(TLog#(nCompareBlockCount), szCompareBlockCount),
    Alias#(Bit#(szCompareBlockCount), tCompareBlockIdx),
    Alias#(Bit#(nCompareBlockCount), tBlockCompareResultBitmap),
    Bits#(tBoundary, szBoundary),
    Add#(a__, szBoundary, PSN_WIDTH),
    Arith#(tBoundary),
    Add#(b__, szDataBitCount, PSN_WIDTH),
    Add#(szCompareBlockCount, c__, szDataBitCount),
    FShow#(Tuple5#(Bool, Bit#(TLog#(TDiv#(szData, 32))), Bit#(32), Bit#(32),
    tBoundary))

);
    FIFOF#(CpsnCounterReq#(tData, tBoundary)) reqPipeInQ <- mkFIFOF;
    FIFOF#(PSN) respPipeOutQ <- mkFIFOF;


    FIFOF#(Tuple5#(Bool, tCompareBlockIdx, tCompareBlock, tCompareBlock, tBoundary)) stageOneToTwoPipelineQueue <- mkFIFOF;
    rule firstState;
        let req = reqPipeInQ.first;
        reqPipeInQ.deq;

        tBoundary rightBoundary = req.bitmapEntry.leftBound - fromInteger(valueOf(TDiv#(szData, szStride))-1);
        

        tBlockCompareResultBitmap fullOneBlockBitmap = 0;

        Bit#(szData) windowBitmap = unpack(pack(req.bitmapEntry.data));
        Vector#(nCompareBlockCount, tCompareBlock) invBlockVec = newVector;
        for (Integer idx = 0; idx < valueOf(nCompareBlockCount); idx = idx + 1) begin
            tCompareBlock block = windowBitmap[ valueOf(szCompareBlock) * (idx + 1) - 1 : valueOf(szCompareBlock) * idx ];
            fullOneBlockBitmap[idx] = pack(block == -1);
            invBlockVec[idx] = ~block;
        end

        Bool foundNonFullOneBlock = False;
        tCompareBlockIdx firstNonFullOneBlockIdx = 0;
        tCompareBlock firstNonFullOneBlockPos = 0;
        tCompareBlock firstNonFullOneBlockNeg = 0;
        for (Integer idx = 0; idx < valueOf(nCompareBlockCount); idx = idx + 1) begin
            if ( !foundNonFullOneBlock && fullOneBlockBitmap[idx] == 0 ) begin
                foundNonFullOneBlock = True;
                firstNonFullOneBlockIdx = fromInteger(idx);
                firstNonFullOneBlockPos = invBlockVec[idx];
                firstNonFullOneBlockNeg = -invBlockVec[idx];
            end
        end

        stageOneToTwoPipelineQueue.enq(tuple5(foundNonFullOneBlock, firstNonFullOneBlockIdx, firstNonFullOneBlockPos, firstNonFullOneBlockNeg, rightBoundary));
    endrule


    rule secondStage;
        let {foundNonFullOneBlock, firstNonFullOneBlockIdx, firstNonFullOneBlockPos, firstNonFullOneBlockNeg, rightBoundary} = stageOneToTwoPipelineQueue.first;
        stageOneToTwoPipelineQueue.deq;
        PSN rightMostPsn = zeroExtendLSB(pack(rightBoundary));
        PSN cpsn = rightMostPsn;

        if (!foundNonFullOneBlock) begin
            cpsn = cpsn + fromInteger(valueOf(szCompareBlock) * valueOf(nCompareBlockCount));
        end
        else begin
            tDataBitCount continousOneCntHighPart = zeroExtend(pack(firstNonFullOneBlockIdx)) << valueOf(TLog#(szCompareBlock));
            tDataBitCount continousOneCntLowPart = 0;

            tCompareBlock oneHot = firstNonFullOneBlockPos & firstNonFullOneBlockNeg;

            for (Integer idx = 0; idx < valueOf(szCompareBlock); idx = idx + 1) begin
                if ( oneHot[idx] == 1 ) begin
                    continousOneCntLowPart = fromInteger(idx);
                end
            end
            tDataBitCount continousOneInBlock = continousOneCntHighPart + continousOneCntLowPart;
            cpsn = cpsn + zeroExtend(continousOneInBlock);
        end
        respPipeOutQ.enq(cpsn);
    endrule

    interface reqPipeIn = toPipeIn(reqPipeInQ);
    interface respPipeOut = toPipeOut(respPipeOutQ);
endmodule





typedef struct {
    tRowAddr    rowAddr;
    tData       value;
} MonoInrcNumberStorageUpdateReq#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    tData       newValue;
} MonoInrcNumberStorageUpdateResp#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tData       data;
} MonoInrcNumberStorageEntry#(type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    MonoInrcNumberStorageEntry#(tData) newEntry;
} MonoInrcNumberStorageStageOneToTwoPipelineEntry#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    MonoInrcNumberStorageEntry#(tData) oldEntry;
    MonoInrcNumberStorageEntry#(tData) newEntry;
} MonoInrcNumberStorageStageTwoToThreePipelineEntry#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr        rowAddr;
    MonoInrcNumberStorageEntry#(tData) newEntry;
} MonoInrcNumberStorageStageThreeToFourPipelineEntry#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    MonoInrcNumberStorageEntry#(tData) entry;
} MonoInrcNumberStorageInternalForwardEntry#(type tRowAddr, type tData) deriving(Bits, FShow);

interface MonoInrcNumberStorage#(type tRowAddr, type tData);
    interface Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(MonoInrcNumberStorageUpdateReq#(tRowAddr, tData)))) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(MonoInrcNumberStorageUpdateResp#(tRowAddr, tData)))) respPipeOutVec;
    
    interface PipeIn#(tRowAddr) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

module mkMonoInrcNumberStorage#(String initFile)(MonoInrcNumberStorage#(tRowAddr, tData)) provisos (
        Bits#(tRowAddr, szRowAddr),
        Bits#(tData, szData),
        Bitwise#(tData),
        Literal#(tData),
        Arith#(tData),
        Ord#(tData),
        Bounded#(tRowAddr),
        Literal#(tRowAddr),
        Eq#(tRowAddr),
        FShow#(MonoInrcNumberStorageUpdateReq#(tRowAddr, tData))
    );
    Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(MonoInrcNumberStorageUpdateReq#(tRowAddr, tData)))) reqPipeInVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(MonoInrcNumberStorageUpdateResp#(tRowAddr, tData)))) respPipeOutVecInst = newVector;

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(MonoInrcNumberStorageUpdateReq#(tRowAddr, tData)))) reqPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(MonoInrcNumberStorageUpdateResp#(tRowAddr, tData)))) respPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(NUMERIC_TYPE_TWO, Vector#(NUMERIC_TYPE_TWO, AutoInferBram#(tRowAddr, MonoInrcNumberStorageEntry#(tData)))) storage <- replicateM(replicateM(mkAutoInferBramWithRwBypassLogicUG(initFile)));

    // Forward Registers (use config reg to solve rule schedule order)
    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(MonoInrcNumberStorageInternalForwardEntry#(tRowAddr, tData)))) forwardRegVec <- replicateM(mkConfigReg(tagged Invalid));

    // Pipeline Queues

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(MonoInrcNumberStorageStageOneToTwoPipelineEntry#(tRowAddr, tData)))) stageOneToTwoPipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(MonoInrcNumberStorageStageTwoToThreePipelineEntry#(tRowAddr, tData)))) stageTwoToThreePipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(MonoInrcNumberStorageStageThreeToFourPipelineEntry#(tRowAddr, tData))) stageThreeToFourPipelineQueueVec <- replicateM(mkLFIFOF);

    function Integer getSelfIdx(Integer idx) = idx;
    function Integer getOtherIdx(Integer idx) = 1 - idx;

    FIFOF#(tRowAddr) resetReqPipeInQ <- mkFIFOF;
    FIFOF#(Bit#(0)) resetRespPipeOutQ <- mkFIFOF;

    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(tRowAddr))) curResetReqRegVec <- replicateM(mkConfigReg(tagged Invalid));
    Reg#(Bool) hasPendingResetRequestReg <- mkReg(False);

    // Merge Pipeline Stage One
    rule sendBramQueryReq;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = reqPipeInQueueVec[selfChannelIdx].first;
            reqPipeInQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                storage[selfChannelIdx][0].putReadReq(pipelineEntryIn.rowAddr);
                storage[otherChannelIdx][1].putReadReq(pipelineEntryIn.rowAddr);

                let pipelineEntryOut = MonoInrcNumberStorageStageOneToTwoPipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    newEntry: MonoInrcNumberStorageEntry {
                        data: pipelineEntryIn.value
                    }
                };
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                if (pipelineEntryIn.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkMonoInrcNumberStorage 1 sendBramQueryReq", 
                    //         ", pipelineEntryIn=", fshow(pipelineEntryIn)
                    // );
                end
            end
            else begin
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Two
    rule getBramQueryRespAndPreMergeThem;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageOneToTwoPipelineQueueVec[selfChannelIdx].first;
            stageOneToTwoPipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                let selfResp <- storage[selfChannelIdx][0].getReadResp;
                let otherResp <- storage[otherChannelIdx][1].getReadResp;

                Maybe#(MonoInrcNumberStorageEntry#(tData)) forwardedRespMaybe = tagged Invalid;
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;

                    if (pipelineEntryIn.rowAddr == 4) begin
                        // $display("time=%0t", $time, "mkMonoInrcNumberStorage 2 getBramQueryRespAndPreMergeThem", 
                        //         ", forwardRegVec[0]=", fshow(forwardRegVec[0])
                        // );
                    end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;

                    if (pipelineEntryIn.rowAddr == 4) begin
                        // $display("time=%0t", $time, "mkMonoInrcNumberStorage 2 getBramQueryRespAndPreMergeThem", 
                        //         ", forwardRegVec[1]=", fshow(forwardRegVec[1])
                        // );
                    end
                end
                
                let delta = selfResp.data - otherResp.data;

                // if forward path has data, then use the newest value from forward path.
                // else, if delta is non-negative, means `selfResp` is newer or equal to `otherResp`, so choose `selfResp`.
                let selectedResp = isValid(forwardedRespMaybe) ? fromMaybe(?, forwardedRespMaybe) : ( msb(delta) == 0 ? selfResp : otherResp);

                let pipelineEntryOut = MonoInrcNumberStorageStageTwoToThreePipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: selectedResp,
                    newEntry: pipelineEntryIn.newEntry
                };

                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                if (pipelineEntryIn.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkMonoInrcNumberStorage 2 getBramQueryRespAndPreMergeThem", 
                    //         ", pipelineEntryIn=", fshow(pipelineEntryIn),
                    //         ", pipelineEntryOut=", fshow(pipelineEntryOut),
                    //         ", selfResp=", fshow(selfResp),
                    //         ", otherResp=", fshow(otherResp)
                    // );
                end
            end
            else begin
                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Three
    rule doMerge;

        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageTwoToThreePipelineQueueVec[selfChannelIdx].first;
            stageTwoToThreePipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                let alreadyExistEntry = pipelineEntryIn.oldEntry;
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    alreadyExistEntry = forwardedEntry.entry;
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    alreadyExistEntry = forwardedEntry.entry;
                end

                let delta = pipelineEntryIn.newEntry.data - alreadyExistEntry.data;
                let newEntry =  msb(delta) == 0 ? pipelineEntryIn.newEntry : alreadyExistEntry;

                let forwardEntry = MonoInrcNumberStorageInternalForwardEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    entry: newEntry
                };
                forwardRegVec[selfChannelIdx] <= tagged Valid forwardEntry;

                let resp = MonoInrcNumberStorageUpdateResp {
                    rowAddr: pipelineEntryIn.rowAddr,
                    newValue: newEntry.data
                };
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Valid resp);

                let bramWriteBackReq = MonoInrcNumberStorageStageThreeToFourPipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    newEntry: newEntry
                };
                stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(bramWriteBackReq);

                if (pipelineEntryIn.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkMonoInrcNumberStorage 3 doMerge", 
                    //         ", pipelineEntryIn=", fshow(pipelineEntryIn),
                    //         ", resp=", fshow(resp)
                    // );
                end

            end
            else begin
                forwardRegVec[selfChannelIdx] <= tagged Invalid;
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Merge Pipeline Stage Four
    (* conflict_free = "doBramWriteBack, handleResetRequest" *)
    rule doBramWriteBack;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);
            if (stageThreeToFourPipelineQueueVec[idx].notEmpty) begin
                let writeBackReq = stageThreeToFourPipelineQueueVec[idx].first;
                stageThreeToFourPipelineQueueVec[idx].deq;

                storage[selfChannelIdx][0].write(writeBackReq.rowAddr, writeBackReq.newEntry);
                storage[selfChannelIdx][1].write(writeBackReq.rowAddr, writeBackReq.newEntry);

                if (writeBackReq.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkMonoInrcNumberStorage 4 doBramWriteBack", 
                    //         ", writeBackReq=", fshow(writeBackReq)
                    // );
                end
            end
            else begin
                // Reset is low priority.
                if (curResetReqRegVec[selfChannelIdx] matches tagged Valid .resetReqAddr) begin
                    let resetValue = MonoInrcNumberStorageEntry{
                        data: 0
                    };
                    storage[selfChannelIdx][0].write(resetReqAddr, resetValue);
                    storage[selfChannelIdx][1].write(resetReqAddr, resetValue);
                    curResetReqRegVec[selfChannelIdx] <= tagged Invalid;
                end
            end
        end
    endrule

    rule handleResetRequest;
        if (!hasPendingResetRequestReg) begin
            if ( (!isValid(curResetReqRegVec[0])) && (!isValid(curResetReqRegVec[1])) ) begin
                if (resetReqPipeInQ.notEmpty) begin
                    curResetReqRegVec[0] <= tagged Valid resetReqPipeInQ.first;
                    curResetReqRegVec[1] <= tagged Valid resetReqPipeInQ.first;
                    resetReqPipeInQ.deq;
                    hasPendingResetRequestReg <= True;
                end
            end
        end
        else begin
            if ( (!isValid(curResetReqRegVec[0])) && (!isValid(curResetReqRegVec[1])) ) begin
                hasPendingResetRequestReg <= False;
                resetRespPipeOutQ.enq(0);
            end
        end
    endrule

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQ);
    interface resetRespPipeOut = toPipeOut(resetRespPipeOutQ);
endmodule


typedef struct {
    BitmapWindowStorageEntry#(tData, tBoundary) needAckBitmap;
    PSN cpsn;
} MaxAckPsnCalculatorReq#(type tData, type tBoundary) deriving(Bits, FShow);


interface MaxAckPsnCalculator#(type tData, type tBoundary);
    interface PipeIn#(MaxAckPsnCalculatorReq#(tData, tBoundary)) reqPipeIn;
    interface PipeOut#(Maybe#(PSN)) respPipeOut;
endinterface

module mkMaxAckPsnCalculator(MaxAckPsnCalculator#(tData, tBoundary)) provisos (
        Bits#(tData, szData),
        NumAlias#(TLog#(szData), szShiftOffset),
        Alias#(Bit#(szShiftOffset), tShiftOffset),
        Add#(a__, szShiftOffset, PSN_WIDTH),
        Bits#(tBoundary, szBoundary),
        Add#(b__, szBoundary, 24),
        Eq#(tData),
        Bitwise#(tData),
        Literal#(tData)
    );
    FIFOF#(MaxAckPsnCalculatorReq#(tData, tBoundary)) reqPipeInQueue <- mkFIFOF;
    FIFOF#(Maybe#(PSN)) respPipeOutQueue <- mkFIFOF;


    FIFOF#(Tuple4#(Bool, Bool, tShiftOffset, MaxAckPsnCalculatorReq#(tData, tBoundary))) doShiftPipelineQ <- mkFIFOF;
    FIFOF#(Tuple2#(BitmapWindowStorageEntry#(tData, tBoundary), MaxAckPsnCalculatorReq#(tData, tBoundary))) doBitmapCompareQ <- mkFIFOF;
    rule preClac;
        let req = reqPipeInQueue.first;
        reqPipeInQueue.deq;

        PSN leftMostPsnValOfBitmapWindow = unpack({pack(req.needAckBitmap.leftBound), -1});
        PSN psnDelta = leftMostPsnValOfBitmapWindow - req.cpsn;
        Bool isCpsnFallBehindExceedWindow = psnDelta >= fromInteger(valueOf(szData));
        Bool isCpsnGreaterThanWholeWindow = msb(psnDelta) == 1;
        tShiftOffset shiftOffset = truncate(psnDelta);

        doShiftPipelineQ.enq(tuple4(isCpsnFallBehindExceedWindow, isCpsnGreaterThanWholeWindow, shiftOffset, req));

    endrule

    rule doShift;
        let {isCpsnFallBehindExceedWindow, isCpsnGreaterThanWholeWindow, shiftOffset, req} = doShiftPipelineQ.first;
        doShiftPipelineQ.deq;

        BitmapWindowStorageEntry#(tData, tBoundary) psnBitmapEntry = req.needAckBitmap;
        if (isCpsnGreaterThanWholeWindow) begin
            psnBitmapEntry.data = -1;
        end
        else if (isCpsnFallBehindExceedWindow) begin
            psnBitmapEntry.data = 0;
        end
        else begin
            psnBitmapEntry.data = -1;
            psnBitmapEntry.data = psnBitmapEntry.data >> shiftOffset;
        end
        doBitmapCompareQ.enq(tuple2(psnBitmapEntry, req));
    endrule

    rule doBitmapCompare;
        let {psnBitmapEntry, req} = doBitmapCompareQ.first;
        doBitmapCompareQ.deq;

        let maskedNeedAckBitmap = req.needAckBitmap.data & psnBitmapEntry.data;
        if (maskedNeedAckBitmap != 0) begin
            respPipeOutQueue.enq(tagged Valid req.cpsn);
        end
        else begin
            respPipeOutQueue.enq(tagged Invalid);
        end
    endrule

    interface reqPipeIn = toPipeIn(reqPipeInQueue);
    interface respPipeOut = toPipeOut(respPipeOutQueue);
endmodule