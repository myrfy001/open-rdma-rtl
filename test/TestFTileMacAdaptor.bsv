import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import FTileMacAdaptor :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;

import PcieTypes :: *;
import StreamShifterG :: *;
import DtldStream :: *;
import AddressChunker :: *;


module mkTestFtileMacRxPingPongSingleChannelProcessor(Empty);
    let dut <- mkFtileMacRxPingPongSingleChannelProcessor;

    Reg#(Byte) injectStepReg <- mkReg(0);
    Reg#(Word) checkStepReg <- mkReg(0);

    rule injectBeat if (injectStepReg <= 2);
        injectStepReg <= injectStepReg + 1;
        let inputMeta = ?;
        case (injectStepReg)
            0: begin
                // normal case, output one packet
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1}),
                    eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            1: begin
                // normal case, output one packet, but has empty field at head and tail
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
        endcase
        dut.metaPipeIn.enq(inputMeta);
    endrule

    rule checkBeat;
        checkStepReg <= checkStepReg + 1;
        let startStepOffset = 1;

        let outMeta0 = ?;
        let outMeta1 = ?;
        let outMeta2 = ?;
        let overflowFlag = ?;

        if (dut.packetNumOverflowAffectNextBeatPipeOut.notEmpty) begin
            dut.metaMaybePipeOutVec[0].deq; 
            dut.metaMaybePipeOutVec[1].deq;
            dut.metaMaybePipeOutVec[2].deq;
            dut.packetNumOverflowAffectNextBeatPipeOut.deq;
            outMeta0 = fromMaybe(?, dut.metaMaybePipeOutVec[0].first);
            outMeta1 = fromMaybe(?, dut.metaMaybePipeOutVec[1].first);
            outMeta2 = fromMaybe(?, dut.metaMaybePipeOutVec[2].first);
            overflowFlag = dut.packetNumOverflowAffectNextBeatPipeOut.first;
        end

        case (checkStepReg)
            (1 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.metaMaybePipeOutVec[0].notEmpty && !dut.metaMaybePipeOutVec[1].notEmpty && !dut.metaMaybePipeOutVec[2].notEmpty && !dut.packetNumOverflowAffectNextBeatPipeOut.notEmpty,
                    "check error at step 15",
                    $format("")
                );
            end
            (1 * 16 + startStepOffset): begin
                immAssert(
                    isValid(dut.metaMaybePipeOutVec[0].first) && !isValid(dut.metaMaybePipeOutVec[1].first) && !isValid(dut.metaMaybePipeOutVec[2].first) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 15 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True,
                    "check error",
                    $format("")
                );
            end
            (2 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.metaMaybePipeOutVec[0].notEmpty && !dut.metaMaybePipeOutVec[1].notEmpty && !dut.metaMaybePipeOutVec[2].notEmpty && !dut.packetNumOverflowAffectNextBeatPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (2 * 16 + startStepOffset): begin
                immAssert(
                    isValid(dut.metaMaybePipeOutVec[0].first) && !isValid(dut.metaMaybePipeOutVec[1].first) && !isValid(dut.metaMaybePipeOutVec[2].first) &&
                    outMeta0.startSegIdx == 1 && 
                    outMeta0.zeroBasedValidSegCnt == 12 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True,
                    "check error",
                    $format("outMeta0=", fshow(outMeta0), "outMeta1=", fshow(outMeta1), "outMeta2=", fshow(outMeta2))
                );
            end
        endcase

        if (checkStepReg > 200) begin
            $finish(1);
        end
    endrule
endmodule


interface TestFtileMacAdaptorTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestFtileMacAdaptorTimingTest(TestFtileMacAdaptorTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
    Reg#(Bool) runReg <- mkReg(True);
    Reg#(Bit#(128)) outReg <- mkReg(0);

    // // let rtilePcie <- mkRTilePcie;
    // let dut <- mkFTileMacAdaptor;

    // // mkConnection(dut.pcieRxPipeOut, rtilePcie.pcieRxPipeIn);
    // // mkConnection(dut.pcieTxPipeIn, rtilePcie.pcieTxPipeOut);


    // ForceKeepWideSignals#(Bit#(2048), Bit#(32)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 
    // ForceKeepWideSignals#(Bit#(512), Bit#(16)) signalKeeperForRxBusOutput           <- mkForceKeepWideSignals; 
    // ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForUserLogicReadOutput   <- mkForceKeepWideSignals; 
    

    // let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    // let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    // let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    // let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    // let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    // let randSource6 <- mkSynthesizableRng512('h11111111);
    // let randSource7 <- mkSynthesizableRng512('h22222222);
    // let randSource8 <- mkSynthesizableRng512('h33333333);
    // let randSource9 <- mkSynthesizableRng512('h44444444);
    // let randSourceA <- mkSynthesizableRng512('h55555555);
    // let randSourceB <- mkSynthesizableRng512('h66666666);
    // let randSourceC <- mkSynthesizableRng512('h77777777);
    // let randSourceD <- mkSynthesizableRng512('h88888888);




    // Reg#(Bit#(2048)) rxBusInputSignalReg <- mkReg(0);
    // Reg#(Bit#(512)) txBusInputSignalReg <- mkReg(0);

    // Reg#(Bit#(512)) rxBusOutputSignalReg <- mkReg(0);
    // Reg#(Bit#(2048)) txBusOutputSignalReg <- mkReg(0);

    // // rule injectUserLogicReq if (runReg);
        
    // //     let randValue1 <- randSource1.get;
    // //     let randValue2 <- randSource2.get;
    // //     let randValue3 <- randSource3.get;
    // //     let randValue4 <- randSource4.get;
    // //     let randValue5 <- randSource5.get;


    // //     let writeMeta = unpack(truncate(randValue1));

    // //     let writeData = unpack(truncate({randValue2, randValue3, randValue4}));

    // //     let readMeta = unpack(truncate(randValue5));

    // //     // write req
    // //     rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
    // //     rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

    // //     rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
    // //     rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeDataPipeIn.enq(writeData);

    // //     rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
    // //     rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeDataPipeIn.enq(writeData);

    // //     rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
    // //     rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeDataPipeIn.enq(writeData);

    // //     // read req
    // //     rtilePcie.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
    // //     rtilePcie.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
    // //     rtilePcie.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
    // //     rtilePcie.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);


    // // endrule

    // rule updateBusSignalReg;
    //     let randValue6 <- randSource6.get;
    //     let randValue7 <- randSource7.get;
    //     let randValue8 <- randSource8.get;
    //     let randValue9 <- randSource9.get;
    //     let randValueA <- randSourceA.get;

    //     rxBusInputSignalReg <= {randValue6, randValue7, randValue8, randValue9};
    //     txBusInputSignalReg <= {randValueA};
    // endrule

    // // rule handleRxBusInputSignals;
    // //     PcieTlpDataBusSegBundle         data;
    // //     PcieTlpHeaderBusSegBundle       hdr;
    // //     SopSignalBundle                 sop;
    // //     EopSignalBundle                 eop;
    // //     HvalidSignalBundle              hvalid;
    // //     DvalidSignalBundle              dvalid;
    // //     BarIdSignalBundle               bar;
    // //     SegmentEmptySignalBundle        empty;
    // //     HeaderCreditInitAckSignalBundle hcrdt_init_ack;
    // //     DataCreditInitAckSignalBundle   dcrdt_init_ack;

    // //     {data, hdr, sop, eop, hvalid, dvalid, bar, empty, hcrdt_init_ack, dcrdt_init_ack} = unpack(truncate(rxBusInputSignalReg));
    // //     dut.rx.setRxInputData(data, hdr, sop, eop, hvalid, dvalid, bar, empty, hcrdt_init_ack, dcrdt_init_ack);
    // // endrule

    // // rule handleRxBusOutputSignals;
    // //     rxBusOutputSignalReg <= zeroExtend({
    // //         pack(dut.rx.hcrdt_init),
    // //         pack(dut.rx.hcrdt_update),
    // //         pack(dut.rx.hcrdt_update_cnt),
    // //         pack(dut.rx.dcrdt_init),
    // //         pack(dut.rx.dcrdt_update),
    // //         pack(dut.rx.dcrdt_update_cnt)
    // //     });
    // //     signalKeeperForRxBusOutput.bitsPipeIn.enq(zeroExtend(pack(rxBusOutputSignalReg)));
    // // endrule

    // // rule handleTxBusInputSignals;

    // //     HeaderCreditInitSignalBundle        hcrdt_init;
    // //     HeaderCreditUpdateSignalBundle      hcrdt_update;
    // //     HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt;
    // //     DataCreditInitSignalBundle          dcrdt_init;
    // //     DataCreditUpdateSignalBundle        dcrdt_update;
    // //     DataCreditUpdateCntSignalBundle     dcrdt_update_cnt;
    // //     Bool                                ready;

    // //     {hcrdt_init, hcrdt_update, hcrdt_update_cnt, dcrdt_init, dcrdt_update, dcrdt_update_cnt, ready} = unpack(truncate(txBusInputSignalReg));
    // //     dut.tx.setTxInputData(hcrdt_init, hcrdt_update, hcrdt_update_cnt, dcrdt_init, dcrdt_update, dcrdt_update_cnt, ready);
    
    // // endrule

    // // rule handleTxBusOutputSignals;
    // //     txBusOutputSignalReg <= zeroExtend({
    // //         pack(dut.tx.hcrdt_init_ack),
    // //         pack(dut.tx.dcrdt_init_ack),
    // //         pack(dut.tx.hdr),
    // //         pack(dut.tx.data),
    // //         pack(dut.tx.sop),
    // //         pack(dut.tx.eop),
    // //         pack(dut.tx.hvalid),
    // //         pack(dut.tx.dvalid)
    // //     });
    // //     signalKeeperForTxBusOutput.bitsPipeIn.enq(zeroExtend(pack(txBusOutputSignalReg)));
    // // endrule

    // // rule handleUSerlogicReadOutput;
    // //     Vector#(NUMERIC_TYPE_FOUR, PcieStreamData) resultVec = newVector;

    // //     for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
    // //         if (rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.notEmpty) begin
    // //             resultVec[idx] = rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.first;
    // //             rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.deq;
    // //         end
    // //     end

    // //     signalKeeperForUserLogicReadOutput.bitsPipeIn.enq(zeroExtend(pack(resultVec)));

    // // endrule


    // rule handleOutput;
    //     outReg <= zeroExtend({signalKeeperForRxBusOutput.out, signalKeeperForTxBusOutput.out, signalKeeperForUserLogicReadOutput.out});
    // endrule



    method getOutput = outReg;
endmodule
