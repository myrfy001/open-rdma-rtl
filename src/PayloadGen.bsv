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

    AddressChunker#(
        ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
        TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
    ) burstChunker <- mkAddressChunker(
        alignAddrForPcieBurst,
        devideLengthForPcieBurst,
        isAddrAndLengthLowerPartSumOverflowForPcieBurst,
        getChunkSizeForPcieBurst
    );

    AcxNapSlaveWrapper dmaReadSlaveNap <- mkAcxNapSlaveWrapper;

    rule handleInReq;
        let req = reqPipeInQ.first;
        reqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: dontCareValue
        };

        burstChunker.requestPipeIn.enq(chunkReq);
    endrule

    rule chunkRespToAxiBurst;
        // let chunkResp = burstChunker.
    endrule

    rule t;

        let ar = AxiMmNapBeatAr {
            arid: 0,
            araddr: ?,
            arlen: ?,
            arsize: ?,
            arburst: ?,
            arlock: False,
            arqos: ?
        };


        dmaReadSlaveNap.sendReadAddr(ar);
    endrule


    interface reqPipeIn = toPipeIn(reqPipeInQ);
    interface payloadStreamPipeOut = toPipeOut(payloadStreamPipeOutQ);

endmodule