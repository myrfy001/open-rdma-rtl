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

interface PayloadGen;
    interface PipeIn#(PayloadGenReq) reqPipeIn;
    interface PipeOut#(DataStream) payloadStreamPipeOut;
endinterface


module mkPayloadGen(PayloadGen);

    FIFOF#(PayloadGenReq) reqPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) payloadStreamPipeOutQ <- mkFIFOF;

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

    AcxNapSlaveWrapper dmaReadSlaveNap <- mkAcxNapSlaveWrapper;

    FIFOF#(AddressChunkResp#(ADDR, Length)) chunkedBurstMetaQ <- mkFIFOF;

    Reg#(Bool) outputIsFirstReg <- mkReg(True);

    mkConnection(rawReqToBurstChunkMetaCalc.metaPipeOut, rawReqToBurstChunker.requestPipeIn);


    rule handleInReq;
        let req = reqPipeInQ.first;
        reqPipeInQ.deq;

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

        $display(fshow(ds));
        // payloadStreamPipeOutQ.enq(ds);
    endrule


    interface reqPipeIn = toPipeIn(reqPipeInQ);
    interface payloadStreamPipeOut = toPipeOut(payloadStreamPipeOutQ);

endmodule