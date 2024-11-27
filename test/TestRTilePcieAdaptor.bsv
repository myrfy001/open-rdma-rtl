import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import RTilePcieAdaptor :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;

import PcieTypes :: *;
import StreamShifterG :: *;
import DtldStream :: *;
import AddressChunker :: *;

`include "PcieMacros.bsv"


(* doc = "testcase" *)
module mkTestRTilePcieAdaptorTx(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

    let dut <- mkRTilePcie;

    Reg#(Bool) runReg <- mkReg(True);
    rule injectReadTlp if (runReg);
        runReg <= False;

        let writeMeta = DtldStreamMemAccessMeta {
            addr: 0,
            totalLen: 32
        };
        let writeData = DtldStreamData {
            data: 'h00000000_11111111_22222222_33333333_44444444_55555555_66666666_77777777,
            startByteIdx: 0,
            byteNum: 32,
            isFirst: True,
            isLast: True
        };
        dut.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        dut.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

        let readMeta = DtldStreamMemAccessMeta {
            addr: 0,
            totalLen: 32
        };
        
        dut.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);

    endrule

    rule getOutput;
        let outBeat = dut.pcieTxPipeOut.first;
        dut.pcieTxPipeOut.deq;
        $display(fshow(outBeat));
    endrule
endmodule

interface TestPcieRxStreamSegmentForkTimingTest;
    method Bit#(16) getOutput;
endinterface

(* synthesize *)
module mkTestPcieRxStreamSegmentForkTimingTest(TestPcieRxStreamSegmentForkTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

    let dut <- mkPcieRxStreamSegmentFork;

    ForceKeepWideSignals#(Bit#(2048), Bit#(16)) signalKeeperA <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(256), Bit#(16)) signalKeeperB <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(256), Bit#(16)) signalKeeperC <- mkForceKeepWideSignals; 
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    // let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    // let randSource6 <- mkSynthesizableRng512('h11111111);

    Reg#(Bit#(16)) outReg <- mkReg(0);
    rule injectTlp;

        let randValue1 <- randSource1.get;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        let randValue4 <- randSource4.get;
        // let randValue5 <- randSource5.get;
        // let randValue6 <- randSource6.get;

        let beat = unpack(truncate({pack(randValue1), pack(randValue2), pack(randValue3),  pack(randValue4)}));
        dut.pcieRxPipeIn.enq(beat);

    endrule

    rule handleOutput;
        RtilePcieRxPayloadStorageWriteReq x = unpack(0);
        Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)) y = unpack(0);
        Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) z = unpack(0);

        for (Integer idx = 0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            if (dut.tlpRawBeatDataStorageWriteReqPipeOutVec[idx].notEmpty) begin
                x = unpack(pack(x) ^ pack(dut.tlpRawBeatDataStorageWriteReqPipeOutVec[idx].first));
                dut.tlpRawBeatDataStorageWriteReqPipeOutVec[idx].deq;
            end
            
            if (dut.cpltTlpVecPipeOutVec[idx].notEmpty) begin
                y = unpack(pack(y) ^ pack(dut.cpltTlpVecPipeOutVec[idx].first));
                dut.cpltTlpVecPipeOutVec[idx].deq;
            end
        end

        if (dut.memReadWriteReqTlpVecPipeOut.notEmpty) begin
            z = dut.memReadWriteReqTlpVecPipeOut.first;
            dut.memReadWriteReqTlpVecPipeOut.deq;
        end


        signalKeeperA.bitsPipeIn.enq(zeroExtend(pack(x)));
        signalKeeperB.bitsPipeIn.enq(zeroExtend(pack(y)));
        signalKeeperC.bitsPipeIn.enq(zeroExtend(pack(z)));


        outReg <= pack(signalKeeperA.out) ^ pack(signalKeeperB.out) ^ pack(signalKeeperC.out);
    endrule

    method getOutput = outReg;
endmodule



interface TestPcieHwCpltBufferAllocatorTimingTest;
    method Bit#(8) getOutput;
endinterface


module mkTestPcieHwCpltBufferAllocatorTimingTest(TestPcieHwCpltBufferAllocatorTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

    let dut <- mkPcieHwCpltBufferAllocator;


    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Reg#(Bit#(8))) signalKeepRegVec <- replicateM(mkReg(0));
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    // let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    // let randSource6 <- mkSynthesizableRng512('h11111111);

    Reg#(Bit#(8)) outReg <- mkReg(0);


    Reg#(Bit#(512)) randValue1Reg <- mkRegU;
    Reg#(Bit#(512)) randValue2Reg <- mkRegU;

    rule getRandVal;
        Bit#(512) randValue1 <- randSource1.get;
        Bit#(512) randValue2 <- randSource2.get;

        randValue1Reg <= randValue1;
        randValue2Reg <= randValue2;
    endrule

    for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        rule injectA;
            let beat = unpack(truncate(pack(randValue1Reg) >> 64 * idx));
            dut.slotAllocReqPipeInVec[idx].enq(beat);
        endrule

        rule injectB;
            let beat = unpack(truncate(pack(randValue2Reg) >> 64 * idx));
            dut.slotDeAllocPipeInVec[idx].enq(beat);
        endrule
    end
        
    for (Integer idx = 0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        rule handleOutput;
            dut.slotAllocRespPipeOutVec[idx].deq;
            signalKeepRegVec[idx] <= signalKeepRegVec[idx] + 1;
        endrule
    end


    rule mergeOutput;
        Bit#(8) out = 0;
        for (Integer idx = 0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            out = out ^ pack(signalKeepRegVec[idx]);
        end
        outReg <= out;
    endrule
    method getOutput = outReg;
endmodule



interface TestPcieCompletionBufferTimingTest;
    method Byte getOutput;
endinterface

(* doc = "testcase" *)
(* synthesize *)
module mkTestPcieCompletionBufferTimingTest(TestPcieCompletionBufferTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

    let dut <- mkPcieCompletionBuffer;

    ForceKeepWideSignals#(Bit#(256), Byte) signalKeeper1 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(256), Byte) signalKeeper2 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(512), Byte) signalKeeper3 <- mkForceKeepWideSignals; 
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    let randSource6 <- mkSynthesizableRng512('h11111111);
    let randSource7 <- mkSynthesizableRng512('h22222222);

    Reg#(Byte) outReg <- mkReg(0);

    rule setChannelIdx;
        dut.setChannelIdx(0);
    endrule

    rule injectReq1;
        let randValue1 <- randSource1.get;

        let entry = unpack(truncate(randValue1));
        dut.tagAllocReqPipeIn.enq(entry);

    endrule

    rule injectReq2;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        let randValue4 <- randSource4.get;


        let entry = unpack(truncate({pack(randValue2), pack(randValue3), pack(randValue4)}));
        dut.tlpRawBeatDataStorageWriteReqPipeIn.enq(entry);

    endrule

    rule injectReq3;
        let randValue5 <- randSource5.get;

        let entry = unpack(truncate(randValue5));
        dut.cpltTlpVecPipeIn.enq(entry);

    endrule


    rule handleOutput1;
        signalKeeper1.bitsPipeIn.enq(zeroExtend(pack(dut.tagAllocRespPipeOut.first)));
        dut.tagAllocRespPipeOut.deq;
    endrule

    rule handleOutput2;
        signalKeeper2.bitsPipeIn.enq(zeroExtend(pack(dut.sharedHwCpltBufferSlotDeAllocReqPipeOut.first)));
        dut.sharedHwCpltBufferSlotDeAllocReqPipeOut.deq;
    endrule

    rule handleOutput3;
        signalKeeper3.bitsPipeIn.enq(zeroExtend(pack(dut.dataStreamPipeOut.first)));
        dut.dataStreamPipeOut.deq;
    endrule

    rule mergeOutput;
        outReg <= unpack(pack(signalKeeper1.out) ^ pack(signalKeeper2.out) ^ pack(signalKeeper3.out));
    endrule




    method getOutput = outReg;
endmodule


interface TestRtilePcieAdaptorTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestRtilePcieAdaptorTimingTest(TestRtilePcieAdaptorTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);


    let rtilePcie <- mkRTilePcie;
    let dut <- mkRTilePcieAdaptor;

    mkConnection(dut.pcieRxPipeOut, rtilePcie.pcieRxPipeIn);
    mkConnection(dut.pcieTxPipeIn, rtilePcie.pcieTxPipeOut);


    ForceKeepWideSignals#(Bit#(2048), Bit#(32)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(512), Bit#(16)) signalKeeperForRxBusOutput           <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForUserLogicReadOutput   <- mkForceKeepWideSignals; 
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    let randSource6 <- mkSynthesizableRng512('h11111111);
    let randSource7 <- mkSynthesizableRng512('h22222222);
    let randSource8 <- mkSynthesizableRng512('h33333333);
    let randSource9 <- mkSynthesizableRng512('h44444444);
    let randSourceA <- mkSynthesizableRng512('h55555555);
    let randSourceB <- mkSynthesizableRng512('h66666666);
    let randSourceC <- mkSynthesizableRng512('h77777777);
    let randSourceD <- mkSynthesizableRng512('h88888888);


    Reg#(Bool) runReg <- mkReg(True);
    Reg#(Bit#(128)) outReg <- mkReg(0);

    Reg#(Bit#(2048)) rxBusInputSignalReg <- mkReg(0);
    Reg#(Bit#(512)) txBusInputSignalReg <- mkReg(0);

    Reg#(Bit#(512)) rxBusOutputSignalReg <- mkReg(0);
    Reg#(Bit#(2048)) txBusOutputSignalReg <- mkReg(0);

    rule injectUserLogicReq1 if (runReg);
        let randValue1 <- randSource1.get;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        let randValue4 <- randSource4.get;
        let randValue5 <- randSource5.get;


        
        
        // write req
        let writeMeta = unpack(truncate(randValue1));
        let writeData = unpack(truncate({randValue2, randValue3, randValue4}));
        rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

        writeMeta = unpack(truncate(randValue2));
        writeData = unpack(truncate({randValue1, randValue4, randValue3}));
        rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeDataPipeIn.enq(writeData);

        writeMeta = unpack(truncate(randValue5));
        writeData = unpack(truncate({randValue3, randValue2, randValue1}));
        rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeDataPipeIn.enq(writeData);

        writeMeta = unpack(truncate(randValue3));
        writeData = unpack(truncate({randValue4, randValue1, randValue2}));
        rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeDataPipeIn.enq(writeData);

        // read req
        let readMeta = unpack(truncate(randValue5));
        rtilePcie.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue4));
        rtilePcie.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue3));
        rtilePcie.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue2));
        rtilePcie.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);
    endrule

    rule updateBusSignalReg;
        let randValue6 <- randSource6.get;
        let randValue7 <- randSource7.get;
        let randValue8 <- randSource8.get;
        let randValue9 <- randSource9.get;
        let randValueA <- randSourceA.get;

        rxBusInputSignalReg <= {randValue6, randValue7, randValue8, randValue9};
        txBusInputSignalReg <= {randValueA};
    endrule

    rule handleRxBusInputSignals;
        PcieTlpDataBusSegBundle         data;
        PcieTlpHeaderBusSegBundle       hdr;
        SopSignalBundle                 sop;
        EopSignalBundle                 eop;
        HvalidSignalBundle              hvalid;
        DvalidSignalBundle              dvalid;
        BarIdSignalBundle               bar;
        SegmentEmptySignalBundle        empty;
        HeaderCreditInitAckSignalBundle hcrdt_init_ack;
        DataCreditInitAckSignalBundle   dcrdt_init_ack;

        {data, hdr, sop, eop, hvalid, dvalid, bar, empty, hcrdt_init_ack, dcrdt_init_ack} = unpack(truncate(rxBusInputSignalReg));
        dut.rx.setRxInputData(data, hdr, sop, eop, hvalid, dvalid, bar, empty, hcrdt_init_ack, dcrdt_init_ack);
    endrule

    rule handleRxBusOutputSignals;
        rxBusOutputSignalReg <= zeroExtend({
            pack(dut.rx.hcrdt_init),
            pack(dut.rx.hcrdt_update),
            pack(dut.rx.hcrdt_update_cnt),
            pack(dut.rx.dcrdt_init),
            pack(dut.rx.dcrdt_update),
            pack(dut.rx.dcrdt_update_cnt)
        });
        signalKeeperForRxBusOutput.bitsPipeIn.enq(zeroExtend(pack(rxBusOutputSignalReg)));
    endrule

    rule handleTxBusInputSignals;

        HeaderCreditInitSignalBundle        hcrdt_init;
        HeaderCreditUpdateSignalBundle      hcrdt_update;
        HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt;
        DataCreditInitSignalBundle          dcrdt_init;
        DataCreditUpdateSignalBundle        dcrdt_update;
        DataCreditUpdateCntSignalBundle     dcrdt_update_cnt;
        Bool                                ready;

        {hcrdt_init, hcrdt_update, hcrdt_update_cnt, dcrdt_init, dcrdt_update, dcrdt_update_cnt, ready} = unpack(truncate(txBusInputSignalReg));
        dut.tx.setTxInputData(hcrdt_init, hcrdt_update, hcrdt_update_cnt, dcrdt_init, dcrdt_update, dcrdt_update_cnt, ready);
    
    endrule

    rule handleTxBusOutputSignals;
        txBusOutputSignalReg <= zeroExtend({
            pack(dut.tx.hcrdt_init_ack),
            pack(dut.tx.dcrdt_init_ack),
            pack(dut.tx.hdr),
            pack(dut.tx.data),
            pack(dut.tx.sop),
            pack(dut.tx.eop),
            pack(dut.tx.hvalid),
            pack(dut.tx.dvalid)
        });
        signalKeeperForTxBusOutput.bitsPipeIn.enq(zeroExtend(pack(txBusOutputSignalReg)));
    endrule

    rule handleUSerlogicReadOutput;
        Vector#(NUMERIC_TYPE_FOUR, RtilePcieUserStream) resultVec = newVector;

        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
            if (rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.notEmpty) begin
                resultVec[idx] = rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.first;
                rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.deq;
            end
        end

        signalKeeperForUserLogicReadOutput.bitsPipeIn.enq(zeroExtend(pack(resultVec)));

    endrule


    rule handleOutput;
        

        outReg <= zeroExtend({signalKeeperForRxBusOutput.out, signalKeeperForTxBusOutput.out, signalKeeperForUserLogicReadOutput.out});
    endrule



    method getOutput = outReg;
endmodule




interface TestRTilePcieByCocotbTest;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rxRawIfc;

    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx txRawIfc;

    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieBiDirUserDataStreamPipes)     streamSlaveIfcVec;
endinterface

module mkTestRTilePcieByCocotbTest(TestRTilePcieByCocotbTest);
    let inner <- mkRTilePcie;
    let rawInterfaceAdaptor <- mkRTilePcieAdaptor;

    mkConnection(rawInterfaceAdaptor.pcieRxPipeOut, inner.pcieRxPipeIn);
    mkConnection(rawInterfaceAdaptor.pcieTxPipeIn, inner.pcieTxPipeOut);

    interface rxRawIfc = rawInterfaceAdaptor.rx;
    interface txRawIfc = rawInterfaceAdaptor.tx;
    interface streamSlaveIfcVec = inner.streamSlaveIfcVec;
endmodule







// interface TestRTileDmaReadWriteSimple;
//     (* always_ready, always_enabled *)
//     interface RTilePcieAdaptorRx rxRawIfc;

//     (* always_ready, always_enabled *)
//     interface RTilePcieAdaptorTx txRawIfc;

//     (* always_ready, always_enabled *)
//     method Action startTest(Bool isStart);

// endinterface

// // since the beat size is a const value, so no need to return value dynamically. Only need a placeholder to satify function signature.
// typedef 128                              RTILE_DATA_BUS_BYTE_WIDTH;
// typedef TLog#(RTILE_DATA_BUS_BYTE_WIDTH) RTILE_BEAT_ALIGN_BIT_NUM;   // 7

// module mkTestRTileDmaReadWriteSimple(TestRTileDmaReadWriteSimple);
//     let dut <- mkRTilePcie;
//     let rawInterfaceAdaptor <- mkRTilePcieAdaptor;

//     mkConnection(rawInterfaceAdaptor.pcieRxPipeOut, dut.pcieRxPipeIn);
//     mkConnection(rawInterfaceAdaptor.pcieTxPipeIn, dut.pcieTxPipeOut);

//     Reg#(Bool) isStartedReg <- mkReg(False);
//     Reg#(Word) runStepReg   <- mkReg(0);

//     Vector#(NUMERIC_TYPE_FOUR, PipeOut#(Length)) readAddrRandPipeOutVec <- replicateM(mkRandomLenPipeOut(0, 1024*1024-1));
//     Vector#(NUMERIC_TYPE_FOUR, PipeOut#(Length)) readLenRandPipeOutVec <- replicateM(mkRandomLenPipeOut(1, 512+100));

//     Vector#(NUMERIC_TYPE_FOUR, PipeOut#(Length)) writeAddrRandPipeOutVec <- replicateM(mkRandomLenPipeOut(0, 1024*1024-1));
//     Vector#(NUMERIC_TYPE_FOUR, PipeOut#(Length)) writeLenRandPipeOutVec <- replicateM(mkRandomLenPipeOut(1, 512+100));

//     function Tuple2#(ADDR, ADDR) alignAddrForRtileBeat(ADDR addr, BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
//         Bit#(RTILE_BEAT_ALIGN_BIT_NUM) zeroPadding = 0;
//         ADDR alignedAddr = unpack({addr[valueOf(ADDR_WIDTH)-1 : valueOf(RTILE_BEAT_ALIGN_BIT_NUM)], zeroPadding});
//         ADDR addrRemainder = unpack({zeroPadding, addr[valueOf(RTILE_BEAT_ALIGN_BIT_NUM) - 1 : 0]});
//         return tuple2(alignedAddr, addrRemainder);
//     endfunction

//     function Tuple2#(Length, Length) devideLengthForRtileBeat(Length len, BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
//         Bit#(RTILE_BEAT_ALIGN_BIT_NUM) zeroPadding = 0;
//         Length dividedLen = {zeroPadding, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : valueOf(RTILE_BEAT_ALIGN_BIT_NUM)]};
//         Length divideRemainder = {zeroPadding, len[valueOf(RTILE_BEAT_ALIGN_BIT_NUM) - 1 : 0]};
//         return tuple2(dividedLen, divideRemainder);
//     endfunction

//     function Bool isAddrAndLengthLowerPartSumOverflowForRtileBeat(Length len, BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
//         Bit#(RTILE_BEAT_ALIGN_BIT_NUM) lowerBits = len[valueOf(RTILE_BEAT_ALIGN_BIT_NUM)-1 : 0];
//         return len[valueOf(RTILE_BEAT_ALIGN_BIT_NUM)] == 1 && !isZeroR(lowerBits);
//     endfunction

//     function Length getChunkSizeForRtileBeat(BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
//         return fromInteger(valueOf(RTILE_DATA_BUS_BYTE_WIDTH));
//     endfunction


//     // Vector#(NUMERIC_TYPE_FOUR, AddressChunkMetaCalculator#(ADDR, Length, PMTU, TAdd#(1, MAX_PMTU_WIDTH))) readAddrChunkerVec <- replicateM(
//     //     mkAddressChunkMetaCalculator(
//     //         alignAddrForRtileBeat,
//     //         devideLengthForRtileBeat,
//     //         isAddrAndLengthLowerPartSumOverflowForRtileBeat,
//     //         getChunkSizeForRtileBeat
//     //     )); 

    


//     // Vector#(256, Byte) linerIncrByteVec = reverse(genVector);
//     // let linerIncrByteVecAsBit = pack(linerIncrByteVec);

//     // rule doTest if (isStartedReg && runStepReg < 1000);
//     //     if (runStepReg == 0) begin
//     //         $display("%t, ----------------start do test----------------------", $time);
//     //     end
//     //     runStepReg <= runStepReg + 1;

//     //     for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx=idx + 1) begin
//     //         let readAddr = readAddrRandPipeOutVec[idx].first;
//     //         readAddrRandPipeOutVec[idx].deq;

//     //         let readLen = readLenRandPipeOutVec[idx].first;
//     //         readLenRandPipeOutVec[idx].deq;

//     //         let writeAddr = writeAddrRandPipeOutVec[idx].first;
//     //         writeAddrRandPipeOutVec[idx].deq;

//     //         let writeLen = writeLenRandPipeOutVec[idx].first;
//     //         writeLenRandPipeOutVec[idx].deq;

//     //         if (curWriteReqMetaMaybeVec[idx] matches tagged Valid .curWriteReqMeta) begin
//     //             if (writeLen <= 512) begin
//     //                 let writeMeta = DtldStreamMemAccessMeta {
//     //                     addr: writeAddr,
//     //                     totalLen: writeLen
//     //                 };
//     //                 let writeData = DtldStreamData {
//     //                     data: 'h00000000_11111111_22222222_33333333_44444444_55555555_66666666_77777777_88888888_99999999,
//     //                     startByteIdx: 0,
//     //                     byteNum: 16,
//     //                     isFirst: True,
//     //                     isLast: True
//     //                 };
//     //             end
//     //         end
//     //         else begin
//     //             // if ()
//     //         end

//     //         if (readLen <= 512) begin
//     //             let readMeta = DtldStreamMemAccessMeta {
//     //                 addr: 4,
//     //                 totalLen: 17
//     //             };
//     //         end

//     //         case (runStepReg)
//     //             0: begin
//     //                 dut.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
//     //                 dut.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

//     //                 dut.streamSlaveIfcVec[1].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
//     //                 dut.streamSlaveIfcVec[1].writePipeIfc.writeDataPipeIn.enq(writeData);

//     //                 dut.streamSlaveIfcVec[2].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
//     //                 dut.streamSlaveIfcVec[2].writePipeIfc.writeDataPipeIn.enq(writeData);

//     //                 dut.streamSlaveIfcVec[3].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
//     //                 dut.streamSlaveIfcVec[3].writePipeIfc.writeDataPipeIn.enq(writeData);
//     //             end
//     //             100: begin
//     //                 dut.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
//     //                 dut.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
//     //                 dut.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
//     //                 dut.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);
//     //             end
//     //         endcase
//     //     end
        
//     // endrule

//     rule getReadResult;
//         let readDs = dut.streamSlaveIfcVec[0].readPipeIfc.readDataPipeOut.first;
//         dut.streamSlaveIfcVec[0].readPipeIfc.readDataPipeOut.deq;
//         $display("----------------read output----------------------\n", fshow(readDs));
//     endrule

//     method Action startTest(Bool isStart);
//         if (isStart) begin
//             $display("----------------isStartedReg <= True----------------------");
//             isStartedReg <= True;
//         end
//     endmethod 

//     interface rxRawIfc = rawInterfaceAdaptor.rx;
//     interface txRawIfc = rawInterfaceAdaptor.tx;
// endmodule