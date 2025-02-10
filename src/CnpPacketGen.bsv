import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;

import Settings :: *;
import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import AddressChunker :: *;
import RdmaHeaders :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import Ringbuf :: *;
import Descriptors :: *;
import EthernetTypes :: *;
import EthernetFrameIO512 :: *;

typedef struct {
    ThinMacIpUdpMetaDataForRecv peerAddrInfo;
    QPN                         peerQpn;
    MSN                         peerMsn;
    UdpPort                     localUdpPort;
} CnpPacketGenReq deriving(Bits, FShow);

interface CnpPacketGenerator;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeInB0#(CnpPacketGenReq)) genReqPipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(IoChannelEthDataStream)) cnpEthPacketPipeOutVec;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
endinterface

(* synthesize *)
module mkCnpPacketGenerator(CnpPacketGenerator);
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeInAdapterB0#(CnpPacketGenReq)) genReqPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeInB0#(CnpPacketGenReq)) genReqPipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(IoChannelEthDataStream)) cnpEthPacketPipeOutVecInst = newVector;

    Vector#(HARDWARE_QP_CHANNEL_CNT, EthernetPacketGenerator) ethernetPacketGeneratorVec <- replicateM(mkEthernetPacketGenerator);

    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(ThinMacIpUdpMetaDataForSend)) ethernetPacketGeneratorMacIpUdpMetaPipeInAdapterVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(RdmaSendPacketMeta)) ethernetPacketGeneratorRdmaPacketMetaPipeInAdapterVec = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        genReqPipeInVecInst[idx] = toPipeInB0(genReqPipeInQueueVec[idx]);
        cnpEthPacketPipeOutVecInst[idx] = ethernetPacketGeneratorVec[idx].ethernetPacketPipeOut;
        ethernetPacketGeneratorMacIpUdpMetaPipeInAdapterVec[idx] <- mkPipeInB0ToPipeIn(ethernetPacketGeneratorVec[idx].macIpUdpMetaPipeIn, 4); 
        ethernetPacketGeneratorRdmaPacketMetaPipeInAdapterVec[idx] <- mkPipeInB0ToPipeIn(ethernetPacketGeneratorVec[idx].rdmaPacketMetaPipeIn, 4); 
    end

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        rule genPacket;
            let req = genReqPipeInQueueVec[idx].first;
            genReqPipeInQueueVec[idx].deq;

            let thinMacIpUdpMetaDataForSend = ThinMacIpUdpMetaDataForSend {
                dstMacAddr      : req.peerAddrInfo.srcMacAddr,
                ipDscp          : 0,
                ipEcn           : pack(IpHeaderEcnFlagEnabled),
                dstIpAddr       : req.peerAddrInfo.srcIpAddr,
                srcPort         : req.localUdpPort,
                dstPort         : fromInteger(valueOf(UDP_PORT_RDMA)),
                udpPayloadLen   : fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM)),
                ethType         : fromInteger(valueOf(ETH_TYPE_IP))
            };

            let rdmaSendPacketMeta = RdmaSendPacketMeta {
                header:RdmaBthAndExtendHeader{
                    bth: BTH {
                        trans    : TRANS_TYPE_CNP,
                        opcode   : unpack(0),
                        solicited: False,
                        isRetry  : False,
                        padCnt   : unpack(0),
                        tver     : unpack(0),
                        msn      : req.peerMsn,
                        fecn     : unpack(0),
                        becn     : unpack(0),
                        resv6    : unpack(0),
                        dqpn     : req.peerQpn,
                        ackReq   : False,
                        resv7    : unpack(0),
                        psn      : unpack(0)
                    },
                    rdmaExtendHeaderBuf: unpack(0)
                },
                hasPayload: False
            };
            ethernetPacketGeneratorMacIpUdpMetaPipeInAdapterVec[idx].enq(thinMacIpUdpMetaDataForSend);
            ethernetPacketGeneratorRdmaPacketMetaPipeInAdapterVec[idx].enq(rdmaSendPacketMeta);
        endrule
    end

    interface genReqPipeInVec = genReqPipeInVecInst;
    interface cnpEthPacketPipeOutVec = cnpEthPacketPipeOutVecInst;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            ethernetPacketGeneratorVec[idx].setLocalNetworkSettings(networkSettings);
        end
    endmethod

    
endmodule