import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import ConfigReg :: * ;

import PrimUtils :: *;
import BasicDataTypes :: *;

import RdmaHeaders :: *;


import ConnectableF :: *;

typedef 4 CPSN_CHECKER_CHANNEL_NUM;
typedef Bit#(TLog#(CPSN_CHECKER_CHANNEL_NUM)) CpsnCheckerChannelIdx;



typedef TSub#(PSN_WIDTH, TLog#(ACK_WINDOW_STRIDE)) PSN_MERGE_WINDOW_BOUNDARY_WIDTH;
typedef Bit#(PSN_MERGE_WINDOW_BOUNDARY_WIDTH) PsnMergeWindowBoundary;
typedef Bit#(TLog#(ACK_BITMAP_WIDTH)) PsnMergeWindowBitOffset;


typedef struct {
    PSN psn;
    QPN qpn;
} FourChannelPsnBitmapPreMergeReq deriving(Bits, FShow);

typedef struct {
    QPN qpn;
    PSN psn;  // for debug use
    PsnMergeWindowBoundary maxLeftBoundary;
    AckBitmap  bitmap;
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
            // $display("time=%0t", $time, ", mkFourChannelPsnBitmapPreMerge handleInputReqEveryTwoBeta", 
            //     ", outVec=", fshow(outVec)
            // );
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
        
        Bool overFlowOccured = False;
        for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
            let channelInfoMaybe = pipelineEntryIn[idx];
            if (channelInfoMaybe matches tagged Valid .channelInfo) begin
                
                // extend lsb and fill lsb with 1
                PSN boundaryPSN = unpack({pack(channelInfo.maxLeftBoundary), -1});
                let shiftDelta = boundaryPSN - channelInfo.psn;

                Bool isOverflow = (shiftDelta >= fromInteger(valueOf(ACK_BITMAP_WIDTH)));
                overFlowOccured = overFlowOccured || isOverflow;

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
        if (overFlowOccured) begin
            $display("time=%0t", $time, ", mkFourChannelPsnBitmapPreMerge preCalcOneHotBitmapMetaForEachChannel", 
                toRed(" WARNING overflow occured in psn bitmap permerge"),
                ", outputVec=", fshow(outputVec)
            );
        end
    endrule

    rule genOneHotBitmapForEachChannel;
        let pipelineEntryIn = onehotGenMetaCalcPipelineQueue.first;
        onehotGenMetaCalcPipelineQueue.deq;

        Vector#(CPSN_CHECKER_CHANNEL_NUM, Maybe#(FourChannelPsnBitmapPreMergeResp)) outputVec = newVector;

        Bool needPrintDebugInfo = False;
        for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
            let channelInfoMaybe = pipelineEntryIn[idx];
            if (channelInfoMaybe matches tagged Valid .channelInfo) begin
                AckBitmap  bitmap = channelInfo.isOverflow ? 0 : swapEndianBit(1 << channelInfo.shiftOffset);

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

        // $display("time=%0t", $time, ", mkFourChannelPsnBitmapPreMerge preMergeChannels", 
        //     ", outVec=", fshow(outVec)
        // );
    endrule



    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
    end
    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOut = toPipeOut(respPipeOutQueue);
endmodule

// Must be 2^N
typedef 4  OOO_WINDOW_BITMAP_STORAGE_EPOCH_WIDTH;
typedef Bit#(OOO_WINDOW_BITMAP_STORAGE_EPOCH_WIDTH) AckBitmapStorageEntryEpoch;
typedef 1  OOO_WINDOW_BITMAP_STORAGE_CHANNEL_IDX_WIDTH;
typedef Bit#(OOO_WINDOW_BITMAP_STORAGE_CHANNEL_IDX_WIDTH) AckBitmapStorageChannelIdx;

typedef struct {
    tData                               data;
    tBoundary                           leftBound;
    AckBitmapStorageEntryEpoch          epoch;
    AckBitmapStorageChannelIdx          channelIdx;
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
    Bool isReset;
} BitmapWindowStorageStageFourToFivePipelineEntry#(type tRowAddr, type tData, type tBoundary, type tShiftOffset) deriving(Bits, FShow);


typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) entry;
} BitmapWindowStorageInternalForwardEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

