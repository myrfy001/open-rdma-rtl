import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 

import Utils4Test :: *;
import EthernetTypes :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import EthernetFrameIO :: *;



(* doc = "testcase" *)
module mkTestInputPacketClassifier(Empty);
    let packetGen <- mkEthernetPacketGenerator;
    let packetCon <- mkRdmaHeaderExtractor;
    let packetClassifier <- mkInputPacketClassifier;

    mkConnection(packetGen.ethernetPacketPipeOut, packetClassifier.ethRawPacketPipeIn);

    Integer     normalPacketUdpPortForTest = 1234;
    IpAddr      ipAddrForTest = unpack('h11223344);
    EthMacAddr  macUnicastAddrForTest = unpack('hFFFFFFFFFFFF);
    EthMacAddr  macBroadcastAddrForTest = unpack('h123456789ABC);


    
    let macAddrVec = vec(macUnicastAddrForTest, macBroadcastAddrForTest, macUnicastAddrForTest, macBroadcastAddrForTest);
    Vector#(9, RdmaTransAndOpcode) rdmaOpcodeVec = vec(
        unpack(fromInteger(valueOf(RC_SEND_FIRST))),                          // 12
        unpack(fromInteger(valueOf(RC_SEND_LAST_WITH_IMMEDIATE))),            // 16
        unpack(fromInteger(valueOf(RC_ACKNOWLEDGE))),                         // 20
        unpack(fromInteger(valueOf(UD_SEND_ONLY_WITH_IMMEDIATE))),            // 24
        unpack(fromInteger(valueOf(RC_RDMA_WRITE_FIRST))),                    // 28
        unpack(fromInteger(valueOf(RC_RDMA_WRITE_LAST_WITH_IMMEDIATE))),      // 32
        unpack(fromInteger(valueOf(XRC_RDMA_WRITE_ONLY_WITH_IMMEDIATE))),     // 36
        unpack(fromInteger(valueOf(RC_COMPARE_SWAP))),                        // 40
        unpack(fromInteger(valueOf(RC_RDMA_READ_REQUEST)))                    // 44
    );

    let trueFalseVec = vec(True, False, True, False);

    PipeOut#(Length) rdmaPayloadLenRandPipeOut <- mkRandomLenPipeOut(1, fromInteger(valueOf(MAX_PMTU)));
    PipeOut#(RdmaTransAndOpcode) transAndOpecodeRandPipeOut <- mkRandomItemFromVec(rdmaOpcodeVec);
    PipeOut#(Bool) hasPayloadRandPipeOut <- mkRandomItemFromVec(trueFalseVec);
    PipeOut#(Bool) isRdmaPacketRandPipeOut <- mkRandomItemFromVec(trueFalseVec);
    PipeOut#(EthMacAddr) macAddrRandPipeOut <- mkRandomItemFromVec(macAddrVec);
    PipeOut#(RdmaExtendHeaderBuffer) extendHeaderBufferRandPipeOut <- mkGenericRandomPipeOut;

    FIFOF#(ThinMacIpUdpMetaDataForSend) rdmaPacketCheckerExpectedQ <- mkFIFOF;
    FIFOF#(ThinMacIpUdpMetaDataForSend) normalPacketCheckerExpectedQ <- mkFIFOF;

    FIFOF#(Tuple2#(RdmaBthAndEthTotalLength, PktLen)) payloadGenReqQ <- mkFIFOF;



    rule genRandomPacketHeader;
        ThinMacIpUdpMetaDataForSend macIpUdpMeta = unpack(0);

        let isRdmaPacket = isRdmaPacketRandPipeOut.first;
        isRdmaPacketRandPipeOut.deq;
        let hasPayload = hasPayloadRandPipeOut.first;
        hasPayloadRandPipeOut.deq;
        PktLen rdmaPayloadLen = truncate(rdmaPayloadLenRandPipeOut.first);
        rdmaPayloadLenRandPipeOut.deq;
        let transAndOpecode = transAndOpecodeRandPipeOut.first;
        transAndOpecodeRandPipeOut.deq;
        let macAddr = macAddrRandPipeOut.first;
        macAddrRandPipeOut.deq;
        let rdmaExtendHeaderBuf = extendHeaderBufferRandPipeOut.first;
        extendHeaderBufferRandPipeOut.deq;

        RdmaBthAndEthTotalLength bthAndEthTotalLength = fromInteger(
            calcHeaderLenByTransTypeAndRdmaOpCode(transAndOpecode.trans, transAndOpecode.opcode)
        );
        
        macIpUdpMeta.dstMacAddr = macAddr;
        macIpUdpMeta.dstIpAddr = ipAddrForTest;

        if (isRdmaPacket) begin
            macIpUdpMeta.dstPort = fromInteger(valueOf(UDP_PORT_RDMA));
            macIpUdpMeta.ethType = fromInteger(valueOf(ETH_TYPE_IP));
            macIpUdpMeta.udpPayloadLen = unpack(zeroExtend(bthAndEthTotalLength));
            if (hasPayload) begin
                macIpUdpMeta.udpPayloadLen = macIpUdpMeta.udpPayloadLen + zeroExtend(rdmaPayloadLen);
            end
            rdmaPacketCheckerExpectedQ.enq(macIpUdpMeta);
        end
        else begin
            macIpUdpMeta.udpPayloadLen = zeroExtend(rdmaPayloadLen);
            macIpUdpMeta.dstPort = fromInteger(normalPacketUdpPortForTest);
            normalPacketCheckerExpectedQ.enq(macIpUdpMeta);
        end
        packetGen.macIpUdpMetaPipeIn.enq(macIpUdpMeta);

        if (isRdmaPacket) begin
            let rdmaExtendHeaderByteNum = bthAndEthTotalLength - fromInteger(valueOf(BTH_BYTE_WIDTH));
            let rdmaExtendHeaderBufInvalidByteNum = fromInteger(valueOf(RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH)) - rdmaExtendHeaderByteNum;
            RdmaExtendHeaderBuffer rdmaExtendHeaderMask = (1 << rdmaExtendHeaderBufInvalidByteNum) - 1;
            rdmaExtendHeaderBuf = rdmaExtendHeaderBuf & rdmaExtendHeaderMask;
            
            BTH bth = unpack(0);
            bth.trans = transAndOpecode.trans;
            bth.opcode = transAndOpecode.opcode;
            let rdmaBthAndExtendHeader = RdmaBthAndExtendHeader{
                bth: bth,
                rdmaExtendHeaderBuf: rdmaExtendHeaderBuf
            };
            let rdmaPacketMeta = RdmaSendPacketMeta{
                header: rdmaBthAndExtendHeader,
                bthAndEthTotalLength: bthAndEthTotalLength,
                hasPayload: hasPayload
            };
            if (hasPayload) begin
                payloadGenReqQ.enq(tuple2(bthAndEthTotalLength, rdmaPayloadLen));
            end
            packetGen.rdmaPacketMetaPipeIn.enq(rdmaPacketMeta);
        end
    endrule

    rule genRandomPayloadFirstBeat;
        let {bthAndEthTotalLength, rdmaPayloadLen} = payloadGenReqQ.first;
        payloadGenReqQ.deq;
        packetGen.rdmaPayloadPipeIn.enq(DataStream{
            data: -1,
            byteNum: -1,
            startByteIdx: 0,
            isFirst: True,
            isLast: True
        });
    endrule

endmodule