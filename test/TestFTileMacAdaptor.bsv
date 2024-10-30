import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import StmtFSM :: * ;

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

    Reg#(Byte) injectStepReg <- mkReg(1);
    Reg#(Word) checkStepReg <- mkReg(0);

    rule injectBeat if (injectStepReg <= 15);
        injectStepReg <= injectStepReg + 1;
        let inputMeta = ?;
        case (injectStepReg)
            1: begin
                // normal case, output one packet
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1}),
                    eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            2: begin
                // normal case, output one packet, but has empty field at head and tail
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            3: begin
                // normal case, output one packet, but has empty field at head, and not reach eop inn this beat
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            4: begin
                // normal case, output one packet, but no sop, only have eop, so it's a packet with previous beat
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            5: begin
                // normal case, output two packet
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            6: begin
                // normal case, output two packet, but has gap between them
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            7: begin
                // normal case, output three packet, has gap between them
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0}),
                    eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            8: begin
                // normal case, output three packet, has gap between them, first one is a eop, last one is a sop
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            9: begin
                // normal case, output one packet, no sop or eop, it's middle packet
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            10: begin
                // abnormal case, output four packet, with last segment invalid. won't affact next beat.
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            11: begin
                // abnormal case, output four packet, with last segment just eop. won't affact next beat.
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1}),
                    eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            12: begin
                // abnormal case, output four packet, with last segment not eop. will affact next beat, should output overflow True
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            13: begin
                // abnormal case, output four packet, with first packet continous from previous beat,
                // and last segment not eop. will affact next beat, should output overflow True
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            14: begin
                // abnormal case, output five packet, with first packet continous from previous beat,
                // and last segment not eop. will affact next beat, should output overflow True
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
                    eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
            15: begin
                // abnormal case, output five packet, with first packet continous from previous beat,
                // and last segment eop. will not affact next beat, should output overflow False
                inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
                    bufferAddr  : zeroExtend(injectStepReg),
                    eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
                    sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
                    eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
                    fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
                };
            end
        endcase
        dut.beatMetaPipeIn.enq(inputMeta);
    endrule

    rule checkBeat;
        checkStepReg <= checkStepReg + 1;
        let startStepOffset = 1;

        let outMeta0 = ?;
        let outMeta1 = ?;
        let outMeta2 = ?;
        let overflowFlag = ?;
        let packestMeta = ?;

        if (dut.packetsChunkMetaPipeOut.notEmpty) begin
            dut.packetsChunkMetaPipeOut.deq; 
            packestMeta = dut.packetsChunkMetaPipeOut.first;

            outMeta0 = fromMaybe(?, packestMeta.packetChunkMetaVector[0]);
            outMeta1 = fromMaybe(?, packestMeta.packetChunkMetaVector[1]);
            outMeta2 = fromMaybe(?, packestMeta.packetChunkMetaVector[2]);
            overflowFlag = packestMeta.packetNumOverflowAffectNextBeat;
        end

        case (checkStepReg)
            (1 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (1 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 15 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (2 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("outMeta0=", fshow(outMeta0), "outMeta1=", fshow(outMeta1), "outMeta2=", fshow(outMeta2))
                );
            end
            (2 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 1 && 
                    outMeta0.zeroBasedValidSegCnt == 12 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (3 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (3 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 1 && 
                    outMeta0.zeroBasedValidSegCnt == 14 &&
                    outMeta0.isFirst == True && outMeta0.isLast == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (4 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (4 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 4 &&
                    outMeta0.isFirst == False && outMeta0.isLast == True,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (5 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (5 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 1 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 3 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (6 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (6 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 1 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 4 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (7 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (7 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 1 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 4 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 14 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (8 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (8 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 2 &&
                    outMeta0.isFirst == False && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 4 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 14 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == False &&
                    overflowFlag == False,
                    "check error",$format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (9 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (9 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 15 &&
                    outMeta0.isFirst == False && outMeta0.isLast == False &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (10 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (10 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 2 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 5 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (11 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (11 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 2 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 5 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (12 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (12 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == True && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 2 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 5 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == True,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (13 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (13 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == False && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 2 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 5 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == True,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (14 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (14 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == False && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 2 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 5 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == True,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (15 * 16 - 1 + startStepOffset): begin
                immAssert(
                    !dut.packetsChunkMetaPipeOut.notEmpty,
                    "check error",
                    $format("")
                );
            end
            (15 * 16 + startStepOffset): begin
                immAssert(
                    isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
                    outMeta0.startSegIdx == 0 && 
                    outMeta0.zeroBasedValidSegCnt == 1 &&
                    outMeta0.isFirst == False && outMeta0.isLast == True &&
                    outMeta1.startSegIdx == 2 && 
                    outMeta1.zeroBasedValidSegCnt == 1 &&
                    outMeta1.isFirst == True && outMeta1.isLast == True &&
                    outMeta2.startSegIdx == 5 && 
                    outMeta2.zeroBasedValidSegCnt == 1 &&
                    outMeta2.isFirst == True && outMeta2.isLast == True &&
                    overflowFlag == False,
                    "check error",
                    $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
                );
            end
            (16 * 16 + startStepOffset): begin
                $finish;
            end
        endcase
    endrule
endmodule



interface TestFtileMacRxPingPongSingleChannelProcessorTimingTest;
    method Bit#(128) getOutput;
endinterface


(* synthesize *)
module mkTestFtileMacRxPingPongSingleChannelProcessorTimingTest(TestFtileMacRxPingPongSingleChannelProcessorTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
    Reg#(Bool) runReg <- mkReg(True);
    Reg#(Bit#(128)) outReg <- mkReg(0);

    let dut <- mkFtileMacRxPingPongSingleChannelProcessor;

    ForceKeepWideSignals#(Bit#(128), Bit#(128)) signalKeeperForOutput   <- mkForceKeepWideSignals; 
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);


    rule injectInput if (runReg);
        let randValue1 <- randSource1.get;
        let inputMeta = unpack(truncate(randValue1));
        dut.beatMetaPipeIn.enq(inputMeta);
    endrule

    rule handleDutOutput;
        dut.packetsChunkMetaPipeOut.deq;

        signalKeeperForOutput.bitsPipeIn.enq(zeroExtend(pack(dut.packetsChunkMetaPipeOut.first)));
    endrule

    rule forwardOutput;
        outReg <= signalKeeperForOutput.out;
    endrule



    method getOutput = outReg;
endmodule




module mkTestFtileMacRxPingPongChannelMetaJoin(Empty);

    let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 
    let ftileMacRxBeatJoin <- mkFtileMacRxPingPongChannelMetaJoin;

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);
        mkConnection(pingPongChannelVec[idx].packetsChunkMetaPipeOut, ftileMacRxBeatJoin.metaPipeInVec[idx]);
    end

    Reg#(Word) injectStepReg <- mkReg(1);
    Reg#(Word) checkStepReg <- mkReg(0);

    Reg#(Word) totalRecvPacketCntReg <- mkReg(0);
    Reg#(Word) totalRecvSegmentCntReg <- mkReg(0);

    rule discard;
        ftileMacRxBeatFork.rxBramWriteReqPipeOut.deq;
    endrule

    rule injectBeat;
        injectStepReg <= injectStepReg + 1;
        FtileMacRxBeat inputBeat = ?;
        case (injectStepReg)
            // normal case, for the 1st to 4th beat, each beat has one or two packet.
            1: begin
                // 1 packet, 10 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            2: begin
                // 2 packet, 9 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.eop       = unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            3: begin
                // 1 packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            4: begin
                // one packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end

            // normal case, for the 1st to 5th beat, each beat has one or two packet, but some packet will span multi beat
            31: begin
                // 2 packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            32: begin
                // 1 packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            33: begin
                // 1 packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            34: begin
                // 2 packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            35: begin
                // 3 packet, 16 seg
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0});
                inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end

            // abnormal case
            100: begin
                // 3 packet, but middle packet is error, so only 2 packet should be output, valid seg cnt = 11
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            101: begin
                // 4 packet, overflow but not affact next beat.  so only 3 packet should be output, valid seg cnt = 6
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            102: begin
                // 4 packet, overflow and will affact next beat.  so only 3 packet should be output, valid seg cnt = 6
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            103: begin
                // 1 packet, but is affacted by previous overflow, should be dropped
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
            104: begin
                // 3 packet, but first packet is affacted by previous overflow. so only 2 packet should be output, valid seg cnt = 14
                inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0});
                inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0});
                inputBeat.fcs_error = 0;
                ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
            end
        endcase
    endrule

    rule checkBeat;
        checkStepReg <= checkStepReg + 1;

        Word totalRecvPacketCnt  = totalRecvPacketCntReg;
        Word totalRecvSegmentCnt = totalRecvSegmentCntReg;

        for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            if (ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].notEmpty) begin
                let outputMeta = ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].first;
                ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].deq;
                totalRecvPacketCnt = totalRecvPacketCnt + 1;
                totalRecvSegmentCnt = totalRecvSegmentCnt + zeroExtend(outputMeta.zeroBasedValidSegCnt) + 1;
                $display("time=%0t:", $time, "idx=%d", idx , "outputMeta=", fshow(outputMeta));
            end
        end



        case (checkStepReg)
            30: begin
                immAssert(
                    totalRecvPacketCnt == 6 && totalRecvSegmentCnt == 51,
                    "packet num or seg num wrong",
                    $format("totalRecvPacketCnt=", fshow(totalRecvPacketCnt), ", totalRecvSegmentCnt=", fshow(totalRecvSegmentCnt))
                );
                // reset counter
                totalRecvPacketCnt = 0;
                totalRecvSegmentCnt = 0;
            end
            100: begin
                immAssert(
                    totalRecvPacketCnt == 9 && totalRecvSegmentCnt == 80,
                    "packet num or seg num wrong",
                    $format("totalRecvPacketCnt=", fshow(totalRecvPacketCnt), ", totalRecvSegmentCnt=", fshow(totalRecvSegmentCnt))
                );
                // reset counter
                totalRecvPacketCnt = 0;
                totalRecvSegmentCnt = 0;
            end
            150: begin
                immAssert(
                    totalRecvPacketCnt == 10 && totalRecvSegmentCnt == 37,
                    "packet num or seg num wrong",
                    $format("totalRecvPacketCnt=", fshow(totalRecvPacketCnt), ", totalRecvSegmentCnt=", fshow(totalRecvSegmentCnt))
                );
                // reset counter
                totalRecvPacketCnt = 0;
                totalRecvSegmentCnt = 0;
            end
            2000: begin
                $finish;
            end
        endcase


        totalRecvPacketCntReg   <= totalRecvPacketCnt;
        totalRecvSegmentCntReg  <= totalRecvSegmentCnt;
    endrule
endmodule




interface TestFtileMacRxPingPongChannelMetaJoinTimingTest;
    method Bit#(128) getOutput;
endinterface


(* synthesize *)
module mkTestFtileMacRxPingPongChannelMetaJoinTimingTest(TestFtileMacRxPingPongChannelMetaJoinTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
    Reg#(Bool) runReg <- mkReg(True);
    Reg#(Bit#(128)) outReg <- mkReg(0);

    let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 
    let ftileMacRxBeatJoin <- mkFtileMacRxPingPongChannelMetaJoin;

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);
        mkConnection(pingPongChannelVec[idx].packetsChunkMetaPipeOut, ftileMacRxBeatJoin.metaPipeInVec[idx]);
    end

    ForceKeepWideSignals#(Bit#(128), Bit#(128)) signalKeeperForOutput   <- mkForceKeepWideSignals; 
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);


    rule discard;
        ftileMacRxBeatFork.rxBramWriteReqPipeOut.deq;
    endrule

    rule injectInput if (runReg);
        let randValue1 <- randSource1.get;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;

        let inputBeat = unpack(truncate({randValue1, randValue2, randValue3}));
        ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
    endrule

    rule handleDutOutput;
        FtileMacRxPacketChunkMeta outputMeta = ?;
        for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            if (ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].notEmpty) begin
                outputMeta = unpack(pack(outputMeta) ^ pack(ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].first));
                ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].deq;
            end
        end

        signalKeeperForOutput.bitsPipeIn.enq(zeroExtend(pack(outputMeta)));
    endrule

    rule forwardOutput;
        outReg <= signalKeeperForOutput.out;
    endrule



    method getOutput = outReg;
endmodule



module mkTestFtileMacRxPayloadStorageAndGearBox(Empty);

    let dut <- mkFtileMacRxPayloadStorageAndGearBox;

    Reg#(Word) injectStepReg <- mkReg(1);
    Reg#(Word) checkStepReg <- mkReg(0);

    

    Stmt injectProc = seq
        action
            // Case 1
            FtileMacRxPacketChunkMeta req = ?;
            req.startSegIdx             = 0;
            req.zeroBasedValidSegCnt    = 15;
            req.lastSegEmptyByteCnt     = 2;
            req.isFirst                 = True;
            req.isLast                  = True;
            dut.packetChunkMetaPipeIn.enq(req);
        endaction
        action
            // Case 2
            FtileMacRxPacketChunkMeta req = ?;
            req.startSegIdx             = 0;
            req.zeroBasedValidSegCnt    = 1;
            req.lastSegEmptyByteCnt     = 2;
            req.isFirst                 = True;
            req.isLast                  = True;
            dut.packetChunkMetaPipeIn.enq(req);
        endaction
        // action
        //     // Case 3
        //     FtileMacRxPacketChunkMeta req = ?;
        //     req.startSegIdx             = 0;
        //     req.zeroBasedValidSegCnt    = 1;
        //     req.lastSegEmptyByteCnt     = 2;
        //     req.isFirst                 = True;
        //     req.isLast                  = True;
        //     dut.packetChunkMetaPipeIn.enq(req);
        // endaction
    endseq;


    let outPipeOut = dut.streamPipeOut;
    Stmt checkProc = (seq
        // Case 1
        action
            dut.streamPipeOut.deq;
            immAssert(outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
        endaction
        action
            dut.streamPipeOut.deq;
            immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
        endaction
        action
            dut.streamPipeOut.deq;
            immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
        endaction
        action
            dut.streamPipeOut.deq;
            immAssert(!outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 30, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
        endaction

        // Case 2
        action
            dut.streamPipeOut.deq;
            immAssert(outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 14, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
        endaction

        // // Case 3
        // action
        //     dut.streamPipeOut.deq;
        //     immAssert(outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 14, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
        // endaction
        $finish;
    endseq);

    FSM injectFSM <- mkFSM(injectProc);
    FSM checkFSM  <- mkFSM(checkProc);
    
    Reg#(Bool) goingReg <- mkReg(False);

    rule start (!goingReg);
        goingReg <= True;
        injectFSM.start;
        checkFSM.start;
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