interface BitmapWindowStorage#(type tRowAddr, type tData, type tBoundary, numeric type szStride);
    interface Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary)))) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutVec;
    
    interface PipeIn#(tRowAddr)                                         readOnlyReqPipeIn;
    interface PipeOut#(BitmapWindowStorageEntry#(tData, tBoundary))     readOnlyRespPipeOut;

    interface PipeIn#(tRowAddr) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

module mkBitmapWindowStorage(BitmapWindowStorage#(tRowAddr, tData, tBoundary, szStride)) provisos (
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

    FIFOF#(tRowAddr)                                        readOnlyReqPipeInQueue <- mkFIFOF;
    FIFOF#(BitmapWindowStorageEntry#(tData, tBoundary))     readOnlyRespPipeOutQueue <- mkFIFOF;

    Vector#(NUMERIC_TYPE_TWO, Vector#(NUMERIC_TYPE_THREE, AutoInferBram#(tRowAddr, BitmapWindowStorageEntry#(tData, tBoundary)))) storage = newVector;
    storage[0][0] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch0.bin");
    storage[0][1] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch0.bin");
    storage[0][2] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch0.bin");
    storage[1][0] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch1.bin");
    storage[1][1] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch1.bin");
    storage[1][2] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch1.bin");
    


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
                // if (pipelineEntryIn.rowAddr == 3) begin
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

                
                immAssert(
                    selfResp.channelIdx == fromInteger(selfChannelIdx),
                    "all entry from channel N must have this field as N.",
                    $format(
                        ", selfChannelIdx=%d", selfChannelIdx,
                        ", selfResp=", fshow(selfResp)
                    )
                );
                
                

                Maybe#(BitmapWindowStorageEntry#(tData, tBoundary)) forwardedRespMaybe = tagged Invalid;
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;
                    immAssert(
                        forwardedEntry.entry.channelIdx == 0,
                        "all entry from channel 0 must have this field as 0.",
                        $format(
                            ", selfChannelIdx=%d", selfChannelIdx,
                            ", forwardedEntry=", fshow(forwardedEntry)
                        )
                    );

                    // if (pipelineEntryIn.rowAddr == 3) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 2 getBramQueryRespAndPreMergeThem", 
                    //             ", forwardRegVec[0]=", fshow(forwardRegVec[0])
                    //     );
                    // end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;
                    immAssert(
                        forwardedEntry.entry.channelIdx == 1,
                        "all entry from channel 1 must have this field as 1.",
                        $format(
                            ", selfChannelIdx=%d", selfChannelIdx,
                            ", forwardedEntry=", fshow(forwardedEntry)
                        )
                    );

                    // if (pipelineEntryIn.rowAddr == 3) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 2 getBramQueryRespAndPreMergeThem", 
                    //             ", forwardRegVec[1]=", fshow(forwardRegVec[1])
                    //     );
                    // end
                end
                
                let delta = selfResp.epoch - otherResp.epoch;

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
                // if (pipelineEntryIn.rowAddr == 3) begin
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
                    immAssert(
                        newestAlreadyExistEntry.channelIdx == 0,
                        "all entry from channel 0 must have this field as 0.",
                        $format(
                            ", selfChannelIdx=%d", selfChannelIdx,
                            ", forwardedEntry=", fshow(forwardedEntry)
                        )
                    );
                    // if (pipelineEntryIn.rowAddr == 3) begin
                    //     $display("time=%0t", $time, "mkBitmapWindowStorage 3 doNewOldPreMerge", 
                    //             ", forwardRegVec[0]=", fshow(forwardRegVec[0])
                    //     );
                    // end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    newestAlreadyExistEntry = forwardedEntry.entry;
                    immAssert(
                        newestAlreadyExistEntry.channelIdx == 1,
                        "all entry from channel 1 must have this field as 1.",
                        $format(
                            ", selfChannelIdx=%d", selfChannelIdx,
                            ", forwardedEntry=", fshow(forwardedEntry)
                        )
                    );
                    // if (pipelineEntryIn.rowAddr == 3) begin
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
                // if (pipelineEntryIn.rowAddr == 3) begin
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

                immAssert(
                    newEntry.channelIdx == fromInteger(selfChannelIdx),
                    "all entry from channel N must have this field as N.",
                    $format(
                        ", selfChannelIdx=%d", selfChannelIdx,
                        ", pipelineEntryIn=", fshow(pipelineEntryIn)
                    )
                );

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
                if (newEntry.channelIdx != pipelineEntryIn.oldEntry.channelIdx || pipelineEntryIn.oldEntry.epoch == 0) begin
                    // for example, when a very big message is send on the wire, it's likely that the continous packet will from the same channel,
                    // and there will be only one valid channel per beat, which always goes into first channel, leading the other channel stall.
                    // so, we only increase epoch when the channel changes, to make sure when merging from two channels, the newest one will be selected.
                    // and the first beat is tricky, since the init epoch of every channel is 0, suppose the following case:
                    // channel 0 comes the first req, old epoch is 0, and then the second req for the same row comes from channel 1, if we didn't
                    // update the epoch to 1 in the first request, then the second request may select the wrong path as the newest entry.

                    newEntry.epoch = pipelineEntryIn.oldEntry.epoch + 1;
                end
                else begin
                    // we need this branch, because the input newEntry's epoch is a random one, it should be set to the oldEntry's
                    newEntry.epoch = pipelineEntryIn.oldEntry.epoch;
                end

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
                    newEntry: newEntry,
                    isReset: False
                };
                stageFourToFivePipelineQueueVec[selfChannelIdx].enq(bramWriteBackReq);

                // if (pipelineEntryIn.rowAddr == 3) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 4 doMerge", 
                //             ", resp=", fshow(resp)
                //     );
                //     // $display("time=%0t", $time, "mkBitmapWindowStorage 4 doMerge", 
                //     //         ", pipelineEntryIn=", fshow(pipelineEntryIn),
                //     //         ", resp=", fshow(resp)
                //     // );
                // end
            end
            else begin
                forwardRegVec[selfChannelIdx] <= tagged Invalid;
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Invalid);

                // Reset is low priority.
                if (curResetReqRegVec[selfChannelIdx] matches tagged Valid .resetReqAddr) begin
                    let resetValue = BitmapWindowStorageEntry{
                        leftBound: -1,
                        data: -1,
                        epoch: 0,
                        channelIdx: fromInteger(selfChannelIdx)
                    };
                    let bramWriteBackReq = BitmapWindowStorageStageFourToFivePipelineEntry {
                        rowAddr: resetReqAddr,
                        newEntry: resetValue,
                        isReset: True
                    };
                    stageFourToFivePipelineQueueVec[selfChannelIdx].enq(bramWriteBackReq);
                end

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
                storage[selfChannelIdx][2].write(writeBackReq.rowAddr, writeBackReq.newEntry);

                if (writeBackReq.isReset) begin
                    curResetReqRegVec[selfChannelIdx] <= tagged Invalid;
                end

                // if (writeBackReq.rowAddr == 4) begin
                //     $display("time=%0t", $time, "mkBitmapWindowStorage 5 doBramWriteBack", 
                //             ", writeBackReq=", fshow(writeBackReq)
                //     );
                // end
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

    rule handleReadOnlyReq;
        let addr = readOnlyReqPipeInQueue.first;
        readOnlyReqPipeInQueue.deq;
        storage[0][2].putReadReq(addr);
        storage[1][2].putReadReq(addr);
    endrule

    rule handleReadOnlyResp;
        let resp0 <- storage[0][2].getReadResp;
        let resp1 <- storage[1][2].getReadResp;
        
        let delta = resp0.epoch - resp1.epoch;

        let selectedResp = (msb(delta) == 0 ? resp0 : resp1);
        readOnlyRespPipeOutQueue.enq(selectedResp);
    endrule

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;

    interface readOnlyReqPipeIn     = toPipeIn(readOnlyReqPipeInQueue);
    interface readOnlyRespPipeOut   = toPipeOut(readOnlyRespPipeOutQueue);

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQ);
    interface resetRespPipeOut = toPipeOut(resetRespPipeOutQ);
