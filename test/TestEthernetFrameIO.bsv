import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 

import PrimUtils :: *;

import Utils4Test :: *;
import EthernetTypes :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import EthernetFrameIO :: *;
import StreamShifter :: *;

typedef enum {
    TestInputPacketClassifierStateGenReq = 0,
    TestInputPacketClassifierStateCheckPacketClassifierOutput = 1,
    TestInputPacketClassifierStateCheckRdmaHeaderExtractorOutput = 2
} TestInputPacketClassifierState deriving(Bits, FShow, Eq);

(* doc = "testcase" *)
module mkTestInputPacketClassifier(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(1000000);

    Reg#(TestInputPacketClassifierState) stateReg <- mkReg(TestInputPacketClassifierStateGenReq);

    let packetGen <- mkEthernetPacketGenerator;
    let packetCon <- mkRdmaHeaderExtractor;
    let packetClassifier <- mkInputPacketClassifier;



    mkConnection(packetGen.ethernetPacketPipeOut, packetClassifier.ethRawPacketPipeIn);
    mkConnection(packetClassifier.rdmaRawPacketPipeOut, packetCon.ethPipeIn);

    Integer     normalPacketUdpPortForTest = 1234;
    IpAddr      ipAddrForTestSendNode = unpack('h11223344);
    IpAddr      ipAddrForTestRecvNode = unpack('h55667788);
    EthMacAddr  macUnicastAddrForTestSendNode = unpack('h123456789ABC);
    EthMacAddr  macUnicastAddrForTestRecvNode = unpack('hDDEEFFAABBCC);
    EthMacAddr  macBroadcastAddrForTest = unpack('hFFFFFFFFFFFF);


    
    let macAddrVec = vec(macUnicastAddrForTestRecvNode, macBroadcastAddrForTest, macUnicastAddrForTestRecvNode, macBroadcastAddrForTest);
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

    PipeOut#(Length) rdmaPayloadLenRandPipeOut <- mkRandomLenPipeOut(1, 256);//fromInteger(valueOf(MAX_PMTU)));
    PipeOut#(RdmaTransAndOpcode) transAndOpecodeRandPipeOut <- mkRandomItemFromVec(rdmaOpcodeVec);
    PipeOut#(Bool) isRdmaPacketRandPipeOut <- mkRandomItemFromVec(trueFalseVec);
    PipeOut#(EthMacAddr) macAddrRandPipeOut <- mkRandomItemFromVec(macAddrVec);
    PipeOut#(RdmaExtendHeaderBuffer) extendHeaderBufferRandPipeOut <- mkGenericRandomPipeOut;

    FIFOF#(ThinMacIpUdpMetaDataForSend) rdmaMacIpUspMetadataCheckerExpectedQ <- mkFIFOF;
    FIFOF#(ThinMacIpUdpMetaDataForSend) normalPacketCheckerExpectedQ <- mkFIFOF;

    FIFOF#(RdmaRecvPacketMeta) rdmaHeaderExtractorMetaExpectedQ <- mkFIFOF;
    FIFOF#(DataStream) rdmaHeaderExtractorPayloadExpectedQ <- mkFIFOF;

    FIFOF#(Tuple2#(RdmaBthAndEthTotalLength, PktLen)) payloadGenReqQ <- mkFIFOF;

    let payloadStreamGen <- mkFixedLengthDateStreamRandomGen;
    let txStreamShifter <- mkBiDirectionStreamShifter;
    mkConnection(payloadStreamGen.streamPipeOut, txStreamShifter.streamPipeIn);
    Vector#(2, PipeOut#(DataStream)) rdmaPayloadDataStreamPipeOutForkedVec <- mkForkVector(txStreamShifter.streamPipeOut);
    mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[0], packetGen.rdmaPayloadPipeIn);
    mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[1], toPipeIn(rdmaHeaderExtractorPayloadExpectedQ));

    Reg#(RdmaRecvPacketMeta) curRecvPacketMetaDataReg <- mkRegU;

    rule genRandomPacketHeader if (stateReg == TestInputPacketClassifierStateGenReq);
        
        ThinMacIpUdpMetaDataForSend macIpUdpMeta = unpack(0);

        let isRdmaPacket = isRdmaPacketRandPipeOut.first;
        isRdmaPacketRandPipeOut.deq;
        isRdmaPacket = True;

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

        let hasPayload = rdmaOpCodeHasPayload(transAndOpecode.opcode);
        
        macIpUdpMeta.dstMacAddr = macAddr;
        macIpUdpMeta.dstIpAddr = ipAddrForTestRecvNode;

        let localNetworkSettingsForSendNode = LocalNetworkSettings{
            macAddr: macUnicastAddrForTestSendNode,
            ipAddr: ipAddrForTestSendNode,
            gatewayAddr: unpack(0),
            netMask: unpack(0)
        };
        packetGen.setMacAndIp(localNetworkSettingsForSendNode);

        let localNetworkSettingsForRecvNode = LocalNetworkSettings{
            macAddr: macUnicastAddrForTestRecvNode,
            ipAddr: ipAddrForTestRecvNode,
            gatewayAddr: unpack(0),
            netMask: unpack(0)
        };
        packetClassifier.setMacAndIp(localNetworkSettingsForRecvNode);

        if (isRdmaPacket) begin
            macIpUdpMeta.dstPort = fromInteger(valueOf(UDP_PORT_RDMA));
            macIpUdpMeta.ethType = fromInteger(valueOf(ETH_TYPE_IP));
            macIpUdpMeta.udpPayloadLen = unpack(zeroExtend(bthAndEthTotalLength));
            if (hasPayload) begin
                macIpUdpMeta.udpPayloadLen = macIpUdpMeta.udpPayloadLen + zeroExtend(rdmaPayloadLen);
            end
            rdmaMacIpUspMetadataCheckerExpectedQ.enq(macIpUdpMeta);
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
            BusBitNum tmpShiftCnt = zeroExtend(rdmaExtendHeaderBufInvalidByteNum) * fromInteger(valueOf(BYTE_WIDTH));
            RdmaExtendHeaderBuffer rdmaExtendHeaderMask = ~((1 << tmpShiftCnt) - 1);
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
                payloadStreamGen.reqPipeIn.enq(zeroExtend(rdmaPayloadLen));
                
                DataBusOneBasedByteIndex firstPayloadByteOneBasedOffsetInFirstPayloadBeat = fromInteger(valueOf(BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT)) - truncate(bthAndEthTotalLength);
                ByteIndexInBeat firstPayloadByteOneBasedOffsetInFirstPayloadBeatTmpValue = truncate(firstPayloadByteOneBasedOffsetInFirstPayloadBeat);
                firstPayloadByteOneBasedOffsetInFirstPayloadBeat = zeroExtend(firstPayloadByteOneBasedOffsetInFirstPayloadBeatTmpValue);
                DataBusSignedShiftOffset signedShiftOffset = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - zeroExtend(firstPayloadByteOneBasedOffsetInFirstPayloadBeat);
                txStreamShifter.offsetPipeIn.enq(signedShiftOffset);
            end
            packetGen.rdmaPacketMetaPipeIn.enq(rdmaPacketMeta);
            let infoForChecker = RdmaRecvPacketMeta{
                header: rdmaBthAndExtendHeader,
                hasPayload: hasPayload,
                firstPayloadByteOneBasedOffsetInFirstPayloadBeat: ?
            };
            rdmaHeaderExtractorMetaExpectedQ.enq(infoForChecker);
            stateReg <= TestInputPacketClassifierStateCheckPacketClassifierOutput;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkTestInputPacketClassifier genRandomPacketHeader"),
            //     toBlue(", macIpUdpMeta="), fshow(macIpUdpMeta),
            //     toBlue(", rdmaPayloadLen="), fshow(rdmaPayloadLen),
            //     toBlue(", rdmaPacketMeta="), fshow(rdmaPacketMeta)
            // );
            // $display("============Finish genRandomPacketHeader Request==============");
        end
        else begin
            immFail("TODO", $format(""));
        end

        
    endrule

    

    rule checkPacketClassifierOutput if (stateReg == TestInputPacketClassifierStateCheckPacketClassifierOutput);
        let expected = rdmaMacIpUspMetadataCheckerExpectedQ.first;
        rdmaMacIpUspMetadataCheckerExpectedQ.deq;
        let got = packetClassifier.rdmaMacIpUdpMetaPipeOut.first;
        packetClassifier.rdmaMacIpUdpMetaPipeOut.deq;
        
        immAssert(
            got.srcMacAddr == macUnicastAddrForTestSendNode && 
            got.ipDscp == expected.ipDscp && 
            got.ipEcn == expected.ipEcn &&
            got.srcIpAddr == ipAddrForTestSendNode &&
            got.srcPort == expected.srcPort,
            "mkTestInputPacketClassifier getPacketClassifierOutput check failed",
            $format(
                ", got=", fshow(got),
                ", expected=", fshow(expected),
                ", macUnicastAddrForTestSendNode=", fshow(macUnicastAddrForTestSendNode),
                ", ipAddrForTestSendNode=", fshow(ipAddrForTestSendNode)
            )
        );

        stateReg <= TestInputPacketClassifierStateCheckRdmaHeaderExtractorOutput;
        // $display("============Finish checkPacketClassifierOutput==============");
    endrule

    rule checkRdmaHeaderExtractorOutput if (stateReg == TestInputPacketClassifierStateCheckRdmaHeaderExtractorOutput);
        if (packetCon.rdmaPacketMetaPipeOut.notEmpty && rdmaHeaderExtractorMetaExpectedQ.notEmpty) begin
            let expected = rdmaHeaderExtractorMetaExpectedQ.first;
            rdmaHeaderExtractorMetaExpectedQ.deq;
            let got = packetCon.rdmaPacketMetaPipeOut.first;
            packetCon.rdmaPacketMetaPipeOut.deq;

            let rdmaTotalHeaderLen = calcHeaderLenByTransTypeAndRdmaOpCode(got.header.bth.trans, got.header.bth.opcode);
            let invalidExtHeaderBufferBitNum = (valueOf(RDMA_BTH_AND_ETH_MAX_BYTE_WIDTH) - rdmaTotalHeaderLen) * valueOf(BYTE_WIDTH);
            BusBitNum shiftInvalidExtHeaderBufferBitNum = fromInteger(invalidExtHeaderBufferBitNum);
            // Note, the rdmaExtendHeaderBuf may contain garbage data at it's lower bits.
            immAssert(
                (pack(got.header) >> shiftInvalidExtHeaderBufferBitNum) == (pack(expected.header) >> shiftInvalidExtHeaderBufferBitNum),
                "mkTestInputPacketClassifier checkRdmaHeaderExtractorOutput meta check failed",
                $format(
                    ", got=", fshow(got),
                    ", expected=", fshow(expected)
                )
            );

            curRecvPacketMetaDataReg <= got;

            if (!got.hasPayload) begin
                stateReg <= TestInputPacketClassifierStateGenReq;
                // $display("============Finish checkRdmaHeaderExtractorOutput  no payload==============");
            end

            quitCounterReg <= quitCounterReg - 1;
            if (quitCounterReg % 50000 == 0) begin
                $display(quitCounterReg);
            end
        end
        else begin
            let got = packetCon.rdmaPayloadPipeOut.first;
            packetCon.rdmaPayloadPipeOut.deq;
            let expected = rdmaHeaderExtractorPayloadExpectedQ.first;
            rdmaHeaderExtractorPayloadExpectedQ.deq;

            if (got.isFirst) begin
                // for the first beat, received datastream may have garbage data
                BusBitNum shiftInvalidExtHeaderBufferBitNum = (
                    fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - zeroExtend(curRecvPacketMetaDataReg.firstPayloadByteOneBasedOffsetInFirstPayloadBeat)
                ) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);

                got.data = got.data << shiftInvalidExtHeaderBufferBitNum;
                expected.data = expected.data << shiftInvalidExtHeaderBufferBitNum;
            end
            
            immAssert(
                got == expected,
                "mkTestInputPacketClassifier checkRdmaHeaderExtractorOutput payload check failed",
                $format(
                    ", got=", fshow(got),
                    ", expected=", fshow(expected)
                )
            );
  

            if (got.isLast) begin
                stateReg <= TestInputPacketClassifierStateGenReq;
                // $display("============Finish checkRdmaHeaderExtractorOutput with payload==============");
                // $display("PASS");
            end
        end
        

    endrule

    rule checkQuitCounter;
        if (quitCounterReg == 0) begin
            $display("pass");
            $finish;
        end
    endrule
endmodule