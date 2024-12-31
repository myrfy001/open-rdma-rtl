import RegFile :: * ;
import FIFOF :: *;
import ClientServer :: *;
import Connectable :: *;
import PAClib :: *;
import PrimUtils :: *;
import Vector :: *;
import BuildVector :: *;
import GetPut :: *;
import Printf:: *;
import MIMO :: *;

import Settings :: *;
import BasicDataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;
import Ringbuf :: *;
import Descriptors :: *;
import EthernetTypes :: *;
import EthernetFrameIO :: *;
import QPContext :: *;
import IoChannels :: *;

import ConnectableF :: *;

import PsnContinousChecker :: *;

typedef struct {
    PSN psn;
    QPN qpn;
} AutoAckGeneratorReq deriving(Bits, FShow);

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
    Dword lastEntryReceiveTime;
    MSN   ackMsn;
    Bool  hasReported;
} AutoAckGenAtomicUpdateStorageEntry deriving(Bits, FShow);

typedef 10000 AUTO_ACK_POLLING_TIMEOUT_TICKS;

interface AutoAckGenerator;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(IoChannelEthDataStream))     ackEthPacketPipeOutVec;

    interface Vector#(NUMERIC_TYPE_THREE, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVec;

    interface Server#(WriteReqQPC, Bool) qpcUpdateSrv;

    interface PipeIn#(IndexQP) resetReqPipeIn;
    // interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface


