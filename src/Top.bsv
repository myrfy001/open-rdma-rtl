import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;
import Settings :: *;
import Utils4Test :: *;
import DtldStream :: *;


import RTilePcieAdaptor :: *;

interface BsvTop;
        (* always_ready, always_enabled *)
        interface RTilePcieAdaptorRx rtilePcieAdaptorRxRawIfc;

        (* always_ready, always_enabled *)
        interface RTilePcieAdaptorTx rtilePcieAdaptorTxRawIfc;

        method Bit#(128) signalKeeperOutput;
        
endinterface


module mkBsvTop(BsvTop);
    RTilePcieAdaptor rtilePcieAdaptor   <- mkRTilePcieAdaptor;
    RTilePcie        rtilePcie          <- mkRTilePcie;

    mkConnection(rtilePcieAdaptor.pcieRxPipeOut, rtilePcie.pcieRxPipeIn);
    mkConnection(rtilePcieAdaptor.pcieTxPipeIn, rtilePcie.pcieTxPipeOut);


    ForceKeepWideSignals#(Bit#(2048), Bit#(32)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(512), Bit#(16)) signalKeeperForRxBusOutput           <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForUserLogicReadOutput   <- mkForceKeepWideSignals; 
    

    Reg#(Bit#(128)) outReg <- mkReg(0);

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

    rule injectUserLogicReq1;
        let randValue1 <- randSource1.get;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        let randValue4 <- randSource4.get;
        let randValue5 <- randSource5.get;
        
        // write req as requester
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

        // read req as requester
        let readMeta = unpack(truncate(randValue5));
        rtilePcie.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue4));
        rtilePcie.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue3));
        rtilePcie.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue2));
        rtilePcie.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);

        // read resp as completer
        let readData = unpack(truncate({randValue1, randValue2, randValue5}));
        rtilePcie.streamMasterIfc.readPipeIfc.readDataPipeIn.enq(readData);
    endrule


    rule handleUserlogicReadOutput;
        Vector#(NUMERIC_TYPE_FOUR, RtilePcieUserStream) resultVec = newVector;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
            if (rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.notEmpty) begin
                resultVec[idx] = rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.first;
                rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.deq;
            end
        end

        let completerWm = ?;
        let completerWd = ?;
        let completerRm = ?;
        if (rtilePcie.streamMasterIfc.writePipeIfc.writeMetaPipeOut.notEmpty) begin
            completerWm = rtilePcie.streamMasterIfc.writePipeIfc.writeMetaPipeOut.first;
            rtilePcie.streamMasterIfc.writePipeIfc.writeMetaPipeOut.deq;
        end
        if (rtilePcie.streamMasterIfc.writePipeIfc.writeDataPipeOut.notEmpty) begin
            completerWd = rtilePcie.streamMasterIfc.writePipeIfc.writeDataPipeOut.first;
            rtilePcie.streamMasterIfc.writePipeIfc.writeDataPipeOut.deq;
        end
        if (rtilePcie.streamMasterIfc.readPipeIfc.readMetaPipeOut.notEmpty) begin
            completerRm = rtilePcie.streamMasterIfc.readPipeIfc.readMetaPipeOut.first;
            rtilePcie.streamMasterIfc.readPipeIfc.readMetaPipeOut.deq;
        end

        signalKeeperForUserLogicReadOutput.bitsPipeIn.enq(zeroExtend({pack(resultVec), pack(completerWm), pack(completerWd), pack(completerRm)}));

    endrule

    rule handleOutput;
        outReg <= zeroExtend({signalKeeperForRxBusOutput.out, signalKeeperForTxBusOutput.out, signalKeeperForUserLogicReadOutput.out});
    endrule

    method signalKeeperOutput = outReg;

    interface rtilePcieAdaptorRxRawIfc = rtilePcieAdaptor.rx;
    interface rtilePcieAdaptorTxRawIfc = rtilePcieAdaptor.tx;
endmodule

