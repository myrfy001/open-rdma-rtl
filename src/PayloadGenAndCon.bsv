import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;

typedef union tagged {
    IMM  Imm;
    RKEY RKey;
} ImmOrRKey deriving(Bits, FShow);

typedef struct {
    PKEY pkey;                                      // 16 bits
    WorkReqOpCode opcode;                           // 4  bits
    FlagsType#(WorkReqSendFlag) flags;              // 5  bits
    TypeQP qpType;                                  // 4  bits
    PSN psn;                                        // 24 bits
    PMTU pmtu;                                      // 3 bits
    UdpPort srcUdpPort;                             // 16 bits
    IP dqpIP;                                       // 32 bits
    MAC macAddr;                                    // 48 bits
    ADDR   laddr;                                   // 64 bits
    LKEY   lkey;                                    // 32 bits
    ADDR raddr;                                     // 64 bits
    RKEY rkey;                                      // 32 bits
    Length len;                                     // 32 bits
    QPN dqpn;                                       // 24 bits
    Maybe#(Long) comp;                              // 65 bits
    Maybe#(Long) swap;                              // 65 bits
    Maybe#(ImmOrRKey) immDtOrInvRKey;               // 34 bits
    Maybe#(QPN) srqn; // for XRC                    // 25 bits
    Maybe#(QKEY) qkey; // for UD                    // 33 bits
    Bool isFirst;                                   // 1  bit
    Bool isLast;                                    // 1  bit
} WorkQueueElem deriving(Bits);

typedef struct {
    ADDR   addr;
    Length len;
} PayloadGenReq deriving(Bits, FShow);

typedef struct {
    ADDR   addr;
    Length len;
} PayloadConReq deriving(Bits, FShow);



interface PayloadGen;
    interface PipeIn#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(DataStream) payloadGenStreamPipeOut;
endinterface

interface PayloadCon;
    interface PipeIn#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;

    interface PipeIn#(DataStream) payloadConStreamPipeIn;
endinterface



interface PayloadGenAndCon;
    interface PipeIn#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(DataStream) payloadGenStreamPipeOut;

    interface PipeIn#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;
    interface PipeIn#(DataStream) payloadConStreamPipeIn;
endinterface


module mkPayloadGenAndCon(PayloadGenAndCon);
    AcxNapSlaveWrapper dmaReadWriteSlaveNap <- mkAcxNapSlaveWrapper;

    PayloadGen payloadGen <- mkPayloadGen(dmaReadWriteSlaveNap);
    PayloadCon payloadCon <- mkPayloadCon(dmaReadWriteSlaveNap);

    interface genReqPipeIn = payloadGen.genReqPipeIn;
    interface payloadGenStreamPipeOut = payloadGen.payloadGenStreamPipeOut;

    interface conReqPipeIn = payloadCon.conReqPipeIn;
    interface conRespPipeOut = payloadCon.conRespPipeOut;
    interface payloadConStreamPipeIn = payloadCon.payloadConStreamPipeIn;
endmodule