endmodule


interface PsnPerMergeAndStorage;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(FourChannelPsnBitmapPreMergeReq)) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary)))) respPipeOutVec;

    interface PipeIn#(IndexQP) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface


(* synthesize *)
module mkPsnPerMergeAndStorage(PsnPerMergeAndStorage);
    FourChannelPsnBitmapPreMerge allPacketPsnPermerge <- mkFourChannelPsnBitmapPreMerge;

    BitmapWindowStorage#(IndexQP, AckBitmap, PsnMergeWindowBoundary, ACK_WINDOW_STRIDE) allPacketPsnBitmapStorage <- mkBitmapWindowStorage;

    Reg#(Bool) forwardToStorageEvenOddReg <- mkReg(True);


    rule forwardPremergeToStorage;
        forwardToStorageEvenOddReg <= !forwardToStorageEvenOddReg;
        let allPacketStorageResp = allPacketPsnPermerge.respPipeOut.first;

        // if (forwardToStorageEvenOddReg) begin
        //     $display("time=%0t", $time, "mkPsnPerMergeAndStorage forwardPremergeToStorage", 
        //             ", allPacketStorageResp=", fshow(allPacketStorageResp)
        //     );
        // end

        if (forwardToStorageEvenOddReg) begin
            if (allPacketStorageResp[0] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary,
                        epoch: ?,
                        channelIdx: 0
                    }
                });
               
            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (allPacketStorageResp[1] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary,
                        epoch: ?,
                        channelIdx: 1
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end
        end
        else begin
            if (allPacketStorageResp[2] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary,
                        epoch: ?,
                        channelIdx: 0
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (allPacketStorageResp[3] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary,
                        epoch: ?,
                        channelIdx: 1
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            allPacketPsnPermerge.respPipeOut.deq;
        end
    endrule


    interface reqPipeInVec = allPacketPsnPermerge.reqPipeInVec;
    interface respPipeOutVec = allPacketPsnBitmapStorage.respPipeOutVec;

    interface resetReqPipeIn = allPacketPsnBitmapStorage.resetReqPipeIn;
    interface resetRespPipeOut = allPacketPsnBitmapStorage.resetRespPipeOut;
endmodule



// Must be 2^N
typedef 4  ATOMIC_UPDATE_STORAGE_EPOCH_WIDTH;
typedef Bit#(ATOMIC_UPDATE_STORAGE_EPOCH_WIDTH) AtomicUpdateStorageEntryEpoch;
typedef 1  ATOMIC_UPDATE_STORAGE_CHANNEL_IDX_WIDTH;
typedef Bit#(ATOMIC_UPDATE_STORAGE_CHANNEL_IDX_WIDTH) AtomicUpdateStorageChannelIdx;


typedef struct {
    tRowAddr    rowAddr;
    tReq        reqData;
} AtomicUpdateStorageUpdateReq#(type tRowAddr, type tReq) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    tData       oldValue;
    tData       newValue;
} AtomicUpdateStorageUpdateResp#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tData       data;
    AtomicUpdateStorageEntryEpoch     epoch;
    AtomicUpdateStorageChannelIdx     channelIdx;
} AtomicUpdateStorageEntry#(type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    tReq        reqData;
} AtomicUpdateStorageStageOneToTwoPipelineEntry#(type tRowAddr, type tReq) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    AtomicUpdateStorageEntry#(tData) oldEntry;
    tReq        reqData;
} AtomicUpdateStorageStageTwoToThreePipelineEntry#(type tRowAddr, type tData, type tReq) deriving(Bits, FShow);

