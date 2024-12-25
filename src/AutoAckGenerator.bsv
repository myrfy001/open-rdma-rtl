import RegFile :: * ;
import FIFOF :: *;
import ClientServer :: *;
import Connectable :: *;
import PAClib :: *;
import PrimUtils :: *;
import Vector :: *;
import GetPut :: *;
import Printf:: *;

import Settings :: *;
import BasicDataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import ConnectableF :: *;

import PsnContinousChecker :: *;

typedef struct {
    PSN psn;
    QPN qpn;
} AutoAckGeneratorReq deriving(Bits, FShow);

typedef struct {
    IndexQP                                                             qpnIdx;
    Bool                                                                isPacketLost;
    MSN                                                                 lastAckMsn;
    MSN                                                                 curAckMsn;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary)  oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary)  newBitmapEntry;
} AutoAckGeneratorResp deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToCpsnCounterPipelineEntry deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToMaxAckPsnCalculatorPipelineEntry deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToMaxAckPsnStoragePipelineEntry deriving(Bits, FShow);

typedef struct {
    DWord LastEntryReceiveTime;
    MSN   ackMsn;
    Bool  hasReported;
} AutoAckGenAtomicUpdateStorageEntry deriving(Bits, FShow);

interface AutoAckGenerator;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(AutoAckGeneratorResp))) respPipeOutVec;

    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVec;

    interface PipeIn#(IndexQP) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface


(* synthesize *)
module mkAutoAckGenerator(AutoAckGenerator);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(AutoAckGeneratorReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);
    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
    end

    Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(AutoAckGeneratorResp))) respPipeOutVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AutoAckGeneratorResp))) respPipeOutQueueVec <- replicateM(mkFIFOF);
    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    Vector#(NUMERIC_TYPE_TWO, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(RingbufRawDescriptor)) metaReportDescPipeOutQueueVec <- replicateM(mkFIFOF);
    
    Vector#(NUMERIC_TYPE_TWO, EthernetPacketGenerator) ethernetPacketGeneratorVec <- replicateM(mkEthernetPacketGenerator);

    QpContextTwoWayQuery  qpContextForAutoAck <- mkQpContextTwoWayQuery;

    Reg#(DWord) curTimeReg <- mkReg(0);

    function AutoAckGenAtomicUpdateStorageEntry atomicUpdateFunction(AutoAckGenAtomicUpdateStorageEntry oldVal, Bool reqVal);
        let needSendAckNow = reqVal;
        oldVal.ackMsn = needSendAckNow ? oldVal.ackMsn + 1 : oldVal.ackMsn;
        oldVal.LastEntryReceiveTime = curTimeReg;
        oldVal.hasReported = reqVal;
    endfunction

    PsnPerMergeAndStorage psnMergeAndStorage <- mkPsnPerMergeAndStorage;
    AtomicUpdateStorage#(IndexQP, AutoAckGenAtomicUpdateStorageEntry, Bool) autoAckMetaAtomicUpdateStorage <- mkAutoAckGenAtomicUpdateStorageEntry(
        atomicUpdateFunction,
        "init_bram_auto_ack_meta_storage"
    );


    let mimoCfg = MIMOConfiguration {
        unguarded: False,
        bram_based: False
    };
    Vector#(NUMERIC_TYPE_TWO, MIMO#(
        NUMERIC_TYPE_TWO,
        NUMERIC_TYPE_ONE,
        NUMERIC_TYPE_FOUR,
        RingbufRawDescriptor
    )) metaReportMimoQueueVec <- replicateM(mkMIMO(mimoCfg));

    // Pipeline Queues
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary))) sendAutoAckPipelineQueueVec <- replicateM(mkFIFOF);

    // TODO: maybe we can remove this rule
    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        rule forwardInputReqToPsnPreMerge;
            let req = reqPipeInQueueVec[idx].first;
            reqPipeInQueueVec[idx].deq;

            let preMergeReq = FourChannelPsnBitmapPreMergeReq {
                psn: req.psn,
                qpn: req.qpn
            };
            psnMergeAndStorage.reqPipeInVec[idx].enq(preMergeReq);
        endrule
    end


    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        rule handleMergedBitmap;
            let respMaybe = allPacketPsnBitmapStorage.respPipeOutVec[idx].first;
            allPacketPsnBitmapStorage.respPipeOutVec[idx].deq;

            if (respMaybe matches tagged Valid .resp) begin
                let hasPacketLost = resp.isShiftWindow && resp.windowShiftedOutData != -1;
                let needSendAckNow = hasPacketLost;
                let autoAckMetaUpdateReq = AtomicUpdateStorageUpdateReq {
                    rowAddr: resp.rowAddr,
                    reqData: needSendAckNow
                };
                autoAckMetaAtomicUpdateStorage.reqPipeInVec[idx].enq(autoAckMetaUpdateReq);
                sendAutoAckPipelineQueueVec[idx].enq(resp);
                qpContextForAutoAck.querySrvVec[idx].request.put(ReadReqQPC{
                    qpn: genQPN(resp.rowAddr, ?)
                });
            end
        endrule

        rule genAutoAckPacketAndReportDescriptor;
            let bitmapInfo = sendAutoAckPipelineQueueVec[idx].first;
            let msnInfo = autoAckMetaAtomicUpdateStorage.respPipeOutVec[idx].first;

            // write them in a function to make sure they are all comb logic.
            function Vector#(NUMERIC_TYPE_TWO, RingbufRawDescripto) genDescVector();
                
                let commonHeader = RingbufDescCommonHead {
                    valid           : True,
                    hasNextFrag     : False,
                    reserved0       : unpack(0),
                    isExtendOpcode  : False,
                    opCode          : opcode
                };


                let desc0 = MetaReportQueueAckDesc{
                    nowBitmap       : bitmapInfo.newEntry.data,
                    reserved4       : unpack(0),
                    msn             : 0,
                    reserved3       : unpack(0),         
                    psnNow          : zeroExtendLsb(bitmapInfo.newEntry.leftBound),
                    reserved2       : unpack(0),
                    psnBeforeSlide  : zeroExtendLsb(bitmapInfo.oldEntry.leftBound),
                    reserved1       : unpack(0),
                    isPacketLost    : True,
                    isWindowSlided  : aeth.isWindowSlided,
                    isSendByDriver  : False,
                    isSendByLocalHw : True,
                    reserved0       : unpack(0),
                    commonHeader    : commonHeader
                };
                desc0.commonHeader.hasNextFrag = True;

                let desc1 = MetaReportQueueAckExtraDesc{
                    preBitmap   :   bitmapInfo.oldEntry.data,
                    reserved2   :   unpack(0),
                    reserved1   :   unpack(0),
                    reserved0   :   unpack(0),
                    commonHeader:   commonHeader
                };

                return vec(pack(desc0), pack(desc1));
            endfunction


            let needSendAckNow = msnInfo.newValue.hasReported;
            if (needSendAckNow) begin
                let vecToEnq = genDescVector;
                if (metaReportMimoQueueVec[idx].enqReadyN(2)) begin
                    metaReportMimoQueueVec[idx].enq(2, vecToEnq);
                    sendAutoAckPipelineQueueVec[idx].deq;
                    autoAckMetaAtomicUpdateStorage.respPipeOutVec[idx].deq;
                end
            end
        endrule

        rule forwardMetaReportDescToOutput;
            if (metaReportMimoQueueVec[idx].deqReadyN(1)) begin
                metaReportMimoQueueVec[idx].deq(1);
                let desc = metaReportMimoQueueVec[idx].first[0];
                metaReportDescPipeOutQueueVec[idx].enq(desc);
            end
        endrule


        rule genAutoAckEthPacket;
            let qpCtxRespMaybe <- qpContextForAutoAck.querySrvVec[idx].request.get;
            if (qpCtxRespMaybe matches tagged Valid .qpCtxResp) begin
                
            end
        endrule
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;

    interface metaReportDescPipeOutVec = metaReportDescPipeOutVecInst;
    interface resetReqPipeIn = allPacketPsnBitmapStorage.resetReqPipeIn;
    interface resetRespPipeOut = allPacketPsnBitmapStorage.resetRespPipeOut;
endmodule