module mkPayloadGen#(AcxNapSlaveWrapper dmaReadSlaveNap)(PayloadGen);

    FIFOF#(PayloadGenReq) genReqPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) payloadGenStreamPipeOutQ <- mkFIFOF;

    AddressChunkMetaCalculator#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForPcieBurst,
            devideLengthForPcieBurst,
            isAddrAndLengthLowerPartSumOverflowForPcieBurst,
            getChunkSizeForPcieBurst
        );
    AddressChunker#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunker <- mkAddressChunker;
    AddressChunkMetaCalculator#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForBeat,
            devideLengthForBeat,
            isAddrAndLengthLowerPartSumOverflowForBeat,
            getChunkSizeForBeat
        );
    AddressChunker#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunker <- mkAddressChunker;

    FIFOF#(AddressChunkResp#(ADDR, Length)) chunkedBurstMetaQ <- mkFIFOF;

    Reg#(Bool) outputIsFirstReg <- mkReg(True);

    mkConnection(rawReqToBurstChunkMetaCalc.metaPipeOut, rawReqToBurstChunker.requestPipeIn);


    rule handleInReq;
        let req = genReqPipeInQ.first;
        genReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: dontCareValue
        };

        rawReqToBurstChunkMetaCalc.requestPipeIn.enq(chunkReq);
    endrule

    rule getBurstChunRespAndIssueBeatChunkMetaCalculateReq;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let chunkReq = AddressChunkReq{
            startAddr: burstAddrBoundry.startAddr,
            len: burstAddrBoundry.len,
            chunk: dontCareValue
        };

        burstToBeatChunkMetaCalc.requestPipeIn.enq(chunkReq);
        chunkedBurstMetaQ.enq(burstAddrBoundry);
    endrule

    rule getBeatChunkMetaCalculateRespAndIssueAxiRead;
        let burstToBeatChunkMeta = burstToBeatChunkMetaCalc.metaPipeOut.first;
        burstToBeatChunkMetaCalc.metaPipeOut.deq;

        let ar = AxiMmNapBeatAr {
            arid: 0,
            araddr: truncate(burstToBeatChunkMeta.req.startAddr),
            arlen: unpack(truncate(burstToBeatChunkMeta.zeroBasedChunkNum)),
            arsize: unpack(pack(NapAxiSize32B)),
            arburst: unpack(pack(NapAxiBurstIncr)),
            arlock: False,
            arqos: 0
        };

        dmaReadSlaveNap.sendReadAddr(ar);
        burstToBeatChunker.requestPipeIn.enq(burstToBeatChunkMeta);
    endrule

    rule gatherAxiReadResp;
        let axiReadResp <- dmaReadSlaveNap.recvReadResp;
        let burstMeta = chunkedBurstMetaQ.first;
        let beatMeta = burstToBeatChunker.responsePipeOut.first;
        burstToBeatChunker.responsePipeOut.deq;

        Bool isLast = False;
        if (axiReadResp.rlast) begin
            immAssert(
                beatMeta.isLast,
                "beatMeta.isLast should also be true here, but it doesn't, which means our chunk algroithm is not the same as the NAP hardware",
                $format("")
            );
            chunkedBurstMetaQ.deq;
            if (burstMeta.isLast) begin
                isLast = True;
            end
        end

        outputIsFirstReg <= isLast;

        Bool isFirst = outputIsFirstReg;

        ByteEnBitNum    startByteIdx = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        ByteIndexInBeat startAddrByteOffsetInBeat = truncate(burstMeta.startAddr);
        ByteEnBitNum    byteNum = truncate(beatMeta.len);

        // TODO: maybe we can split this calculate into previous beat and this beat
        startByteIdx = isFirst ? startByteIdx - zeroExtend(startAddrByteOffsetInBeat) - byteNum : 0;

        let ds = DataStream {
            data: axiReadResp.rdata,
            byteNum: byteNum,
            startByteIdx: truncate(startByteIdx),
            isFirst: isFirst,
            isLast: isLast
        };
        ds = reverseStream(ds);

        payloadGenStreamPipeOutQ.enq(ds);
    endrule


    interface genReqPipeIn = toPipeIn(genReqPipeInQ);
    interface payloadGenStreamPipeOut = toPipeOut(payloadGenStreamPipeOutQ);

endmodule