(* synthesize *)
module mkAutoAckGenerator(AutoAckGenerator);

    FIFOF#(IndexQP) resetReqPipeInQueue <- mkFIFOF;

    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(AutoAckGeneratorReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);

    Vector#(NUMERIC_TYPE_TWO, PipeOut#(IoChannelEthDataStream)) ackEthPacketPipeOutVecInst = newVector;

    Vector#(NUMERIC_TYPE_THREE, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVecInst = newVector;
    Vector#(NUMERIC_TYPE_THREE, FIFOF#(RingbufRawDescriptor)) metaReportDescPipeOutQueueVec <- replicateM(mkFIFOF);

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_THREE); idx = idx + 1) begin
        metaReportDescPipeOutVecInst[idx] = toPipeOut(metaReportDescPipeOutQueueVec[idx]);
    end

    Vector#(NUMERIC_TYPE_TWO, EthernetPacketGenerator) ethernetPacketGeneratorVec <- replicateM(mkEthernetPacketGenerator);

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        ackEthPacketPipeOutVecInst[idx] = ethernetPacketGeneratorVec[idx].ethernetPacketPipeOut; 
    end

    QpContextTwoWayQuery  qpContextForAutoAck <- mkQpContextTwoWayQuery;

    Reg#(Dword) curTimeReg <- mkReg(0);
    Reg#(IndexQP) pollingQpIdxReg <- mkReg(0);

    AutoInferBram#(IndexQP, Dword) lastReportTimeStorage <- mkAutoInferBramUG(True, "init_bram_auto_ack_last_report_time.bin");

    function AutoAckGenAtomicUpdateStorageEntry atomicUpdateFunction(AutoAckGenAtomicUpdateStorageEntry oldVal, Bool reqVal);
        let needSendAckNow = reqVal;
        oldVal.ackMsn = needSendAckNow ? oldVal.ackMsn + 1 : oldVal.ackMsn;
        oldVal.lastEntryReceiveTime = curTimeReg;
        oldVal.hasReported = reqVal;
        return oldVal;
    endfunction

    PsnPerMergeAndStorage psnMergeAndStorage <- mkPsnPerMergeAndStorage;
    AtomicUpdateStorage#(IndexQP, AutoAckGenAtomicUpdateStorageEntry, Bool) autoAckMetaAtomicUpdateStorage <- mkAtomicUpdateStorage(
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
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary))) genAutoAckReportDescriptorPipelineQueueVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary))) genAutoAckEthPacketPipelineQueueVec <- replicateM(mkFIFOF);

    Reg#(Bool) isSendPollReqReg <- mkReg(True);

    rule timerTask;
        curTimeReg <= curTimeReg + 1;
    endrule

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
            let respMaybe = psnMergeAndStorage.respPipeOutVec[idx].first;
            psnMergeAndStorage.respPipeOutVec[idx].deq;

            if (respMaybe matches tagged Valid .resp) begin
                let hasPacketLost = resp.isShiftWindow && resp.windowShiftedOutData != -1;
                let needSendAckNow = hasPacketLost;
                let autoAckMetaUpdateReq = AtomicUpdateStorageUpdateReq {
                    rowAddr: resp.rowAddr,
                    reqData: needSendAckNow
                };
                autoAckMetaAtomicUpdateStorage.reqPipeInVec[idx].enq(tagged Valid autoAckMetaUpdateReq);
                genAutoAckEthPacketPipelineQueueVec[idx].enq(resp);
                qpContextForAutoAck.querySrvVec[idx].request.put(ReadReqQPC{
                    qpn: genQPN(resp.rowAddr, ?)
                });
            end
            else begin
                autoAckMetaAtomicUpdateStorage.reqPipeInVec[idx].enq(tagged Invalid);
            end
        endrule

        rule genAutoAckEthPacket;

            let msnInfoMaybe = autoAckMetaAtomicUpdateStorage.respPipeOutVec[idx].first;
            autoAckMetaAtomicUpdateStorage.respPipeOutVec[idx].deq;

            if (msnInfoMaybe matches tagged Valid .msnInfo) begin
                let qpCtxRespMaybe <- qpContextForAutoAck.querySrvVec[idx].response.get;
                let bitmapInfo = genAutoAckEthPacketPipelineQueueVec[idx].first;
                genAutoAckEthPacketPipelineQueueVec[idx].deq;

                let needSendAckNow = msnInfo.newValue.hasReported;
                let isPacketLost = needSendAckNow;

                if (needSendAckNow) begin
                    if (qpCtxRespMaybe matches tagged Valid .qpCtxResp) begin
                        let thinMacIpUdpMetaDataForSend = ThinMacIpUdpMetaDataForSend {
                            dstMacAddr: qpCtxResp.peerMacAddr,
                            ipDscp: 0,
                            ipEcn: 0,
                            dstIpAddr: qpCtxResp.peerIpAddr,
                            srcPort: qpCtxResp.localUdpPort,
                            dstPort: fromInteger(valueOf(UDP_PORT_RDMA)),
                            udpPayloadLen: fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM)),
                            ethType: fromInteger(valueOf(ETH_TYPE_IP))
                        };

                        let rdmaSendPacketMeta = RdmaSendPacketMeta {
                            header:RdmaBthAndExtendHeader{
                                bth: BTH {
                                    trans    : TRANS_TYPE_RC,
                                    opcode   : ACKNOWLEDGE,
                                    solicited: False,
                                    isRetry  : False,
                                    padCnt   : unpack(0),
                                    tver     : unpack(0),
                                    msn      : msnInfo.newValue.ackMsn,
                                    fecn     : unpack(0),
                                    becn     : unpack(0),
                                    resv6    : unpack(0),
                                    dqpn     : qpCtxResp.peerQPN,
                                    ackReq   : False,
                                    resv7    : unpack(0),
                                    psn      : zeroExtendLSB(bitmapInfo.newEntry.leftBound)
                                },
                                rdmaExtendHeaderBuf: buildRdmaExtendHeaderBuffer(pack(AETH{
                                        preBitmap:  bitmapInfo.oldEntry.data,
                                        newBitmap:  bitmapInfo.newEntry.data,
                                        isPacketLost: True,
                                        isWindowSlided: True,
                                        isSendByDriver: False,
                                        resv0: unpack(0),
                                        preBitmapPsn: zeroExtendLSB(bitmapInfo.oldEntry.leftBound)
                                    }))
                            },
                            hasPayload: False
                        };
                        ethernetPacketGeneratorVec[idx].macIpUdpMetaPipeIn.enq(thinMacIpUdpMetaDataForSend);
                        ethernetPacketGeneratorVec[idx].rdmaPacketMetaPipeIn.enq(rdmaSendPacketMeta);

                        genAutoAckReportDescriptorPipelineQueueVec[idx].enq(bitmapInfo);
                    end
                end
            end
        endrule


        rule genAutoAckReportDescriptor;
            let bitmapInfo = genAutoAckReportDescriptorPipelineQueueVec[idx].first;
            

            // write them in a function to make sure they are all comb logic.
            function Vector#(NUMERIC_TYPE_TWO, RingbufRawDescriptor) genDescVector();
                
                let commonHeader = RingbufDescCommonHead {
                    valid           : True,
                    hasNextFrag     : False,
                    reserved0       : unpack(0),
                    isExtendOpcode  : False,
                    opCode          : {pack(TRANS_TYPE_RC), pack(ACKNOWLEDGE)}
                };


                let desc0 = MetaReportQueueAckDesc{
                    nowBitmap       : bitmapInfo.newEntry.data,
                    reserved4       : unpack(0),
                    msn             : 0,
                    reserved3       : unpack(0),         
                    psnNow          : zeroExtendLSB(bitmapInfo.newEntry.leftBound),
                    reserved2       : unpack(0),
                    psnBeforeSlide  : zeroExtendLSB(bitmapInfo.oldEntry.leftBound),
                    reserved1       : unpack(0),
                    isPacketLost    : True,
                    isWindowSlided  : True,
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

            let vecToEnq = genDescVector;
            if (metaReportMimoQueueVec[idx].enqReadyN(2)) begin
                metaReportMimoQueueVec[idx].enq(2, vecToEnq);
                genAutoAckReportDescriptorPipelineQueueVec[idx].deq;
            end
           
        endrule

        rule forwardMetaReportDescToOutput;
            if (metaReportMimoQueueVec[idx].deqReadyN(1)) begin
                metaReportMimoQueueVec[idx].deq(1);
                let desc = metaReportMimoQueueVec[idx].first[0];
                metaReportDescPipeOutQueueVec[idx].enq(desc);
            end
        endrule

    end


    rule pollingTask if (isSendPollReqReg);
        psnMergeAndStorage.readOnlyReqPipeIn.enq(pollingQpIdxReg);
        autoAckMetaAtomicUpdateStorage.readOnlyReqPipeIn.enq(pollingQpIdxReg);
        lastReportTimeStorage.putReadReq(pollingQpIdxReg);
        pollingQpIdxReg <= pollingQpIdxReg + 1;
        isSendPollReqReg <= False;
    endrule

    rule handlePollingResult if (!isSendPollReqReg);
        let bitmapInfo = psnMergeAndStorage.readOnlyRespPipeOut.first;
        let ackMeta = autoAckMetaAtomicUpdateStorage.readOnlyRespPipeOut.first;
        let lastPollInfo <- lastReportTimeStorage.getReadResp;
        psnMergeAndStorage.readOnlyRespPipeOut.deq;
        autoAckMetaAtomicUpdateStorage.readOnlyRespPipeOut.deq;
        isSendPollReqReg <= True;

        if (!ackMeta.hasReported) begin
            if (lastPollInfo - ackMeta.lastEntryReceiveTime > fromInteger(valueOf(AUTO_ACK_POLLING_TIMEOUT_TICKS))) begin
                let commonHeader = RingbufDescCommonHead {
                    valid           : True,
                    hasNextFrag     : False,
                    reserved0       : unpack(0),
                    isExtendOpcode  : False,
                    opCode          : {pack(TRANS_TYPE_CNP), pack(ACKNOWLEDGE)}
                };

                let desc0 = MetaReportQueueAckDesc{
                    nowBitmap       : bitmapInfo.data,
                    reserved4       : unpack(0),
                    msn             : 0,
                    reserved3       : unpack(0),         
                    psnNow          : zeroExtendLSB(bitmapInfo.leftBound),
                    reserved2       : unpack(0),
                    psnBeforeSlide  : unpack(0), // don't care since isWindowSlided = False
                    reserved1       : unpack(0),
                    isPacketLost    : False,
                    isWindowSlided  : False,
                    isSendByDriver  : False,
                    isSendByLocalHw : True,
                    reserved0       : unpack(0),
                    commonHeader    : commonHeader
                };
                metaReportDescPipeOutQueueVec[2].enq(pack(desc0));
                lastReportTimeStorage.write(pollingQpIdxReg, ackMeta.lastEntryReceiveTime);
            end
        end
        else begin
            lastReportTimeStorage.write(pollingQpIdxReg, ackMeta.lastEntryReceiveTime);
        end
    endrule

    rule forwardQpResetSignal;
        let req = resetReqPipeInQueue.first;
        resetReqPipeInQueue.deq;
        psnMergeAndStorage.resetReqPipeIn.enq(req);
        autoAckMetaAtomicUpdateStorage.resetReqPipeIn.enq(req);
    endrule

    interface reqPipeInVec = reqPipeInVecInst;
    interface ackEthPacketPipeOutVec = ackEthPacketPipeOutVecInst;

    interface qpcUpdateSrv = qpContextForAutoAck.updateSrv;

    interface metaReportDescPipeOutVec = metaReportDescPipeOutVecInst;

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQueue);
    // interface resetRespPipeOut = allPacketPsnBitmapStorage.resetRespPipeOut;
endmodule