typedef struct {
    tRowAddr                            rowAddr;
    AtomicUpdateStorageEntry#(tData)    newEntry;
    Bool                                isReset;
} AtomicUpdateStorageStageThreeToFourPipelineEntry#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    AtomicUpdateStorageEntry#(tData) entry;
} AtomicUpdateStorageInternalForwardEntry#(type tRowAddr, type tData) deriving(Bits, FShow);

interface AtomicUpdateStorage#(type tRowAddr, type tData, type tReq);
    interface Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)))) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(AtomicUpdateStorageUpdateResp#(tRowAddr, tData)))) respPipeOutVec;
    
    interface PipeIn#(tRowAddr) readOnlyReqPipeIn;
    interface PipeOut#(tData)   readOnlyRespPipeOut;

    interface PipeIn#(tRowAddr) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

module mkAtomicUpdateStorage#(
        function tData updateFunc(tData oldVal, tReq reqVal),
        String initRamFileBaseName
    )(AtomicUpdateStorage#(tRowAddr, tData, tReq)) provisos (
        Bits#(tRowAddr, szRowAddr),
        Bits#(tData, szData),
        Bits#(tReq, szReq),
        Bitwise#(tData),
        Literal#(tData),
        Arith#(tData),
        Ord#(tData),
        Bounded#(tRowAddr),
        Literal#(tRowAddr),
        Eq#(tRowAddr),
        FShow#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)),
        FShow#(AtomicUpdateStorageEntry#(tData))
    );
    Vector#(NUMERIC_TYPE_TWO, PipeIn#(Maybe#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)))) reqPipeInVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(AtomicUpdateStorageUpdateResp#(tRowAddr, tData)))) respPipeOutVecInst = newVector;

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)))) reqPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AtomicUpdateStorageUpdateResp#(tRowAddr, tData)))) respPipeOutQueueVec <- replicateM(mkFIFOF);

    FIFOF#(tRowAddr) readOnlyReqPipeInQueue    <- mkFIFOF;
    FIFOF#(tData)    readOnlyRespPipeOutQueue  <- mkFIFOF;


    Vector#(NUMERIC_TYPE_TWO, Vector#(NUMERIC_TYPE_THREE, AutoInferBram#(tRowAddr, AtomicUpdateStorageEntry#(tData)))) storage = newVector;
    storage[0][0] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch0.bin");
    storage[0][1] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch0.bin");
    storage[0][2] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch0.bin");
    storage[1][0] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch1.bin");
    storage[1][1] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch1.bin");
    storage[1][2] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch1.bin");
    

    // Forward Registers (use config reg to solve rule schedule order)
    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(AtomicUpdateStorageInternalForwardEntry#(tRowAddr, tData)))) forwardRegVec <- replicateM(mkConfigReg(tagged Invalid));

    // Pipeline Queues

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AtomicUpdateStorageStageOneToTwoPipelineEntry#(tRowAddr, tReq)))) stageOneToTwoPipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AtomicUpdateStorageStageTwoToThreePipelineEntry#(tRowAddr, tData, tReq)))) stageTwoToThreePipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(AtomicUpdateStorageStageThreeToFourPipelineEntry#(tRowAddr, tData))) stageThreeToFourPipelineQueueVec <- replicateM(mkLFIFOF);

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

                let pipelineEntryOut = AtomicUpdateStorageStageOneToTwoPipelineEntry {
                    rowAddr     : pipelineEntryIn.rowAddr,
                    reqData     : pipelineEntryIn.reqData
                };
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                if (pipelineEntryIn.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkAtomicUpdateStorage 1 sendBramQueryReq", 
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

                Maybe#(AtomicUpdateStorageEntry#(tData)) forwardedRespMaybe = tagged Invalid;
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;

                    if (pipelineEntryIn.rowAddr == 4) begin
                        // $display("time=%0t", $time, "mkAtomicUpdateStorage 2 getBramQueryRespAndPreMergeThem", 
                        //         ", forwardRegVec[0]=", fshow(forwardRegVec[0])
                        // );
                    end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry &&& forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                    forwardedRespMaybe = tagged Valid forwardedEntry.entry;

                    if (pipelineEntryIn.rowAddr == 4) begin
                        // $display("time=%0t", $time, "mkAtomicUpdateStorage 2 getBramQueryRespAndPreMergeThem", 
                        //         ", forwardRegVec[1]=", fshow(forwardRegVec[1])
                        // );
                    end
                end
                
                let delta = selfResp.epoch - otherResp.epoch;

                // if forward path has data, then use the newest value from forward path.
                // else, if delta is non-negative, means `selfResp` is newer or equal to `otherResp`, so choose `selfResp`.
                let selectedResp = isValid(forwardedRespMaybe) ? fromMaybe(?, forwardedRespMaybe) : ( msb(delta) == 0 ? selfResp : otherResp);

                let pipelineEntryOut = AtomicUpdateStorageStageTwoToThreePipelineEntry {
                    rowAddr     : pipelineEntryIn.rowAddr,
                    oldEntry    : selectedResp,
                    reqData     : pipelineEntryIn.reqData
                };

                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
                if (pipelineEntryIn.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkAtomicUpdateStorage 2 getBramQueryRespAndPreMergeThem", 
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

                let newEntry = alreadyExistEntry;
                newEntry.channelIdx = fromInteger(selfChannelIdx);
                newEntry.data = updateFunc(alreadyExistEntry.data, pipelineEntryIn.reqData);
                if (newEntry.channelIdx != pipelineEntryIn.oldEntry.channelIdx || pipelineEntryIn.oldEntry.epoch == 0) begin
                    // for example, when a very big message is send on the wire, it's likely that the continous packet will from the same channel,
                    // and there will be only one valid channel per beat, which always goes into first channel, leading the other channel stall.
                    // so, we only increase epoch when the channel changes, to make sure when merging from two channels, the newest one will be selected.
                    // and the first beat is tricky, since the init epoch of every channel is 0, suppose the following case:
                    // channel 0 comes the first req, old epoch is 0, and then the second req for the same row comes from channel 1, if we didn't
                    // update the epoch to 1 in the first request, then the second request may select the wrong path as the newest entry.

                    newEntry.epoch = pipelineEntryIn.oldEntry.epoch + 1;
                end
                else begin
                    // we need this branch, because the input newEntry's epoch is a random one, it should be set to the oldEntry's
                    newEntry.epoch = pipelineEntryIn.oldEntry.epoch;
                end
                

                let forwardEntry = AtomicUpdateStorageInternalForwardEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    entry: newEntry
                };
                forwardRegVec[selfChannelIdx] <= tagged Valid forwardEntry;

                let resp = AtomicUpdateStorageUpdateResp {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldValue: alreadyExistEntry.data,
                    newValue: newEntry.data
                };
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Valid resp);

                let bramWriteBackReq = AtomicUpdateStorageStageThreeToFourPipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    newEntry: newEntry,
                    isReset: False
                };
                stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(bramWriteBackReq);

                if (pipelineEntryIn.rowAddr == 4) begin
                    // $display("time=%0t", $time, "mkAtomicUpdateStorage 3 doMerge", 
                    //         ", pipelineEntryIn=", fshow(pipelineEntryIn),
                    //         ", resp=", fshow(resp)
                    // );
                end

            end
            else begin
                forwardRegVec[selfChannelIdx] <= tagged Invalid;
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Invalid);

                // Reset is low priority.
                if (curResetReqRegVec[selfChannelIdx] matches tagged Valid .resetReqAddr) begin
                    let resetValue = AtomicUpdateStorageEntry{
                        data: 0,
                        epoch: 0,
                        channelIdx: fromInteger(selfChannelIdx)
                    };
                    let bramWriteBackReq = AtomicUpdateStorageStageThreeToFourPipelineEntry {
                        rowAddr: resetReqAddr,
                        newEntry: resetValue,
                        isReset: True
                    };
                    stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(bramWriteBackReq);
                end
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
                storage[selfChannelIdx][2].write(writeBackReq.rowAddr, writeBackReq.newEntry);

                if (writeBackReq.isReset) begin
                    curResetReqRegVec[selfChannelIdx] <= tagged Invalid;
                end

                // if (writeBackReq.rowAddr == 4) begin
                //     // $display("time=%0t", $time, "mkAtomicUpdateStorage 4 doBramWriteBack", 
                //     //         ", writeBackReq=", fshow(writeBackReq)
                //     // );
                // end
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

    rule handleReadOnlyReq;
        let addr = readOnlyReqPipeInQueue.first;
        readOnlyReqPipeInQueue.deq;
        storage[0][2].putReadReq(addr);
        storage[1][2].putReadReq(addr);
    endrule

    rule handleReadOnlyResp;
        let resp0 <- storage[0][2].getReadResp;
        let resp1 <- storage[1][2].getReadResp;
        
        let delta = resp0.epoch - resp1.epoch;

        let selectedResp = (msb(delta) == 0 ? resp0 : resp1);
        readOnlyRespPipeOutQueue.enq(selectedResp.data);
    endrule

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;

    interface readOnlyReqPipeIn     = toPipeIn(readOnlyReqPipeInQueue);
    interface readOnlyRespPipeOut   = toPipeOut(readOnlyRespPipeOutQueue);

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQ);
    interface resetRespPipeOut = toPipeOut(resetRespPipeOutQ);
endmodule