module mkPayloadCon#(AcxNapSlaveWrapper dmaWriteSlaveNap)(PayloadCon);

    FIFOF#(PayloadConReq) conReqPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) payloadConStreamPipeInQ <- mkFIFOF;
    FIFOF#(Bool) conRespPipeOutQ <- mkFIFOF;

    AddressChunkMetaCalculator#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForPcieBurst,
            devideLengthForPcieBurst,
            isAddrAndLengthLowerPartSumOverflowForPcieBurst,
            getChunkSizeForPcieBurst
        );
    AddressChunker#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunker <- mkAddressChunker;
    AddressChunkMetaCalculator#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForBeat,
            devideLengthForBeat,
            isAddrAndLengthLowerPartSumOverflowForBeat,
            getChunkSizeForBeat
        );
    AddressChunker#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunker <- mkAddressChunker;

    

    FIFOF#(AddressChunkResp#(ADDR, Length)) chunkedBurstMetaQ <- mkFIFOF;
    FIFOF#(Tuple2#(DataStreamEn, ByteIndexInBeat)) dataStreamEnPreCalcPipelineQ <- mkFIFOF;
    FIFOF#(AddressChunkResp#(ADDR, Length)) inflightAxiWriteBurstMetaQ <- mkFIFOF; 

    mkConnection(rawReqToBurstChunkMetaCalc.metaPipeOut, rawReqToBurstChunker.requestPipeIn);

    Reg#(Bool) errorOccuredReg <- mkReg(False);

    rule handleInReq;
        let req = conReqPipeInQ.first;
        conReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: dontCareValue
        };

        rawReqToBurstChunkMetaCalc.requestPipeIn.enq(chunkReq);
    endrule

    rule getBurstChunRespAndIssueBeatChunkMetaCalculateReq;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let chunkReq = AddressChunkReq{
            startAddr: burstAddrBoundry.startAddr,
            len: burstAddrBoundry.len,
            chunk: dontCareValue
        };

        burstToBeatChunkMetaCalc.requestPipeIn.enq(chunkReq);
        chunkedBurstMetaQ.enq(burstAddrBoundry);
    endrule

    rule getBeatChunkMetaCalculateRespAndIssueAxiRead;
        let burstToBeatChunkMeta = burstToBeatChunkMetaCalc.metaPipeOut.first;
        burstToBeatChunkMetaCalc.metaPipeOut.deq;

        let burstAddrBoundry = chunkedBurstMetaQ.first;
        chunkedBurstMetaQ.deq;

        let awReq = AxiMmNapBeatAw {
            awid: 0,
            awaddr: truncate(burstAddrBoundry.startAddr),
            awlen: unpack(truncate(burstToBeatChunkMeta.zeroBasedChunkNum)),
            awsize: unpack(pack(NapAxiSize32B)),
            awburst: unpack(pack(NapAxiBurstIncr)),
            awlock: False,
            awqos: 0
        };
        dmaWriteSlaveNap.sendWriteAddr(awReq);
        burstToBeatChunker.requestPipeIn.enq(burstToBeatChunkMeta);
        inflightAxiWriteBurstMetaQ.enq(burstAddrBoundry);
    endrule


    rule preCalcWriteStreamByteEn;
        let ds = payloadConStreamPipeInQ.first;
        payloadConStreamPipeInQ.deq;
        ByteEn allOneByteEn = -1;
        ByteEn allZeroByteEn = 0;
        ByteEn byteEn = truncate({allOneByteEn, allZeroByteEn} >> ds.byteNum);

        let dsEn = DataStreamEn {
            data: ds.data,
            byteEn: byteEn,
            isFirst: ds.isFirst,
            isLast: ds.isLast
        };
        dataStreamEnPreCalcPipelineQ.enq(tuple2(dsEn, ds.startByteIdx));
    endrule

    rule sendAxiWriteBeat;
        let beatInfo = burstToBeatChunker.responsePipeOut.first;
        burstToBeatChunker.responsePipeOut.deq;

        let {dsEn, startByteIdx} = dataStreamEnPreCalcPipelineQ.first;
        dataStreamEnPreCalcPipelineQ.deq;

        // Note: the following lines complete the byteEN generation. Those lines of code should 
        // be placed in the `rule preCalcWriteStreamByteEn`, but the shift timing is worse.
        // to fix timing, split the byteEn generation into this rule and `rule preCalcWriteStreamByteEn`
        dsEn.byteEn = dsEn.byteEn >> startByteIdx;
        if (dsEn.isFirst) begin
            // since only first beat in the stream is right aligned
            dsEn.byteEn = swapEndianBit(dsEn.byteEn);
        end


        dsEn = reverseStreamEnAndData(dsEn);

        let wlast = beatInfo.isLast;

        let wReq = AxiMmNapBeatW {
            wdata: dsEn.data,
            wstrb: dsEn.byteEn,
            wlast: wlast
        };
        dmaWriteSlaveNap.sendWriteData(wReq);

        if (dsEn.isLast) begin
            immAssert(
                wlast,
                "wlast should also be true here, but it doesn't, which means the chunk calculated from address and len doesn't match the received stream",
                $format("")
            );
        end
    endrule

    rule forwardAxiB;
        let resp <- dmaWriteSlaveNap.recvWriteResp;
        let burstMeta = inflightAxiWriteBurstMetaQ.first;
        inflightAxiWriteBurstMetaQ.deq;

        let errorOccured = errorOccuredReg || (resp.bresp != 0);
        if (burstMeta.isLast) begin
            conRespPipeOutQ.enq(!errorOccured);
            errorOccuredReg <= False;
        end
        else begin
            errorOccuredReg <= errorOccured;
        end
    endrule

    interface conReqPipeIn = toPipeIn(conReqPipeInQ);
    interface conRespPipeOut = toPipeOut(conRespPipeOutQ);
    interface payloadConStreamPipeIn = toPipeIn(payloadConStreamPipeInQ);

endmodule