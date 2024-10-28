import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import Cntrs :: *;
import BRAMCore :: *;
import Arbiter :: * ;
import Connectable :: *;

import DataTypes :: *;
import RdmaHeaders :: *;
import PAClib :: *;
import ConnectableF :: *;
import PrimUtils :: *;
import PrioritySearchBuffer :: *;
import AxiBus :: *;
import DtldStream :: *;

import StreamShifterG :: *;
import GearBoxArbiter :: *;


typedef 16                                  FTILE_MAC_SEGMENT_CNT;
typedef TLog#(FTILE_MAC_SEGMENT_CNT)        FTILE_MAC_SEGMENT_IDX_WIDTH;
typedef Bit#(FTILE_MAC_SEGMENT_IDX_WIDTH)   FtileMacSegmentIdx;

typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentInframeSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentSopSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentEopSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentFcsErrorSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentSkipCrcSignalBundle;

typedef 3 FTILE_MAC_EOP_EMPTY_WIDTH;
typedef Bit#(FTILE_MAC_EOP_EMPTY_WIDTH) FtileMacEopEmpty;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileMacEopEmpty) SegmentEopEmptySignalBundle;

typedef 2 FTILE_RX_MAC_ERROR_WIDTH;
typedef Bit#(FTILE_RX_MAC_ERROR_WIDTH) FtileRxMacError;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileRxMacError) SegmentRxMacErrorSignalBundle;

typedef 3 FTILE_MAC_STATUS_DATA_WIDTH;
typedef Bit#(FTILE_MAC_STATUS_DATA_WIDTH) FtileMacStatusData;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileMacStatusData) SegmentStatusDataSignalBundle;

typedef 1 FTILE_TX_MAC_ERROR_WIDTH;
typedef Bit#(FTILE_TX_MAC_ERROR_WIDTH) FtileTxMacError;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileTxMacError) SegmentTxMacErrorSignalBundle;


typedef 1024 FTILE_MAC_DATA_BUNDLE_WIDTH;
typedef TDiv#(FTILE_MAC_DATA_BUNDLE_WIDTH, FTILE_MAC_SEGMENT_CNT)       FTILE_MAC_DATA_SEGMENT_WIDTH;    // 64
typedef TDiv#(FTILE_MAC_DATA_SEGMENT_WIDTH, BYTE_WIDTH)                 FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH;    // 8
typedef Bit#(FTILE_MAC_DATA_SEGMENT_WIDTH)                              FtileMacDataSegment;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileMacDataSegment)             FtileMacDataBusSegBundle;


typedef Bit#(TLog#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT)) DispatchChannelIdx;

typedef struct {
    FtileMacDataBusSegBundle        data;
    SegmentInframeSignalBundle      inframe;
    SegmentEopEmptySignalBundle     eop_empty;
    SegmentSopSignalBundle          sop;
    SegmentEopSignalBundle          eop;
    SegmentFcsErrorSignalBundle     fcs_error;
    SegmentRxMacErrorSignalBundle   error;
    SegmentStatusDataSignalBundle   status_data;
} FtileMacRxBeat deriving (Bits, FShow);

typedef struct {
    FtileMacDataBusSegBundle        data;
    SegmentInframeSignalBundle      inframe;
    SegmentEopEmptySignalBundle     eop_empty;
    SegmentSopSignalBundle          sop;
    SegmentSopSignalBundle          eop;
    SegmentTxMacErrorSignalBundle   error;
    SegmentSkipCrcSignalBundle      skip_crc;
} FtileMacTxBeat deriving (Bits, FShow);


interface FTileMacAdaptorRx;

    // input port
    (* prefix="" *)
    method Action setRxInputData(
        FtileMacDataBusSegBundle        data,
        Bool                            valid,
        SegmentInframeSignalBundle      inframe,
        SegmentEopEmptySignalBundle     eop_empty,
        SegmentFcsErrorSignalBundle     fcs_error,
        SegmentRxMacErrorSignalBundle   error,
        SegmentStatusDataSignalBundle   status_data
    );

    // output port
    method Bool                                 ready;
endinterface

interface FTileMacAdaptorTx;

    // input port
    (* prefix="" *)
    method Action setTxInputData(Bool ready);

    // output port
    method FtileMacDataBusSegBundle         data;
    method Bool                             valid;
    method SegmentInframeSignalBundle       inframe;
    method SegmentEopEmptySignalBundle      eop_empty;
    method SegmentTxMacErrorSignalBundle    error;
    method SegmentSkipCrcSignalBundle       skip_crc;
endinterface

interface FTileMacAdaptor;
    (* always_ready, always_enabled *)
    interface FTileMacAdaptorRx rx;

    (* always_ready, always_enabled *)
    interface FTileMacAdaptorTx tx;

    interface PipeOut#(FtileMacRxBeat) ftilemacRxPipeOut;
    interface PipeIn#(FtileMacTxBeat) ftilemacTxPipeIn;
endinterface

(* synthesize *)
module mkFTileMacAdaptor(FTileMacAdaptor);


    FIFOF#(FtileMacRxBeat) ftileMacRxPipeOutQueue <- mkUGFIFOF;
    FIFOF#(FtileMacTxBeat) ftileMacTxPipeInQueue <- mkUGFIFOF;

    Reg#(Bool) txReadySignalOutputReg <- mkReg(False);

    Bool txValid = ftileMacTxPipeInQueue.notEmpty && txReadySignalOutputReg;

    Reg#(Bool) previousRxBeatLastInframeSignalReg <- mkReg(False);
    Reg#(Bool) previousTxBeatLastInframeSignalReg <- mkReg(False);

    rule deq;
        if (txValid && ftileMacTxPipeInQueue.notEmpty) begin
            ftileMacTxPipeInQueue.deq;
        end
    endrule


    interface FTileMacAdaptorRx rx;
        // input port
        method Action setRxInputData(
            FtileMacDataBusSegBundle        data,
            Bool                            valid,
            SegmentInframeSignalBundle      inframe,
            SegmentEopEmptySignalBundle     eop_empty,
            SegmentFcsErrorSignalBundle     fcs_error,
            SegmentRxMacErrorSignalBundle   error,
            SegmentStatusDataSignalBundle   status_data
        );


            let mergedInframeSignal = {pack(inframe), pack(previousRxBeatLastInframeSignalReg)};
            SegmentSopSignalBundle sop;
            SegmentEopSignalBundle eop;
            for (Integer idx = 0; idx < valueOf(FTILE_MAC_SEGMENT_CNT); idx = idx + 1) begin
                sop[idx] = pack(mergedInframeSignal[idx] == 0 && mergedInframeSignal[idx + 1] == 1);
                eop[idx] = pack(mergedInframeSignal[idx] == 1 && mergedInframeSignal[idx + 1] == 0);
            end

            if ( valid ) begin
                let beat = FtileMacRxBeat {
                    data                    : data,
                    inframe                 : inframe,
                    eop_empty               : eop_empty,
                    sop                     : sop,
                    eop                     : eop,
                    fcs_error               : fcs_error,
                    error                   : error,
                    status_data             : status_data
                };

                immAssert(
                    ftileMacRxPipeOutQueue.notFull,
                    "ftileMacRxPipeOutQueue is Full",
                    $format("")
                );

                ftileMacRxPipeOutQueue.enq(beat);
            end
        endmethod

        // output port
        method Bool                                 ready               = True;  
    endinterface

    interface FTileMacAdaptorTx tx;
        // input port
        method Action setTxInputData(Bool ready);
            txReadySignalOutputReg <= ready;
        endmethod

        // output port
        
        method FtileMacDataBusSegBundle         data        = txValid ? ftileMacTxPipeInQueue.first.data        : unpack(0);
        method SegmentInframeSignalBundle       inframe     = txValid ? ftileMacTxPipeInQueue.first.inframe     : unpack(0);
        method SegmentEopEmptySignalBundle      eop_empty   = txValid ? ftileMacTxPipeInQueue.first.eop_empty   : unpack(0);
        method SegmentTxMacErrorSignalBundle    error       = txValid ? ftileMacTxPipeInQueue.first.error       : unpack(0);
        method SegmentSkipCrcSignalBundle       skip_crc    = txValid ? ftileMacTxPipeInQueue.first.skip_crc    : unpack(0);
        method Bool                             valid       = txValid;
    endinterface

    interface ftilemacRxPipeOut = ugToPipeOut(ftileMacRxPipeOutQueue);
    interface ftilemacTxPipeIn = ugToPipeIn(ftileMacTxPipeInQueue);
endmodule



typedef 3 FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT;
typedef Bit#(TLog#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT)) FtileMacRxPingPongMetaOutputChannelIdx;

typedef 4 FTILE_MAC_USER_LOGIC_CHANNEL_CNT;
typedef 256 FTILE_MAC_USER_LOGIC_DATA_WIDTH;

typedef TLog#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT) FTILE_MAC_USER_LOGIC_CHANNEL_IDX_WIDTH;
typedef Bit#(FTILE_MAC_USER_LOGIC_CHANNEL_IDX_WIDTH) FtileMacUserLogicChannelIdx;

typedef 1024 FTILE_MAC_RX_BRAM_BUFFER_DEPTH;
typedef TLog#(FTILE_MAC_RX_BRAM_BUFFER_DEPTH) FTILE_MAC_RX_BRAM_BUFFER_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_RX_BRAM_BUFFER_ADDR_WIDTH) FtileMaxRxBramBufferAddr;



typedef struct {
    FtileMaxRxBramBufferAddr        bufferAddr;         // 10
    SegmentEopEmptySignalBundle     eopEmpty;           // 48
    SegmentSopSignalBundle          sop;                // 16
    SegmentEopSignalBundle          eop;                // 16
    SegmentFcsErrorSignalBundle     fcsError;           // 16
    // SegmentRxMacErrorSignalBundle   error;          // 32
    // SegmentStatusDataSignalBundle   status_data;    // 48
} FtileMacRxPingPongSingleChannelProcessorInputMeta deriving(FShow, Bits);

typedef struct {
    FtileMaxRxBramBufferAddr        bufferAddr;                // 10
    FtileMacSegmentIdx              startSegIdx;                // 4
    FtileMacSegmentIdx              zeroBasedValidSegCnt;       // 4
    FtileMacEopEmpty                lastSegEmptyByteCnt;        // 3
    Bool                            isFirst;                    // 1
    Bool                            isLast;                     // 1
    Bool                            isError;                    // 1
} FtileMacRxPacketChunkMeta deriving(FShow, Bits);

typedef struct {
    Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, Maybe#(FtileMacRxPacketChunkMeta))    packetChunkMetaVector;
    Bool                                                                                packetNumOverflowAffectNextBeat;
} FtileMacRxPingPongSingleChannelProcessorOutputMeta deriving(FShow, Bits);


interface FtileMacRxPingPongSingleChannelProcessor;
    interface PipeIn#(FtileMacRxPingPongSingleChannelProcessorInputMeta)                        beatMetaPipeIn;
    interface PipeOut#(FtileMacRxPingPongSingleChannelProcessorOutputMeta)                      packetsChunkMetaPipeOut;
endinterface

(* synthesize *)
module mkFtileMacRxPingPongSingleChannelProcessor(FtileMacRxPingPongSingleChannelProcessor);
    FIFOF#(FtileMacRxPingPongSingleChannelProcessorInputMeta)  beatMetaPipeInQueue          <- mkFIFOF;
    FIFOF#(FtileMacRxPingPongSingleChannelProcessorOutputMeta) packetsChunkMetaPipeOutQueue <- mkFIFOF;

    Reg#(Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, Maybe#(FtileMacRxPacketChunkMeta))) outputMetaTmpBufferVecReg<- mkReg(replicate(tagged Invalid));


    Reg#(Bool)                                              isIdleReg                               <- mkReg(True);
    Reg#(FtileMacRxPingPongSingleChannelProcessorInputMeta) curProcessingMetaReg                    <- mkRegU;
    Reg#(Bool)                                              currentPacketHasErrorReg                <- mkReg(False);
    Reg#(FtileMacSegmentIdx)                                curProcessingSegIdxReg                  <- mkReg(0);
    Reg#(FtileMacSegmentIdx)                                curFirstSegIdxForThisPacketReg          <- mkReg(0);
    Reg#(FtileMacSegmentIdx)                                zeroBasedValidSegCntForPacketReg        <- mkReg(0);
    Reg#(FtileMacRxPingPongMetaOutputChannelIdx)            curOutChannelIdxReg                     <- mkReg(0);
    Reg#(Bool)                                              isPacketNotEndReg                       <- mkReg(False);
    Reg#(Bool)                                              isPacketNumOverflowReg                  <- mkReg(False);
    // since different ping-pong channel doesn't know the state of other ping-pong channel, the isFirstForOutputReg signal
    // is inited to False. Suppose a packet cross two beat, the sop is in the first beat, which is processed by the first ping-pong channel.
    // when the second beat is handled by the second ping-pong channel, it must output isFirst set to False.
    // So, the total rule is like this: the isPacketNumOverflowReg is turned to False at the start of each beat, then, when it meets a sop flag,
    // it keeps True until to the end of this beat.
    Reg#(Bool)                                              isFirstForOutputReg                     <- mkReg(False);
    Reg#(Bool)                                              hasMetEopButNotSopReg                   <- mkReg(False);
    rule handle;
        let currentMeta;
        let curProcessingSegIdx;
        let zeroBasedValidSegCntForPacket;
        let curOutChannelIdx;
        let isPacketNumOverflow;
        let startSegIdx;
        let isFirstForOutput;
        let hasMetEopButNotSop;
        let tmpMetaBufferVec;
        if (isIdleReg) begin
            isIdleReg <= False;
            currentMeta             = beatMetaPipeInQueue.first;
            beatMetaPipeInQueue.deq;
            curProcessingSegIdx     = 0;
            zeroBasedValidSegCntForPacket  = 0;
            curOutChannelIdx        = 0;
            isPacketNumOverflow     = False;
            startSegIdx             = 0;
            isFirstForOutput        = False;
            hasMetEopButNotSop      = False;
            tmpMetaBufferVec        = replicate(tagged Invalid);
        end
        else begin
            currentMeta                         = curProcessingMetaReg;
            curProcessingSegIdx                 = curProcessingSegIdxReg;
            zeroBasedValidSegCntForPacket       = zeroBasedValidSegCntForPacketReg;
            curOutChannelIdx                    = curOutChannelIdxReg;
            isPacketNumOverflow                 = isPacketNumOverflowReg;
            startSegIdx                         = curFirstSegIdxForThisPacketReg;
            isFirstForOutput                    = isFirstForOutputReg;
            hasMetEopButNotSop                  = hasMetEopButNotSopReg;
            tmpMetaBufferVec                    = outputMetaTmpBufferVecReg;
        end
            
        FtileMacEopEmpty                lastSegEmptyByteCnt         = truncate(pack(currentMeta.eopEmpty));    
        Bool                            sopFlag                     = unpack(lsb(currentMeta.sop));                    
        Bool                            eopFlag                     = unpack(lsb(currentMeta.eop));                     
        Bool                            isError                     = unpack(lsb(currentMeta.fcsError));                    
        

        
        case ({pack(eopFlag), pack(sopFlag)})
            2'b00: begin // middle or empty
                // Nothing to do
            end
            2'b01: begin // first
                zeroBasedValidSegCntForPacket = 0;
                startSegIdx = curProcessingSegIdx;
                isFirstForOutput = True;
                hasMetEopButNotSop = False;
            end
            2'b10: begin // last
                hasMetEopButNotSop = True;
            end
            2'b11: begin // only
                immFail(
                    "should not reach here. FTile can't output sop and eop in the same segment",
                    $format("")
                );
            end
        endcase

        let outPacketMeta = FtileMacRxPacketChunkMeta {
            bufferAddr                  : currentMeta.bufferAddr,
            startSegIdx                 : startSegIdx,
            zeroBasedValidSegCnt        : zeroBasedValidSegCntForPacket,
            lastSegEmptyByteCnt         : lastSegEmptyByteCnt,
            isFirst                     : isFirstForOutput,
            isLast                      : eopFlag,
            isError                     : isError
        };

        zeroBasedValidSegCntForPacket = zeroBasedValidSegCntForPacket + 1;

        Bool isLastSegInThisBeat = curProcessingSegIdxReg == fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT) - 1);
        Bool needOutputOutputMeta = (isLastSegInThisBeat && !hasMetEopButNotSop) || eopFlag;
        
        
        if (needOutputOutputMeta) begin
            if (curOutChannelIdx == fromInteger(valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT))) begin
                isPacketNumOverflow = True;
            end
            
            if (!isPacketNumOverflow) begin
                tmpMetaBufferVec[curOutChannelIdx] = tagged Valid outPacketMeta;
                curOutChannelIdx = curOutChannelIdx + 1;

                $display(
                    "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongSingleChannelProcessor handle output to meta buffer"),
                    toBlue(", outPacketMeta="), fshow(outPacketMeta)
                );
            end
        end

        if (isLastSegInThisBeat) begin
            // if this is the last segment of both the beat and the packet, 
            // then this overflow won't affact next beat in the next sibling ping-pong channel
            // another case is that, it already overflowed, but the last segment is not used 
            // (i.e., the last overflow packet end before the last segment). For example, for a 16-seg beat,
            // there are 4 eop in seg 2, 4, 6, 8, and seg 9-15 doesn't have data, in this case, the beat is 
            // overflowed, but the seg 15 is not eop. In this case, the error should not affact next beat.
            Bool packetNumOverflowAffectNextBeat = hasMetEopButNotSop ? False : isPacketNumOverflow;
            
            Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, 
                Maybe#(FtileMacRxPacketChunkMeta))    packetChunkMetaVector = newVector;

            for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT); idx = idx + 1) begin
                packetChunkMetaVector[idx] = tmpMetaBufferVec[idx];
            end

            let outputMeta = FtileMacRxPingPongSingleChannelProcessorOutputMeta {
                packetChunkMetaVector: packetChunkMetaVector,
                packetNumOverflowAffectNextBeat: packetNumOverflowAffectNextBeat
            }; 

            packetsChunkMetaPipeOutQueue.enq(outputMeta);
        end

        currentMeta.eopEmpty    = unpack(pack(currentMeta.eopEmpty)  >> valueOf(FTILE_MAC_EOP_EMPTY_WIDTH));
        currentMeta.sop         = unpack(pack(currentMeta.sop)       >> valueOf(SizeOf#(Bool)));        
        currentMeta.eop         = unpack(pack(currentMeta.eop)       >> valueOf(SizeOf#(Bool)));
        currentMeta.fcsError   = unpack(pack(currentMeta.fcsError) >> valueOf(SizeOf#(Bool)));

        if (curProcessingSegIdx == maxBound) begin
            isIdleReg <= True;
        end
        
        curProcessingSegIdxReg              <= curProcessingSegIdx + 1;
        curFirstSegIdxForThisPacketReg      <= startSegIdx;
        curProcessingMetaReg                <= currentMeta;
        zeroBasedValidSegCntForPacketReg    <= zeroBasedValidSegCntForPacket;
        curOutChannelIdxReg                 <= curOutChannelIdx;
        isPacketNumOverflowReg              <= isPacketNumOverflow;
        isFirstForOutputReg                 <= isFirstForOutput;
        hasMetEopButNotSopReg               <= hasMetEopButNotSop;
        outputMetaTmpBufferVecReg           <= tmpMetaBufferVec;

        $display(
            "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongSingleChannelProcessor handle"),
            toBlue(", curProcessingSegIdx="), fshow(curProcessingSegIdx),
            toBlue(", startSegIdx="), fshow(startSegIdx),
            toBlue(", curProcessingMeta="), fshow(currentMeta),
            toBlue(", zeroBasedValidSegCntForPacket="), fshow(zeroBasedValidSegCntForPacket),
            toBlue(", curOutChannelIdx="), fshow(curOutChannelIdx),
            toBlue(", isPacketNumOverflow="), fshow(isPacketNumOverflow),
            toBlue(", isFirstForOutput="), fshow(isFirstForOutput),
            toBlue(", hasMetEopButNotSop="), fshow(hasMetEopButNotSop)
        );
    endrule



    interface beatMetaPipeIn = toPipeIn(beatMetaPipeInQueue);
    interface packetsChunkMetaPipeOut = toPipeOut(packetsChunkMetaPipeOutQueue);
endmodule


typedef FTILE_MAC_SEGMENT_CNT FTILE_MAC_RX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT)) FtileMacRxPingPongChannelIdx;

typedef struct {
    FtileMaxRxBramBufferAddr addr;
    FtileMacDataBusSegBundle data;
} FtileMacRxBramBufferWriteReq deriving (FShow, Bits);


interface FtileMacRxBeatFork;
    interface PipeIn#(FtileMacRxBeat)                                                           rxBetaPipeIn;
    interface Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
                      PipeOut#(FtileMacRxPingPongSingleChannelProcessorInputMeta))              rxPingPongChannelMetaPipeOutVec;
    interface PipeOut#(FtileMacRxBramBufferWriteReq)                                            rxBramWriteReqPipeOut;
endinterface


(* synthesize *)
module mkFtileMacRxBeatFork(FtileMacRxBeatFork);
    
    FIFOF#(FtileMacRxBeat)                                                  rxBetaPipeInQueue                   <- mkFIFOF;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
            PipeOut#(FtileMacRxPingPongSingleChannelProcessorInputMeta))    rxPingPongChannelMetaPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
            FIFOF#(FtileMacRxPingPongSingleChannelProcessorInputMeta))      rxPingPongChannelMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    FIFOF#(FtileMacRxBramBufferWriteReq)                                    rxBramWriteReqPipeOutQueue          <- mkFIFOF;

    Reg#(FtileMaxRxBramBufferAddr) addrPtrReg <- mkReg(0);

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        rxPingPongChannelMetaPipeOutVecInst[idx] = toPipeOut(rxPingPongChannelMetaPipeOutQueueVec[idx]);
    end

    Reg#(FtileMacRxPingPongChannelIdx) channelIdxReg <- mkReg(0);

    rule handleInputBeat;
        let rxBeat = rxBetaPipeInQueue.first;
        rxBetaPipeInQueue.deq;
        
        let outMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
            bufferAddr      : addrPtrReg,
            eopEmpty        : rxBeat.eop_empty,  
            sop             : rxBeat.sop,       
            eop             : rxBeat.eop,       
            fcsError        : rxBeat.fcs_error  
        };
        rxPingPongChannelMetaPipeOutQueueVec[channelIdxReg].enq(outMeta);

        let bramWriteReq = FtileMacRxBramBufferWriteReq {
            addr    : addrPtrReg,
            data    : rxBeat.data
        };
        rxBramWriteReqPipeOutQueue.enq(bramWriteReq);

        addrPtrReg      <= addrPtrReg    + 1;
        channelIdxReg   <= channelIdxReg + 1;
    endrule
    

    interface rxBetaPipeIn                      = toPipeIn(rxBetaPipeInQueue);
    interface rxPingPongChannelMetaPipeOutVec   = rxPingPongChannelMetaPipeOutVecInst;
    interface rxBramWriteReqPipeOut             = toPipeOut(rxBramWriteReqPipeOutQueue);
endmodule







interface FTileMac;
    interface PipeIn#(FtileMacRxBeat) ftilemacRxPipeIn;
    interface PipeOut#(FtileMacTxBeat) ftilemacTxPipeOut;
endinterface


(* synthesize *)
module mkFTileMac(FTileMac);
    // FIFOF#(FtileMacRxBeat) ftilemacRxPipeInQueue    <- mkFIFOF;
    FIFOF#(FtileMacTxBeat) ftilemacTxPipeOutQueue   <- mkFIFOF;

    let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);
    end

    interface ftilemacRxPipeIn  = ftileMacRxBeatFork.rxBetaPipeIn;
    interface ftilemacTxPipeOut = toPipeOut(ftilemacTxPipeOutQueue);
endmodule

typedef Vector#(
    FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
    PipeIn#(FtileMacRxPingPongSingleChannelProcessorOutputMeta)) FtileMacRxPingPongChannelMetaJoinInputIfc;


// each beat(packet chunk) is 128B, for 4kB packet, it uses about 32 chunk meta. To buffer about 4 4kB packet, use a 128 depth.
typedef 128 PACKET_CHUNK_META_OUTPUT_BUFFER_DEPTH;

// to select the most empty channel to dispatch, need to track the segment count in each output channel. Each 4kB packet has 512 8Byte segments,
// so, we decide to use a max counter value that can hold about four 4kB packets, that is 512 * 4 = 2048
typedef TLog#(2048) PACKET_BEAT_SEG_COUNTER_MAX_VALUE_WIDTH;
typedef Bit#(PACKET_BEAT_SEG_COUNTER_MAX_VALUE_WIDTH) PacketBeatSegCnt;

typedef struct {
    FtileMacUserLogicChannelIdx         targetChannelIdx;
    Maybe#(FtileMacRxPacketChunkMeta)   packetChunkMetaMaybe;
} FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry deriving(Bits, FShow);

interface FtileMacRxPingPongChannelMetaJoin;
    interface FtileMacRxPingPongChannelMetaJoinInputIfc metaPipeInVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxPacketChunkMeta)) packetChunkMetaPipeOutVec;
endinterface

(* synthesize *)
module mkFtileMacRxPingPongChannelMetaJoin(FtileMacRxPingPongChannelMetaJoin);

    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FIFOF#(FtileMacRxPingPongSingleChannelProcessorOutputMeta)) metaPipeInQueueVec <- replicateM(mkFIFOF);
    FtileMacRxPingPongChannelMetaJoinInputIfc metaPipeInVecInst = newVector; 

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacRxPacketChunkMeta))    packetChunkMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxPacketChunkMeta))  packetChunkMetaPipeOutVecInst  = newVector; 

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        metaPipeInVecInst[idx] = toPipeIn(metaPipeInQueueVec[idx]);
    end

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        packetChunkMetaPipeOutVecInst[idx] = toPipeOut(packetChunkMetaPipeOutQueueVec[idx]);
    end


    Reg#(FtileMacRxPingPongChannelIdx) pingPongChannelIdxReg <- mkReg(0);

    Reg#(Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacUserLogicChannelIdx)) curUserLogicChannelDispatchOrderReg <- mkReg(vec(0, 1, 2, 3));
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Reg#(Bool)) outputChannelErrorFlagRegVec <- replicateM(mkReg(False));


    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacRxPacketChunkMeta)) packetChunkMetaOutputBufferVec <- replicateM(mkSizedFIFOF(valueOf(PACKET_CHUNK_META_OUTPUT_BUFFER_DEPTH)));
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Count#(PacketBeatSegCnt)) outputChannelBufferUsedSegCounterVec <- replicateM(mkCount(0));

    // Pipeline FIFOs
    FIFOF#(FtileMacRxPingPongSingleChannelProcessorOutputMeta) selectedPingPongOutputChannelMetaPipelineQ <- mkFIFOF;
    FIFOF#(Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry)) dispatchPacketChunkMetaPipelineQ <- mkFIFOF;

    rule selectandForwardPingPongChannel;
        pingPongChannelIdxReg <= pingPongChannelIdxReg + 1;

        let pingPongOutputMeta = metaPipeInQueueVec[pingPongChannelIdxReg].first;
        metaPipeInQueueVec[pingPongChannelIdxReg].deq;

        selectedPingPongOutputChannelMetaPipelineQ.enq(pingPongOutputMeta);
    endrule

    rule dispatchToOutputChannel;
        let pipelineInputEntry = dispatchPacketChunkMetaPipelineQ.first;
        dispatchPacketChunkMetaPipelineQ.deq;

        for (Integer userChannelIdx = 0; userChannelIdx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); userChannelIdx = userChannelIdx + 1) begin
            Maybe#(FtileMacRxPacketChunkMeta) metaToOutputMaybe = tagged Invalid;
            
            for (Integer srcIdx = 0; srcIdx < valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT); srcIdx = srcIdx + 1) begin
                let dispatchTargetInfo = pipelineInputEntry[srcIdx];
                if (dispatchTargetInfo.targetChannelIdx == fromInteger(userChannelIdx)) begin
                    metaToOutputMaybe = dispatchTargetInfo.packetChunkMetaMaybe;
                end
            end

            if (metaToOutputMaybe matches tagged Valid .metaToOutput) begin
                packetChunkMetaOutputBufferVec[userChannelIdx].enq(metaToOutput);
                outputChannelBufferUsedSegCounterVec[userChannelIdx].incr(zeroExtend(metaToOutput.zeroBasedValidSegCnt)+1);
            end            
        end 
    endrule

    interface metaPipeInVec             = metaPipeInVecInst;
    interface packetChunkMetaPipeOutVec = packetChunkMetaPipeOutVecInst;
endmodule


// typedef 3 FTILE_MAC_TX_MAX_PACKET_CNT;
// typedef FTILE_MAC_TX_MAX_PACKET_CNT FTILE_MAC_TX_HANDLER_CNT;
// typedef TLog#(FTILE_MAC_TX_HANDLER_CNT) FTILE_MAC_TX_HANDLER_IDX_WIDTH;
// typedef Bit#(FTILE_MAC_TX_HANDLER_IDX_WIDTH) FtileMacTxHandlerIdx;


// typedef struct {
//     FtileMacRxBeat rxBeat;
//     FtileMacSegmentIdx startSegIdx;
// } RawFtileMacRxStreamWithMeta deriving(Bits, FShow);


// typedef Bit#(FTILE_MAC_DATA_BUNDLE_WIDTH) FtileMacDataStreamDataLsbRight;
// typedef Bit#(FTILE_MAC_DATA_BUNDLE_WIDTH) FtileMacDataStreamDataLsbLeft;
// typedef TDiv#(FTILE_MAC_DATA_BUNDLE_WIDTH, BYTE_WIDTH) FTILE_MAC_TLP_DATA_BUNDLE_BYTE_CNT;
// typedef Bit#(TAdd#(1, TLog#(FTILE_MAC_TLP_DATA_BUNDLE_BYTE_CNT))) FtileMacDataStreamByteCnt;
// typedef Bit#(TLog#(TDiv#(FTILE_MAC_DATA_BUNDLE_WIDTH, BYTE_WIDTH))) FtileMacDataStreamByteIdx;

// typedef DtldStreamData#(FtileMacDataStreamDataLsbRight) FtileMacDataStreamLsbRight;
// typedef DtldStreamData#(FtileMacDataStreamDataLsbLeft) FtileMacDataStreamLsbLeft;


// interface FtileMacRxStreamSegmentFork;
//     interface PipeIn#(FtileMacRxBeat) ftilemacRxPipeIn;
//     interface Vector#(FTILE_MAC_RX_HANDLER_CNT, PipeOut#(FtileMacDataStreamLsbRight)) tlpDataStreamPipeOutVec;
//     interface Vector#(FTILE_MAC_RX_HANDLER_CNT, PipeOut#(RawFtileMacRxTlpWithMeta)) tlpHeaderPipeOutVec;
// endinterface

// (* synthesize *)
// module mkFtileMacRxStreamSegmentFork(FtileMacRxStreamSegmentFork);
//     FIFOF#(FtileMacRxBeat) ftilemacRxPipeInQueue <- mkFIFOF;

//     Reg#(FtileMacRxHandlerIdx) curPrimHandlerIdxReg <- mkReg(0);

//     Vector#(FTILE_MAC_RX_HANDLER_CNT, FIFOF#(FtileMacDataStreamLsbRight)) tlpDataStreamPipeOutQueueVec <- replicateM(mkFIFOF);
//     Vector#(FTILE_MAC_RX_HANDLER_CNT, FIFOF#(RawFtileMacRxTlpWithMeta)) tlpHeaderPipeOutQueueVec <- replicateM(mkFIFOF);

//     Vector#(FTILE_MAC_RX_HANDLER_CNT, PipeOut#(FtileMacDataStreamLsbRight)) tlpDataStreamPipeOutInstVec = newVector;
//     Vector#(FTILE_MAC_RX_HANDLER_CNT, PipeOut#(RawFtileMacRxTlpWithMeta)) tlpHeaderPipeOutInstVec = newVector;

//     for (Integer handlerIdx = 0; handlerIdx < valueOf(FTILE_MAC_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
//         tlpDataStreamPipeOutInstVec[handlerIdx] = toPipeOut(tlpDataStreamPipeOutQueueVec[handlerIdx]);
//         tlpHeaderPipeOutInstVec[handlerIdx] = toPipeOut(tlpHeaderPipeOutQueueVec[handlerIdx]);
//     end

//     Reg#(Bool) prevTlpSpanNextBeatReg <- mkReg(False);

//     Vector#(FTILE_MAC_RX_HANDLER_CNT, FIFOF#(RawFtileMacRxStreamWithMeta)) handlerInputQueueVec <- replicateM(mkFIFOF);

//     Vector#(FTILE_MAC_RX_HANDLER_CNT, Reg#(FtileMacTlpDataByteLen)) streamByteRemainingRegVec <- replicateM(mkRegU);

//     RWire#(Vector#(FTILE_MAC_RX_HANDLER_CNT, Maybe#(FtileMacSegmentIdx))) tlpFirstSegmentIdxVecWire <- mkRWire;
//     Wire#(FtileMacRxBeat) beatPassthroughWire <- mkWire;
//     Wire#(FtileMacRxHandlerIdx) curPrimHandlerIdxPassthroughWire <- mkWire;


//     // need this gurad condition since the tlpFirstSegmentIdxVecWire's signal must be consumed in current beat, so we must ensure the consumer not blocked.
//     let preCalcRxBeatMetaRule = (rules
//     rule preCalcRxBeatMeta if (handlerInputQueueVec[0].notFull && handlerInputQueueVec[1].notFull && handlerInputQueueVec[2].notFull);

//         let beat = ftilemacRxPipeInQueue.first;
//         ftilemacRxPipeInQueue.deq;

//         beatPassthroughWire <= beat;

//         Bool isTlpSpanNextBeat = case (pack(beat.eop)) matches
//             'b1???: False;
//             'b01??: (beat.sop[3] == 1);
//             'b001?: (beat.sop[3] == 1 || beat.sop[2] == 1);
//             'b0001: (beat.sop[3] == 1 || beat.sop[2] == 1 || beat.sop[1] == 1);
//             'b0000: ((pack(beat.dvalid) != 0) ? True : False);  // for example, all tlp in this beat are read req, which has no data.
//         endcase;

//         prevTlpSpanNextBeatReg <= isTlpSpanNextBeat;

//         FtileMacSegmentIdx tlpCnt = case (pack(beat.hvalid)) matches
//             'b0000: (prevTlpSpanNextBeatReg ? 1 : 0);
//             'b0001: (prevTlpSpanNextBeatReg ? 0 : 1);
//             'b0010: (prevTlpSpanNextBeatReg ? 2 : 1);
//             'b0011: (prevTlpSpanNextBeatReg ? 0 : 2);
//             'b0100: (prevTlpSpanNextBeatReg ? 2 : 0);
//             'b0101: (prevTlpSpanNextBeatReg ? 0 : 2);
//             'b0110: (prevTlpSpanNextBeatReg ? 3 : 2);
//             'b0111: (prevTlpSpanNextBeatReg ? 0 : 3);
//             'b1000: (prevTlpSpanNextBeatReg ? 2 : 0);
//             'b1001: (prevTlpSpanNextBeatReg ? 0 : 2);
//             'b1010: (prevTlpSpanNextBeatReg ? 3 : 2);
//             'b1011: (prevTlpSpanNextBeatReg ? 0 : 3);
//             'b1100: (prevTlpSpanNextBeatReg ? 3 : 0);
//             'b1101: (prevTlpSpanNextBeatReg ? 0 : 3);
//             'b1110: (prevTlpSpanNextBeatReg ? 0 : 3);
//             'b1111: (prevTlpSpanNextBeatReg ? 0 : 0);
//         endcase;
//         immAssert(
//             tlpCnt != 0,
//             "one of the following 3 assumption not hold: \n \
//                1.The R-Tile FtileMac IP does not use segment 2 and segment 3 if segment 0 AND segment 1 are unused \n\
//                2.At most 3 TLPs in a beat\n\
//                3.When Sop occur at seg0, then the prevTlpSpanNextBeatReg must be False",
//             $format("prevTlpSpanNextBeatReg=", fshow(prevTlpSpanNextBeatReg), "beat=", fshow(beat))
//         );


//         Vector#(FTILE_MAC_RX_HANDLER_CNT, Maybe#(FtileMacSegmentIdx)) tlpFirstSegmentIdxVec = case (pack(beat.hvalid)) matches
//             'b0000: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Invalid, tagged Invalid) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
//             'b0001: vec(tagged Valid 0, tagged Invalid, tagged Invalid);
//             'b0010: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 1, tagged Invalid) : vec(tagged Valid 1, tagged Invalid, tagged Invalid));
//             'b0011: vec(tagged Valid 0, tagged Valid 1, tagged Invalid);
//             'b0100: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 2, tagged Invalid) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
//             'b0101: vec(tagged Valid 0, tagged Valid 2, tagged Invalid);
//             'b0110: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 1, tagged Valid 2) : vec(tagged Valid 1, tagged Valid 2, tagged Invalid));
//             'b0111: vec(tagged Valid 0, tagged Valid 1, tagged Valid 2);
//             'b1000: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 3, tagged Invalid) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
//             'b1001: vec(tagged Valid 0, tagged Valid 3, tagged Invalid);
//             'b1010: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 1, tagged Valid 3) : vec(tagged Valid 1, tagged Valid 3, tagged Invalid));
//             'b1011: vec(tagged Valid 0, tagged Valid 1, tagged Valid 3);
//             'b1100: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 2, tagged Valid 3) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
//             'b1101: vec(tagged Valid 0, tagged Valid 2, tagged Valid 3);
//             'b1110: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Invalid, tagged Invalid) : vec(tagged Valid 1, tagged Valid 2, tagged Valid 3));
//             'b1111: vec(tagged Invalid, tagged Invalid, tagged Invalid);
//         endcase;

//         tlpFirstSegmentIdxVecWire.wset(tlpFirstSegmentIdxVec);
//         curPrimHandlerIdxPassthroughWire <= curPrimHandlerIdxReg;

//         // $display(
//         //     "time=%0t:", $time,
//         //     "isTlpSpanNextBeat=", fshow(isTlpSpanNextBeat),
//         //     ", tlpCnt=", fshow(tlpCnt),
//         //     ", tlpFirstSegmentIdxVec=", fshow(tlpFirstSegmentIdxVec)
//         // );

//         let nextPrimHandlerIdxWide = {1'b0, pack(curPrimHandlerIdxReg)};
//         nextPrimHandlerIdxWide = nextPrimHandlerIdxWide + zeroExtend(tlpCnt);
//         if (prevTlpSpanNextBeatReg) begin
//             nextPrimHandlerIdxWide = nextPrimHandlerIdxWide - 1;
//         end

//         if (nextPrimHandlerIdxWide > 3) begin
//             nextPrimHandlerIdxWide = nextPrimHandlerIdxWide - 3;
//         end
//         curPrimHandlerIdxReg <= truncate(nextPrimHandlerIdxWide);

//     endrule
//     endrules);

//     Vector#(FTILE_MAC_RX_HANDLER_CNT, Rules) outputRulesVec = newVector;
//     for (Integer handlerIdx = 0; handlerIdx < valueOf(FTILE_MAC_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
//         outputRulesVec[handlerIdx] = (rules 
//             rule dispatchSegmentToHandlers;
                
//                 let beat = beatPassthroughWire;
//                 // $display(
//                 //     "time=%0t:", $time,
//                 //     "dispatchSegmentToHandlers idx=%d", handlerIdx,
//                 //     "tlpFirstSegmentIdxVecWire.wget = ", fshow(tlpFirstSegmentIdxVecWire.wget)
//                 // );

//                 if (tlpFirstSegmentIdxVecWire.wget matches tagged Valid .tlpFirstSegmentIdxVec) begin
//                     // $display("dispatchSegmentToHandlers first level idx=%d", handlerIdx, ", tlpFirstSegmentIdxVec=", fshow(tlpFirstSegmentIdxVec));

//                     if (tlpFirstSegmentIdxVec[handlerIdx] matches tagged Valid .startSegIdx) begin
//                         let ent = RawFtileMacRxStreamWithMeta {
//                             rxBeat: beat,
//                             startSegIdx: startSegIdx
//                         };

//                         let curPrimHandlerIdxWide = {1'b0, pack(curPrimHandlerIdxPassthroughWire)};
//                         curPrimHandlerIdxWide = curPrimHandlerIdxWide + fromInteger(handlerIdx);
//                         if (curPrimHandlerIdxWide > fromInteger(valueOf(FTILE_MAC_RX_HANDLER_CNT) - 1)) begin
//                             curPrimHandlerIdxWide = curPrimHandlerIdxWide - fromInteger(valueOf(FTILE_MAC_RX_HANDLER_CNT) - 1);
//                         end

//                         FtileMacRxHandlerIdx curPrimHandlerIdx = truncate(curPrimHandlerIdxWide);

//                         handlerInputQueueVec[curPrimHandlerIdx].enq(ent);

//                         // $display(
//                         //     "time=%0t:", $time, toGreen(" mkFtileMacRxStreamSegmentFork dispatchSegmentToHandlers"),
//                         //     toBlue(", handlerIdx="), "%d", handlerIdx,
//                         //     toBlue(", ent="), fshow(ent)
//                         // );
//                     end
//                 end
//             endrule
//         endrules);
//     end

//     addRules(rJoinConflictFree(preCalcRxBeatMetaRule, rJoinConflictFree(outputRulesVec[0], rJoinConflictFree(outputRulesVec[1], outputRulesVec[2]))));


//     for (Integer handlerIdx = 0; handlerIdx < valueOf(FTILE_MAC_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
//         rule rawFtileMacRxInputToInternalDataType;
//             let beat = handlerInputQueueVec[handlerIdx].first;
//             handlerInputQueueVec[handlerIdx].deq;

//             let sopBundle = beat.rxBeat.sop;
//             let eopBundle = beat.rxBeat.eop;
//             let hvalidBundle = beat.rxBeat.hvalid;
//             let dvalidBundle = beat.rxBeat.dvalid;


//             // TODO: must check the relationship between sop and hvalid. for TLP without data, will sop be assert?
//             //       can hvalid be used as signal for the start of a new TLP?
//             let isFirst = hvalidBundle[beat.startSegIdx] == 1;

//             // for non-first beat, if there is at least one eop, then this beat must be eop.
//             Bool notFirstBeatIsEop = pack(eopBundle) != 0;

//             Bool firstBeatIsEop = case (beat.startSegIdx)
//                 0: (eopBundle[3:0] != 0);
//                 1: (eopBundle[3:1] != 0);
//                 2: (eopBundle[3:2] != 0);
//                 3: (eopBundle[3:3] != 0);
//             endcase;

//             Bool isLast = isFirst ? firstBeatIsEop : notFirstBeatIsEop;

//             let tlpDataLenMaybe = getDataLenFromTlpHeader(beat.rxBeat.header[beat.startSegIdx]);
//             immAssert(
//                 isValid(tlpDataLenMaybe),
//                 "unsupported TLP",
//                 $format("beat=", fshow(beat))
//             );
//             let tlpDataLen = fromMaybe(0, tlpDataLenMaybe);

//             let tlpDataLenInDw = getPayloadLengthInDW(beat.rxBeat.header[beat.startSegIdx]);
//             let tlpDataLenInByteAlignToDW = tlpDataLenInDw << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);

//             FtileMacDataStreamByteCnt byteNum = truncate(streamByteRemainingRegVec[handlerIdx]);
//             FtileMacDataStreamByteIdx startByteIdx = 0;
//             if (isFirst) begin
//                 case (beat.startSegIdx) matches
//                     0: begin
//                         startByteIdx = fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 0);
//                         byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 4);
//                     end
//                     1: begin
//                         startByteIdx = fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 1);
//                         byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 3);
//                     end
//                     2: begin
//                         startByteIdx = fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 2);
//                         byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 2);
//                     end
//                     3: begin
//                         startByteIdx = fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 3);
//                         byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH) * 1);
//                     end
//                 endcase
//                 streamByteRemainingRegVec[handlerIdx] <= tlpDataLenInByteAlignToDW - zeroExtend(byteNum);
//             end

//             let ds = FtileMacDataStreamLsbRight {
//                 data: pack(beat.rxBeat.data),
//                 byteNum: byteNum,
//                 startByteIdx: startByteIdx,
//                 isFirst: isFirst,
//                 isLast: isLast
//             };
            
//             if (isFirst) begin
//                 let tlpWithMeta = RawFtileMacRxTlpWithMeta {
//                     rawTlpHeader: beat.rxBeat.header[beat.startSegIdx],
//                     startSegIdx: beat.startSegIdx
//                 };
//                 tlpHeaderPipeOutQueueVec[handlerIdx].enq(tlpWithMeta);
//             end

//             if (dvalidBundle[beat.startSegIdx] == 1) begin
//                 tlpDataStreamPipeOutQueueVec[handlerIdx].enq(ds);
//             end
//         endrule
//     end


//     interface ftilemacRxPipeIn = toPipeIn(ftilemacRxPipeInQueue);
//     interface tlpDataStreamPipeOutVec = tlpDataStreamPipeOutInstVec;
//     interface tlpHeaderPipeOutVec = tlpHeaderPipeOutInstVec;
// endmodule


// function Bool isFtileMacTlpHasPayload(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacHeaderFieldFmt fmt = unpack(truncateLSB(tlpBuffer));
//     return fmt == `FTILE_MAC_TLP_HEADER_FMT_4DW_WITH_DATA || fmt == `FTILE_MAC_TLP_HEADER_FMT_3DW_WITH_DATA;
// endfunction

// function FtileMacTlpHeaderCommon getFtileMacTlpHeaderCommon(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacTlpHeaderCommon headerFirstDW = unpack(truncateLSB(tlpBuffer));
//     return headerFirstDW;
// endfunction

// function Bool isFtileMacTlpReadCplt(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacTlpHeaderCommon headerFirstDW = getFtileMacTlpHeaderCommon(tlpBuffer);
//     return (headerFirstDW.fmt == `FTILE_MAC_TLP_HEADER_FMT_3DW_WITH_DATA) && (headerFirstDW.typ == `FTILE_MAC_TLP_HEADER_TYPE_CPL_WITH_DATA);
// endfunction

// function FtileMacHeaderFieldExtendedTag getExtendedTagFromTlpCpltHeader(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
//     return unpack(truncate({pack(tlpHeader.commonHeader.t9), pack(tlpHeader.commonHeader.t8), pack(tlpHeader.tag)}));
// endfunction

// function Bool isFtileMacTlpLastReadCplt(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
//     let tlpDataLenMaybe = getDataLenFromTlpHeader(tlpBuffer);

//     FtileMacTlpDataByteLen extendedByteCount = zeroExtend(tlpHeader.byteCount);
//     extendedByteCount[valueOf(FTILE_MAC_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

//     let tlpDataLen = fromMaybe(0, tlpDataLenMaybe);
//     return extendedByteCount == tlpDataLen;
// endfunction




// function FtileMacTlpDataByteLen getPayloadLengthInDW(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacTlpHeaderCommon headerFirstDW = getFtileMacTlpHeaderCommon(tlpBuffer);
//     FtileMacTlpDataByteLen length = zeroExtend(headerFirstDW.length);
//     length[valueOf(SizeOf#(FtileMacHeaderFieldLength))] = pack(headerFirstDW.length == 0);  // length == 0 means 4096 bytes
//     return length;
// endfunction

// function Maybe#(FtileMacTlpDataByteLen) getDataLenFromTlpHeader(FtileMacTlpHeaderBuffer tlpBuffer);
//     FtileMacTlpHeaderCommon headerFirstDW = getFtileMacTlpHeaderCommon(tlpBuffer);

//     FtileMacTlpDataByteLen length = getPayloadLengthInDW(tlpBuffer);
//     length = length << 2; // convert from DW to Byte

//     if (!isFtileMacTlpHasPayload(tlpBuffer)) begin
//         return tagged Invalid;
//     end
//     else begin
//         if (headerFirstDW.typ == `FTILE_MAC_TLP_HEADER_TYPE_MEM_WRITE) begin
//             FtileMacTlpHeaderMemoryAccess tlpHeader = unpack(truncateLSB(tlpBuffer));
//             Bit#(3) subValFirstBe = case (pack(tlpHeader.firstDwBe)) matches
//                 4'b???1: 0;
//                 4'b??10: 1;
//                 4'b?100: 2;
//                 4'b1000: 3;
//                 4'b0000: 4;
//                 default: 0;
//             endcase;

//             Bit#(2) subValLastBe = case (pack(tlpHeader.lastDwBe)) matches
//                 4'b1???: 0;
//                 4'b01??: 1;
//                 4'b001?: 2;
//                 4'b0001: 3;
//                 default: 0;
//             endcase;

//             length = length - zeroExtend(subValFirstBe) - zeroExtend(subValLastBe);
//             return tagged Valid length;
//         end
//         else if (headerFirstDW.typ == `FTILE_MAC_TLP_HEADER_TYPE_CPL_WITH_DATA) begin
//             FtileMacTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

//             // for the first cplt, lowerAddr's 2-lsb means the address offset, which is the count of invalid bytes in the first payload DW
//             // for other cplt, lowerAddr's 2-lsb must be zero, so the length won't be modified.
//             let adjustedLength = length - zeroExtend(tlpHeader.lowerAddress[1:0]);

//             FtileMacTlpDataByteLen extendedByteCount = zeroExtend(tlpHeader.byteCount);
//             extendedByteCount[valueOf(FTILE_MAC_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

//             Bool isLastCplt = adjustedLength >= extendedByteCount;
//             return tagged Valid (isLastCplt ? extendedByteCount : adjustedLength);
//         end
//         else begin
//             return tagged Invalid;
//         end
//     end
// endfunction

// function Maybe#(FtileMacDataStreamByteCnt) getSignedBiDirByteShiftOffsetFromTlpHeader(FtileMacTlpHeaderBuffer tlpBuffer, FtileMacSegmentIdx startSegIdx);
//     FtileMacTlpHeaderCommon headerFirstDW = getFtileMacTlpHeaderCommon(tlpBuffer);

//     if (!isFtileMacTlpHasPayload(tlpBuffer)) begin
//         return tagged Invalid;
//     end
//     else begin
//         Integer dwordInSegmentNumberWidth = valueOf(TLog#(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH)) - valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//         FtileMacDataStreamByteCnt sourceLowerDwAddr = zeroExtend(startSegIdx) << dwordInSegmentNumberWidth;
        
//         if (headerFirstDW.typ == `FTILE_MAC_TLP_HEADER_TYPE_MEM_WRITE) begin
//             ADDR addrDw = truncate(tlpBuffer) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);  // convert from byte aligned addr to DW aligned;

//             Bit#(TSub#(TLog#(SizeOf#(FtileMacDataStreamByteIdx)), BYTE_DWORD_CONVERT_SHIFT_NUM)) tmpTruncateVar = truncate(addrDw);
//             FtileMacDataStreamByteCnt targetLowerDwAddr = zeroExtend(tmpTruncateVar);

//             return tagged Valid ((sourceLowerDwAddr - targetLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
//         end
//         else if (headerFirstDW.typ == `FTILE_MAC_TLP_HEADER_TYPE_CPL_WITH_DATA) begin
//             FtileMacTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

//             FtileMacDataStreamByteCnt targetLowerDwAddr = zeroExtend(tlpHeader.lowerAddress) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);

//             return tagged Valid ((sourceLowerDwAddr - targetLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
//         end
//         else begin
//             return tagged Invalid;
//         end
//     end
// endfunction

// typedef struct {
//     Bool isCplt;
//     FtileMacHeaderFieldExtendedTag extTag;
//     Bool isLastCplt;
// } MetaForReceivedTlpDispatch deriving(Bits, FShow);

// typedef struct {
//     FtileMacDataStreamLsbRight  ds;
//     FtileMacExtendTagHighPart   tagHigherPart;
//     Bool                    isLastCplt;
// } MemoeyMapAlignedDataStreamWithMetadata deriving(Bits, FShow);

// typedef StreamShifterG#(FtileMacDataStreamDataLsbRight) FtileMacStreamShifter;

// interface TlpDemuxAndConvertToMemMapStream;
//     interface PipeIn#(FtileMacDataStreamLsbRight) tlpDataStreamPipeIn;
//     interface PipeIn#(RawFtileMacRxTlpWithMeta) tlpHeaderPipeIn;

//     interface PipeOut#(FtileMacDataStreamLsbRight) tlpMemReqDataStreamPipeOut;
//     interface PipeOut#(FtileMacTlpHeaderBuffer) tlpMemReqHeaderPipeOut;

//     interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(MemoeyMapAlignedDataStreamWithMetadata)) tlpCpltDataStreamPipeOutVec;
//     interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(FtileMacTlpHeaderBuffer)) tlpCpltHeaderPipeOutVec;
// endinterface


// (* synthesize *)
// module mkTlpDemuxAndConvertToMemMapStream(TlpDemuxAndConvertToMemMapStream);
//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(MemoeyMapAlignedDataStreamWithMetadata)) tlpCpltDataStreamPipeOutQueueVec <- replicateM(mkFIFOF);
//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(FtileMacTlpHeaderBuffer)) tlpCpltHeaderPipeOutQueueVec <- replicateM(mkFIFOF);

//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(MemoeyMapAlignedDataStreamWithMetadata)) tlpCpltDataStreamPipeOutInstVec = newVector;
//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(FtileMacTlpHeaderBuffer)) tlpCpltHeaderPipeOutInstVec = newVector;

//     FIFOF#(FtileMacDataStreamLsbRight) tlpDataStreamPipeInQueue <- mkFIFOF;
//     FIFOF#(RawFtileMacRxTlpWithMeta) tlpHeaderPipeInQueue <- mkFIFOF;

//     FIFOF#(FtileMacDataStreamLsbRight) tlpMemReqDataStreamPipeOutQueue <- mkFIFOF;
//     FIFOF#(FtileMacTlpHeaderBuffer) tlpMemReqHeaderPipeOutQueue <- mkFIFOF;

//     for (Integer handlerIdx = 0; handlerIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); handlerIdx = handlerIdx + 1) begin
//         tlpCpltDataStreamPipeOutInstVec[handlerIdx] = toPipeOut(tlpCpltDataStreamPipeOutQueueVec[handlerIdx]);
//         tlpCpltHeaderPipeOutInstVec[handlerIdx] = toPipeOut(tlpCpltHeaderPipeOutQueueVec[handlerIdx]);
//     end

//     FtileMacStreamShifter streamShifter <- mkBiDirectionStreamShifterLsbRightG;

//     FIFOF#(MetaForReceivedTlpDispatch) tlpHeaderDispatchMetaQueue <- mkFIFOF;
//     FIFOF#(MetaForReceivedTlpDispatch) tlpDataDispatchMetaQueue <- mkFIFOF;

//     FIFOF#(RawFtileMacRxTlpWithMeta) tlpHeaderForDispatchPipeQueue <- mkFIFOF;

//     rule forwardDataStreamToShifter;
//         FtileMacDataStreamLsbRight dsInput = tlpDataStreamPipeInQueue.first;
//         tlpDataStreamPipeInQueue.deq;
//         streamShifter.streamPipeIn.enq(dsInput);
//         $display(
//             "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream forwardDataStreamToShifter"),
//             toBlue(", dsInput="), fshow(dsInput)
//         );
//     endrule

//     rule calcMetaData;
//         let tlpHeaderWithMeta = tlpHeaderPipeInQueue.first;
//         tlpHeaderPipeInQueue.deq;
//         let signedShiftOffsetMaybe = getSignedBiDirByteShiftOffsetFromTlpHeader(tlpHeaderWithMeta.rawTlpHeader, tlpHeaderWithMeta.startSegIdx);
//         let isCplt = isFtileMacTlpReadCplt(tlpHeaderWithMeta.rawTlpHeader);
//         let hasData = isFtileMacTlpHasPayload(tlpHeaderWithMeta.rawTlpHeader);

        

//         immAssert(
//             isValid(signedShiftOffsetMaybe),
//             "get shift offset from TLP error, TLP type not supported",
//             $format("TLP Info = ", fshow(getFtileMacTlpHeaderCommon(tlpHeaderWithMeta.rawTlpHeader)))
//         );
//         let signedShiftOffset = fromMaybe(?, signedShiftOffsetMaybe);

//         let dispatchMeta = MetaForReceivedTlpDispatch {
//             isCplt      : isCplt,
//             extTag      : getExtendedTagFromTlpCpltHeader(tlpHeaderWithMeta.rawTlpHeader),
//             isLastCplt  : isFtileMacTlpLastReadCplt(tlpHeaderWithMeta.rawTlpHeader)
//         };

//         tlpHeaderDispatchMetaQueue.enq(dispatchMeta);
//         if (hasData) begin
//             streamShifter.offsetPipeIn.enq(signedShiftOffset);
//             tlpDataDispatchMetaQueue.enq(dispatchMeta);
//         end
//         tlpHeaderForDispatchPipeQueue.enq(tlpHeaderWithMeta);

//         $display(
//             "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream calcMetaData"),
//             toBlue(", dispatchMeta="), fshow(dispatchMeta),
//             toBlue(", signedShiftOffset="), fshow(signedShiftOffset)
//         );
//     endrule

//     rule dispatchOutputDataStream;
//         let shiftedRightAlignedStream = streamShifter.streamPipeOut.first;
//         streamShifter.streamPipeOut.deq;

//         let dispatchMeta = tlpDataDispatchMetaQueue.first;
//         if (shiftedRightAlignedStream.isLast) begin
//             tlpDataDispatchMetaQueue.deq;
//         end

//         let outputDataStreamWithMeta = MemoeyMapAlignedDataStreamWithMetadata {
//             ds              : shiftedRightAlignedStream,
//             tagHigherPart   : truncateLSB(dispatchMeta.extTag),
//             isLastCplt      : dispatchMeta.isLastCplt
//         };

//         DispatchChannelIdx dispatchIdx = truncate(dispatchMeta.extTag);
//         if (dispatchMeta.isCplt) begin
//             tlpCpltDataStreamPipeOutQueueVec[dispatchIdx].enq(outputDataStreamWithMeta);
//             $display(
//                 "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream dispatchOutputDataStream Cplt"),
//                 toBlue(", dispatchIdx="), fshow(dispatchIdx),
//                 toBlue(", tag="), fshow(dispatchMeta.extTag),
//                 toBlue(", outputDataStreamWithMeta="), fshow(outputDataStreamWithMeta)
//             );
//         end
//         else begin
//             tlpMemReqDataStreamPipeOutQueue.enq(shiftedRightAlignedStream);
//             $display(
//                 "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream dispatchOutputDataStream MemRW"),
//                 toBlue(", dispatchIdx="), fshow(dispatchIdx),
//                 toBlue(", tag="), fshow(dispatchMeta.extTag),
//                 toBlue(", outputDataStreamWithMeta="), fshow(outputDataStreamWithMeta)
//             );
//         end
//     endrule

//     rule dispatchOutputTlpHeader;
//         let dispatchMeta = tlpHeaderDispatchMetaQueue.first;
//         tlpHeaderDispatchMetaQueue.deq;

//         let tlpHeaderWithMeta = tlpHeaderForDispatchPipeQueue.first;
//         tlpHeaderForDispatchPipeQueue.deq;

//         DispatchChannelIdx dispatchIdx = truncate(dispatchMeta.extTag);
//         if (dispatchMeta.isCplt) begin
//             tlpCpltHeaderPipeOutQueueVec[dispatchIdx].enq(tlpHeaderWithMeta.rawTlpHeader);
//         end
//         else begin
//             tlpMemReqHeaderPipeOutQueue.enq(tlpHeaderWithMeta.rawTlpHeader);
//         end
//     endrule


//     interface tlpDataStreamPipeIn = toPipeIn(tlpDataStreamPipeInQueue);
//     interface tlpHeaderPipeIn = toPipeIn(tlpHeaderPipeInQueue);

//     interface tlpMemReqDataStreamPipeOut = toPipeOut(tlpMemReqDataStreamPipeOutQueue);
//     interface tlpMemReqHeaderPipeOut = toPipeOut(tlpMemReqHeaderPipeOutQueue);

//     interface tlpCpltDataStreamPipeOutVec = tlpCpltDataStreamPipeOutInstVec;
//     interface tlpCpltHeaderPipeOutVec = tlpCpltHeaderPipeOutInstVec;
// endmodule


// interface FtileMacCompletionBuffer;
//     interface PipeIn#(FtileMacCompletionBufferSlotAllocReq) tagAllocPipeIn;
//     interface PipeOut#(FtileMacHeaderFieldExtendedTag) tagAllocPipeOut;
//     interface PipeIn#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeIn;
//     interface PipeOut#(FtileMacDataStreamLsbRight) dataStreamPipeOut;
// endinterface

// typedef 32 FTILE_MAC_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH;
// typedef Bit#(FTILE_MAC_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH) FtileMacCompletionBufferSlotUserData;

// // according to UG21036, Total tag allowed is from 256 to 1023. We use the lower 2 bits of the 10 bits tag as channel index,
// // so the higher 8 bits should range between 64~255.
// typedef 64 FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE;
// typedef 255 FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE;

// typedef 8 FTILE_MAC_EXTENDED_TAG_HIGH_PART_WIDTH;
// typedef Bit#(FTILE_MAC_EXTENDED_TAG_HIGH_PART_WIDTH) FtileMacExtendTagHighPart;

// typedef 512 FTILE_MAC_MIN_RCB_BIT_WIDTH;
// typedef TDiv#(FTILE_MAC_MIN_RCB_BIT_WIDTH, BYTE_WIDTH) FTILE_MAC_MIN_RCB_BYTE_WIDTH;
// typedef Bit#(FTILE_MAC_MIN_RCB_BIT_WIDTH) FtileMacRcbDataBlock;

// typedef TAdd#(1, TSub#(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE, FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)) FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_COUNT;
// typedef 8 FTILE_MAC_COMPLETION_BUFFER_INTERNAL_BUFFER_ROW_PER_SLOT;

// typedef FTILE_MAC_EXTENDED_TAG_HIGH_PART_WIDTH FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH;   // 8
// typedef TLog#(FTILE_MAC_COMPLETION_BUFFER_INTERNAL_BUFFER_ROW_PER_SLOT) FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH;  // 3

// typedef TAdd#(FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH, FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH) FTILE_MAC_COMPLETION_BUFFER_INNER_STORAGE_ROW_INDEX_WIDTH;  // 11

// typedef Bit#(FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH)           FtileMacCompletionBufferSlotIdx;
// typedef Bit#(TLog#(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE)) FtileMacCompletionBufferSlotCnt;

// typedef Bit#(FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH) FtileMacCompletionBufferSlotInnerRowIdx;
// typedef Bit#(FTILE_MAC_COMPLETION_BUFFER_INNER_STORAGE_ROW_INDEX_WIDTH)  FtileMacCompletionBufferInnerStorageRowIdx;

// typedef Bit#(TLog#(FTILE_MAC_HEADER_FIELD_FIRST_DW_BE_WIDTH))            InvalidByteNumInDw;

// typedef struct {
//     FtileMacCompletionBufferSlotUserData    userdata;
//     InvalidByteNumInDw                  firstDwInvalidByteNum;
//     InvalidByteNumInDw                  lastDwInvalidByteNum;
// } FtileMacCompletionBufferSlotAllocReq deriving(Bits, FShow);

// typedef struct {
//     FtileMacCompletionBufferSlotUserData                    userdata;                   // 32
//     FtileMacCompletionBufferSlotInnerRowIdx                 writePtr;                   // 3
//     FtileMacCompletionBufferSlotIdx                         slotIdx;                    // 8
//     Bool                                                isCompleted; 
//     Bool                                                isFirstBeat;
//     Bool                                                isFirstRow;
//     FtileMacDataStreamByteIdx                               startByteIdx;               // 7
//     FtileMacDataStreamByteCnt                               firstBeatByteNum;           // 8
//     FtileMacDataStreamByteCnt                               lastBeatByteNum;            // 8
//     InvalidByteNumInDw                                  firstDwInvalidByteNum;      // 2
//     InvalidByteNumInDw                                  lastDwInvalidByteNum;       // 2
// } FtileMacCompletionBufferSlotMeta deriving(Bits, FShow);

// // typedef struct {
// //     DataStreamMeta#(FtileMacDataStreamByteCnt, FtileMacDataStreamByteIdx) dataStreamMeta;
// // } FtileMacCompletionBufferRowMeta deriving(Bits, FShow);

// typedef enum {
//     FtileMacCompletionBufferOutputStateSendStateQueryReq = 0,
//     FtileMacCompletionBufferOutputStateWaitStateQueryResp = 1
// } FtileMacCompletionBufferOutputState deriving(Bits, Eq, FShow);

// module mkFtileMacCompletionBuffer#(DispatchChannelIdx channelIdx)(FtileMacCompletionBuffer);

//     FIFOF#(FtileMacCompletionBufferSlotAllocReq)        tagAllocPipeInQueue         <- mkFIFOF;
//     FIFOF#(FtileMacHeaderFieldExtendedTag)              tagAllocPipeOutQueue        <- mkFIFOF;
//     FIFOF#(MemoeyMapAlignedDataStreamWithMetadata)  dataStreamPipeInQueue       <- mkFIFOF;
//     FIFOF#(FtileMacDataStreamLsbRight)                  dataStreamPipeOutQueue      <- mkFIFOF;


//     Reg#(FtileMacExtendTagHighPart) headReg <- mkReg(fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
//     Reg#(FtileMacExtendTagHighPart) tailReg <- mkReg(fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
//     Count#(FtileMacCompletionBufferSlotCnt) busySlotCounter <- mkCount(0);

//     Vector#(NUMERIC_TYPE_TWO, AutoInferBramQueuedOutput#(FtileMacCompletionBufferInnerStorageRowIdx, FtileMacRcbDataBlock))             dataStreamStorageVec            <- replicateM(mkAutoInferBramQueuedOutput(False, ""));
//     AutoInferBramQueuedOutput#(FtileMacCompletionBufferSlotIdx, FtileMacCompletionBufferSlotMeta)                                       slotMetaStorage                 <- mkAutoInferBramQueuedOutput(False, "");
//     // Vector#(NUMERIC_TYPE_TWO, AutoInferBramQueuedOutput#(FtileMacCompletionBufferInnerStorageRowIdx, FtileMacCompletionBufferRowMeta))  rowMetaStorageDoubleWriteVec    <- replicateM(mkAutoInferBramQueuedOutput(False, ""));

//     FIFOF#(Tuple2#(FtileMacCompletionBufferSlotIdx, FtileMacCompletionBufferSlotMeta)) slotMetaUpdateReqQueueForTagAlloc <- mkFIFOF;
//     FIFOF#(Tuple2#(FtileMacCompletionBufferSlotIdx, FtileMacCompletionBufferSlotMeta)) slotMetaUpdateReqQueueForWritePtrUpdate <- mkFIFOF;

//     FIFOF#(FtileMacCompletionBufferSlotIdx) slotMetaReadReqQueueForPtrUpdate <- mkFIFOF;
//     FIFOF#(FtileMacCompletionBufferSlotIdx) slotMetaReadReqQueueForOutputData <- mkFIFOF;

//     FIFOF#(FtileMacCompletionBufferSlotMeta) slotMetaReadRespQueueForPtrUpdate <- mkFIFOF;
//     FIFOF#(FtileMacCompletionBufferSlotMeta) slotMetaReadRespQueueForOutputData <- mkFIFOF;

//     FIFOF#(Bool) slotMetaReadReqKeepOrderQueue <- mkFIFOF;

//     // Pipeline FIFOs
//     FIFOF#(Tuple3#(MemoeyMapAlignedDataStreamWithMetadata, Bool, Bool))     inputStreamStorageMetaCalcPipelineQueue             <- mkFIFOF;
//     FIFOF#(FtileMacCompletionBufferSlotMeta)                                    outputSlotMetaForSendReadReqPipelineQueue           <- mkFIFOF;
//     FIFOF#(DataStreamMeta#(FtileMacDataStreamDataLsbRight))                     outputStreamMetaPipelineQueue                       <- mkFIFOF;

//     Reg#(FtileMacCompletionBufferSlotInnerRowIdx)   curReadOutReqPtrReg           <- mkReg(0);
//     Reg#(FtileMacCompletionBufferSlotInnerRowIdx)   curReadOutReqPtrTargetReg     <- mkReg(0);
//     Reg#(FtileMacCompletionBufferSlotIdx)           curReadOutReqSlotIdx          <- mkReg(0);
                            

//     PrioritySearchBuffer#(NUMERIC_TYPE_FOUR, FtileMacCompletionBufferSlotIdx, FtileMacCompletionBufferSlotMeta) slotMetaUpdateForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_FOUR));
//     // PrioritySearchBuffer#(NUMERIC_TYPE_FOUR, FtileMacCompletionBufferInnerStorageRowIdx, FtileMacCompletionBufferRowMeta) slotMetaUpdateForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_FOUR));
    
//     Reg#(Bool) newCompleteSlotSignal[3] <- mkCReg(3, False);

//     Reg#(FtileMacCompletionBufferOutputState) outputStateReg <- mkReg(FtileMacCompletionBufferOutputStateSendStateQueryReq);

//     Reg#(Bool) isOutputFirstBeatReg <- mkReg(True);

//     rule assertChecker;
//         // since the FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_COUNT is not 2^n now, maybe in the future it will become 2^n. If it become 2^n,
//         // some width calculated by TLog#() will be wrong, so we need to check it. 
//         immAssert(
//             valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_COUNT) < valueOf(TExp#(SizeOf#(FtileMacCompletionBufferSlotCnt))),
//             "value overflow",
//             $format("")
//         );
//     endrule

//     rule muxSlotMetaUpdateReq;
//         // writePtr update has higher priority
//         if (slotMetaUpdateReqQueueForWritePtrUpdate.notEmpty) begin
//             let {addr, data} = slotMetaUpdateReqQueueForWritePtrUpdate.first;
//             slotMetaUpdateReqQueueForWritePtrUpdate.deq;
//             slotMetaStorage.write(addr, data);
//         end
//         else if (slotMetaUpdateReqQueueForTagAlloc.notEmpty) begin
//             let {addr, data} = slotMetaUpdateReqQueueForTagAlloc.first;
//             slotMetaUpdateReqQueueForTagAlloc.deq;
//             slotMetaStorage.write(addr, data);
//         end
//     endrule

//     rule muxSlotMetaQueryReq;
//         // writePtr query has higher priority
//         if (slotMetaReadReqQueueForPtrUpdate.notEmpty) begin
//             let addr = slotMetaReadReqQueueForPtrUpdate.first;
//             slotMetaReadReqQueueForPtrUpdate.deq;
//             slotMetaStorage.putReadReq(addr);
//             Bool isForPtrUpdate = True;
//             slotMetaReadReqKeepOrderQueue.enq(isForPtrUpdate);
//         end
//         else if (slotMetaReadReqQueueForOutputData.notEmpty) begin
//             let addr = slotMetaReadReqQueueForOutputData.first;
//             slotMetaReadReqQueueForOutputData.deq;
//             slotMetaStorage.putReadReq(addr);
//             Bool isForPtrUpdate = False;
//             slotMetaReadReqKeepOrderQueue.enq(isForPtrUpdate);
//         end

//         if (slotMetaStorage.readRespPipeOut.notEmpty) begin
//             let resp = slotMetaStorage.readRespPipeOut.first;
//             let isForPtrUpdate = slotMetaReadReqKeepOrderQueue.first;
//             slotMetaReadReqKeepOrderQueue.deq;
//             slotMetaStorage.readRespPipeOut.deq;
//             if (isForPtrUpdate) begin
//                 slotMetaReadRespQueueForPtrUpdate.enq(resp);
//             end
//             else begin
//                 slotMetaReadRespQueueForOutputData.enq(resp);
//             end
//         end
//     endrule

//     rule handleTagAlloc;
//         if (busySlotCounter != fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_SLOT_COUNT))) begin
//             let req = tagAllocPipeInQueue.first;
//             tagAllocPipeInQueue.deq;

//             let newSlot = FtileMacCompletionBufferSlotMeta {
//                 userdata:               req.userdata,
//                 writePtr:               0,
//                 slotIdx:                headReg,
//                 isCompleted:            False,
//                 isFirstBeat:            True,
//                 isFirstRow:             True,
//                 startByteIdx:           0,
//                 firstBeatByteNum:       0,
//                 lastBeatByteNum:        0,
//                 firstDwInvalidByteNum:  req.firstDwInvalidByteNum,
//                 lastDwInvalidByteNum:   req.lastDwInvalidByteNum
//             };
            
//             FtileMacHeaderFieldExtendedTag tag = unpack({pack(headReg), pack(channelIdx)});
//             slotMetaUpdateReqQueueForTagAlloc.enq(tuple2(headReg, newSlot));

//             tagAllocPipeOutQueue.enq(tag);

//             if (headReg == fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
//                 headReg <= fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
//             end
//             else begin
//                 headReg <= headReg + 1;
//             end
//             busySlotCounter.incr(1);

//             $display(
//                 "time=%0t:", $time, toGreen(" mkFtileMacCompletionBuffer handleTagAlloc"),
//                 toBlue(", channelIdx="), fshow(channelIdx),
//                 toBlue(", tag="), fshow(tag)
//             );
//         end

//     endrule

//     rule handleStreamInput;
//         let inputStreamWithMeta = dataStreamPipeInQueue.first;
//         dataStreamPipeInQueue.deq;

//         let ds = inputStreamWithMeta.ds;
//         let isLastCplt = inputStreamWithMeta.isLastCplt;

//         let slotIdx = unpack(inputStreamWithMeta.tagHigherPart);

//         Bool isLowerHalfUsed = True;
//         Bool isHigherHalfUsed = True;

//         if (ds.isFirst) begin
//             if (ds.startByteIdx >= fromInteger(valueOf(FTILE_MAC_TLP_DATA_BUNDLE_BYTE_CNT) / 2)) begin
//                 isLowerHalfUsed = False;
//             end
//         end

//         if (ds.isLast) begin
//             if (zeroExtend(ds.startByteIdx) + ds.byteNum < fromInteger(valueOf(FTILE_MAC_TLP_DATA_BUNDLE_BYTE_CNT) / 2)) begin
//                 isHigherHalfUsed = False;
//             end
//         end

//         immAssert(
//             (isLowerHalfUsed || isHigherHalfUsed),
//             "isLowerHalfUsed and isHigherHalfUsed can't both be False",
//             $format("")
//         );

//         slotMetaReadReqQueueForPtrUpdate.enq(slotIdx);

//         inputStreamStorageMetaCalcPipelineQueue.enq(tuple3(inputStreamWithMeta, isLowerHalfUsed, isHigherHalfUsed));

//         $display(
//             "time=%0t:", $time, toGreen(" mkFtileMacCompletionBuffer handleStreamInput"),
//             toBlue(", inputStreamWithMeta="), fshow(inputStreamWithMeta),
//             toBlue(", isLowerHalfUsed="), fshow(isLowerHalfUsed),
//             toBlue(", isHigherHalfUsed="), fshow(isHigherHalfUsed)
//         );
//     endrule

//     rule storeInputStream;
//         let {inputStreamWithMeta, isLowerHalfUsed, isHigherHalfUsed} = inputStreamStorageMetaCalcPipelineQueue.first;
//         inputStreamStorageMetaCalcPipelineQueue.deq;

//         let slotMetaReadFromBram = slotMetaReadRespQueueForPtrUpdate.first;
//         slotMetaReadRespQueueForPtrUpdate.deq;

//         let ds                                  = inputStreamWithMeta.ds;
//         let isLastCplt                          = inputStreamWithMeta.isLastCplt;
//         let needUpdateWritePtr                  = isHigherHalfUsed;
//         FtileMacCompletionBufferSlotIdx slotIdx     = unpack(inputStreamWithMeta.tagHigherPart);
//         let slotMetaFromForwardBufferMaybe      <- slotMetaUpdateForwardBuffer.search(slotIdx);
//         FtileMacCompletionBufferSlotMeta slotMeta   = isValid(slotMetaFromForwardBufferMaybe) ? fromMaybe(?, slotMetaFromForwardBufferMaybe) : slotMetaReadFromBram;

//         FtileMacCompletionBufferInnerStorageRowIdx streamWriteAddr = unpack({pack(slotIdx), pack(slotMeta.writePtr)});
//         if (isLowerHalfUsed) begin
//             dataStreamStorageVec[0].write(streamWriteAddr, truncate(ds.data));
//         end
//         if (isHigherHalfUsed) begin
//             dataStreamStorageVec[1].write(streamWriteAddr, truncateLSB(ds.data));
//         end

//         Bool isCompleted = isLastCplt && ds.isLast;
//         slotMeta.isCompleted = isCompleted;

//         if (slotMeta.isFirstBeat) begin
//             slotMeta.isFirstBeat = False;
//             slotMeta.startByteIdx = ds.startByteIdx;
//             slotMeta.firstBeatByteNum = ds.byteNum;
//         end
//         else if (slotMeta.isFirstRow) begin
//             // if the first row is consist of two seperate cplt, this is the second cplt
//             slotMeta.firstBeatByteNum = slotMeta.firstBeatByteNum + ds.byteNum;
//         end
        
//         if (isCompleted) begin
//             if (isLowerHalfUsed && isHigherHalfUsed) begin
//                 slotMeta.lastBeatByteNum = ds.byteNum;
//             end
//             else if (isLowerHalfUsed && !isHigherHalfUsed) begin
//                 slotMeta.lastBeatByteNum = ds.byteNum;
//             end
//             else if (!isLowerHalfUsed && isHigherHalfUsed) begin
//                 // the last row is consist of two cplt.
//                 // there are two case:
//                 // 1. the whole response only have one row. In this case, the `slotMeta.firstBeatByteNum` already record the row's valid byte count,
//                 //    so `slotMeta.lastBeatByteNum` should not be used. we will give it a meaningless value, but it doesn't matter.
//                 // 2. the whole response has more than one row, so the first cplt TLP of the last row must have all higher half data valid.    
//                 slotMeta.lastBeatByteNum  = ds.byteNum + fromInteger(valueOf(FTILE_MAC_MIN_RCB_BYTE_WIDTH));
//             end
//         end

//         if (needUpdateWritePtr && !isCompleted) begin
//             slotMeta.writePtr = slotMeta.writePtr + 1;
//             slotMeta.isFirstRow = False;
//         end

//         slotMetaUpdateForwardBuffer.enq(slotIdx, slotMeta);
//         slotMetaUpdateReqQueueForWritePtrUpdate.enq(tuple2(slotIdx, slotMeta));

//         if (isCompleted) begin
//             newCompleteSlotSignal[1] <= True;
//         end
//     endrule

//     rule outputSendStateQuery if (outputStateReg == FtileMacCompletionBufferOutputStateSendStateQueryReq);
//         if (newCompleteSlotSignal[0] == True) begin
//             newCompleteSlotSignal[0] <= False;
//             slotMetaReadReqQueueForOutputData.enq(tailReg);
//             outputStateReg <= FtileMacCompletionBufferOutputStateWaitStateQueryResp;
//             $display(
//                 "time=%0t:", $time, toGreen(" mkFtileMacCompletionBuffer outputSendStateQuery"),
//                 toBlue(", tailReg="), fshow(tailReg)
//             );
//         end
//     endrule

//     rule outputWaitStateQueryResp if (outputStateReg == FtileMacCompletionBufferOutputStateWaitStateQueryResp);
//         if (slotMetaReadRespQueueForOutputData.notEmpty) begin
//             let slotMeta = slotMetaReadRespQueueForOutputData.first;
//             slotMetaReadRespQueueForOutputData.deq;
//             if (slotMeta.isCompleted) begin
//                 outputSlotMetaForSendReadReqPipelineQueue.enq(slotMeta);
//             end
//             outputStateReg <= FtileMacCompletionBufferOutputStateSendStateQueryReq;
//             $display(
//                 "time=%0t:", $time, toGreen(" mkFtileMacCompletionBuffer outputWaitStateQueryResp"),
//                 toBlue(", slotMeta="), fshow(slotMeta)
//             );
//         end
//     endrule

//     rule sendSlotRowDataReadReq;
//         let curSlotMeta = outputSlotMetaForSendReadReqPipelineQueue.first;
//         Bool needIncrTailPtr = False;
//         if (curReadOutReqPtrReg == curReadOutReqPtrTargetReg) begin
//             // This beat is the start of a new output Stream;
            
//             curReadOutReqPtrReg <= 0;
//             curReadOutReqPtrTargetReg <= curSlotMeta.writePtr;
//             curReadOutReqSlotIdx <= curSlotMeta.slotIdx;


//             dataStreamStorageVec[0].putReadReq(unpack({pack(curSlotMeta.slotIdx), 0}));
//             dataStreamStorageVec[1].putReadReq(unpack({pack(curSlotMeta.slotIdx), 0}));


//             let isOnly = curSlotMeta.writePtr == 0;
//             let dataStreamMeta = DataStreamMeta {
//                 byteNum:        isOnly ? curSlotMeta.firstBeatByteNum - zeroExtend(curSlotMeta.firstDwInvalidByteNum) - zeroExtend(curSlotMeta.lastDwInvalidByteNum) : curSlotMeta.firstBeatByteNum - zeroExtend(curSlotMeta.firstDwInvalidByteNum),
//                 startByteIdx:   curSlotMeta.startByteIdx + zeroExtend(curSlotMeta.firstDwInvalidByteNum),
//                 isFirst:        True,
//                 isLast:         isOnly
//             };
//             outputStreamMetaPipelineQueue.enq(dataStreamMeta);

//             if (isOnly) begin
//                 outputSlotMetaForSendReadReqPipelineQueue.deq;
//                 newCompleteSlotSignal[2] <= True;
//                 needIncrTailPtr = True;

//             end
//         end
//         else begin
//             let newPtr = curReadOutReqPtrReg + 1;
//             curReadOutReqPtrReg <= newPtr;
//             dataStreamStorageVec[0].putReadReq(unpack({pack(curReadOutReqSlotIdx), pack(newPtr)}));
//             dataStreamStorageVec[1].putReadReq(unpack({pack(curReadOutReqSlotIdx), pack(newPtr)}));

//             let isLast = newPtr == curReadOutReqPtrTargetReg;
//             let dataStreamMeta = DataStreamMeta {
//                 byteNum: isLast ? curSlotMeta.lastBeatByteNum - zeroExtend(curSlotMeta.lastDwInvalidByteNum) : fromInteger(valueOf(FTILE_MAC_TLP_DATA_BUNDLE_BYTE_CNT)),
//                 startByteIdx: 0,
//                 isFirst: False,
//                 isLast: isLast
//             };
//             outputStreamMetaPipelineQueue.enq(dataStreamMeta);

//             if (isLast) begin
//                 outputSlotMetaForSendReadReqPipelineQueue.deq;
//                 newCompleteSlotSignal[2] <= True;
//                 needIncrTailPtr = True;
//             end
//         end

//         if (needIncrTailPtr) begin
//             if (tailReg == fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
//                 tailReg <=fromInteger(valueOf(FTILE_MAC_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
//             end 
//             else begin
//                 tailReg <= tailReg + 1;
//             end
//         end

//         $display(
//             "time=%0t:", $time, toGreen(" mkFtileMacCompletionBuffer sendSlotRowDataReadReq"),
//             toBlue(", curSlotMeta="), fshow(curSlotMeta)
//         );
//     endrule

//     rule receiveDataStreamRowDataAndOutput;
//         let streamLowerPart = dataStreamStorageVec[0].readRespPipeOut.first;
//         let streamHigherPart = dataStreamStorageVec[1].readRespPipeOut.first;
//         let streamMeta = outputStreamMetaPipelineQueue.first;

//         dataStreamStorageVec[0].readRespPipeOut.deq;
//         dataStreamStorageVec[1].readRespPipeOut.deq;
//         outputStreamMetaPipelineQueue.deq;

//         FtileMacDataStreamLsbRight ds = DtldStreamData {
//             data: unpack({streamHigherPart, streamLowerPart}),
//             byteNum: streamMeta.byteNum,
//             startByteIdx: streamMeta.startByteIdx,
//             isFirst: streamMeta.isFirst,
//             isLast: streamMeta.isLast
//         };
//         dataStreamPipeOutQueue.enq(ds);

//         if (ds.isLast) begin
//             busySlotCounter.decr(1);
//         end

//         $display(
//             "time=%0t:", $time, toGreen(" mkFtileMacCompletionBuffer receiveDataStreamRowDataAndOutput"),
//             toBlue(", ds="), fshow(ds)
//         );
//     endrule

//     interface tagAllocPipeIn    =   toPipeIn(tagAllocPipeInQueue);
//     interface tagAllocPipeOut   =   toPipeOut(tagAllocPipeOutQueue);
//     interface dataStreamPipeIn  =   toPipeIn(dataStreamPipeInQueue);
//     interface dataStreamPipeOut =   toPipeOut(dataStreamPipeOutQueue);
// endmodule


// interface DataStreamArbiterForCompletionBuffer;
//     interface Vector#(FTILE_MAC_RX_HANDLER_CNT, PipeIn#(MemoeyMapAlignedDataStreamWithMetadata)) dataStreamPipeInVec;
//     interface PipeOut#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeOut;
// endinterface

// (* synthesize *)
// module mkDataStreamArbiterForCompletionBuffer(DataStreamArbiterForCompletionBuffer);
//     Vector#(FTILE_MAC_RX_HANDLER_CNT, PipeIn#(MemoeyMapAlignedDataStreamWithMetadata)) dataStreamPipeInVecInst = newVector;
//     Vector#(FTILE_MAC_RX_HANDLER_CNT, FIFOF#(MemoeyMapAlignedDataStreamWithMetadata)) dataStreamPipeInQueueVec <- replicateM(mkFIFOF);
//     FIFOF#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeOutQueue <- mkFIFOF;

//     for (Integer handlerIdx = 0; handlerIdx < valueOf(FTILE_MAC_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
//         dataStreamPipeInVecInst[handlerIdx] = toPipeIn(dataStreamPipeInQueueVec[handlerIdx]);
//     end

//     Arbiter_IFC#(FTILE_MAC_RX_HANDLER_CNT) arbiter <- mkArbiter(False);

//     Reg#(FtileMacRxHandlerIdx) curInputChannleIdxReg <- mkReg(0);
    
//     Reg#(Bool) isForwardFirstBeatReg <- mkReg(True); 

//     rule sendArbitReq if (isForwardFirstBeatReg);
//         for (Integer handlerIdx = 0; handlerIdx < valueOf(FTILE_MAC_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
//             if (dataStreamPipeInQueueVec[handlerIdx].notEmpty) begin 
//                 arbiter.clients[handlerIdx].request;
//             end
//         end
//     endrule

//     rule getArbitResult if (isForwardFirstBeatReg);
//         Bool isOnly = False;
//         Maybe#(MemoeyMapAlignedDataStreamWithMetadata) dsWithMetaMaybe = tagged Invalid;
//         FtileMacRxHandlerIdx selectedChannel = 0;
//         for (Integer handlerIdx = 0; handlerIdx < valueOf(FTILE_MAC_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
//             if (arbiter.clients[handlerIdx].grant) begin
//                 let dsWithMeta = dataStreamPipeInQueueVec[handlerIdx].first;
//                 dataStreamPipeInQueueVec[handlerIdx].deq;
//                 immAssert(
//                     dsWithMeta.ds.isFirst,
//                     "datastream should be First",
//                     $format("dsWithMeta=", fshow(dsWithMeta))
//                 );
//                 if (dsWithMeta.ds.isLast) begin
//                     isOnly = True;
//                 end
//                 dsWithMetaMaybe = tagged Valid dsWithMeta;
//                 selectedChannel = fromInteger(handlerIdx);
//             end
//         end

//         if (dsWithMetaMaybe matches tagged Valid .dsWithMeta) begin
//             isForwardFirstBeatReg <= isOnly;
//             dataStreamPipeOutQueue.enq(dsWithMeta);
//             curInputChannleIdxReg <= selectedChannel;
//         end
//     endrule

//     rule forwardMoreBeat if (!isForwardFirstBeatReg);
//         let dsWithMeta = dataStreamPipeInQueueVec[curInputChannleIdxReg].first;
//         dataStreamPipeInQueueVec[curInputChannleIdxReg].deq;
//         dataStreamPipeOutQueue.enq(dsWithMeta);
        
//         if (dsWithMeta.ds.isLast) begin
//             isForwardFirstBeatReg <= True;
//         end
//     endrule

//     interface dataStreamPipeInVec = dataStreamPipeInVecInst;
//     interface dataStreamPipeOut = toPipeOut(dataStreamPipeOutQueue);
// endmodule

// typedef DtldStreamMemAccessMeta#(ADDR, Length) FtileMacStreamMeta;
// typedef DtldStreamData#(FtileMacDataStreamDataLsbRight) FtileMacStreamData;


// typedef struct {
//     FtileMacHeaderFieldLength       length;
//     FtileMacHeaderFieldLastDwBe     lastDwBe;
//     FtileMacHeaderFieldFirstDwBe    firstDwBe;
// } FtileMacLengthAndByteEn deriving(FShow, Bits);


// interface FtileMacRequestTlpHeaderGen#(numeric type channelCnt, type tData, type tAddr, type tLen);
//     interface DtldStreamSlavePipes#(tData, tAddr, tLen) dtldStreamSlavePipes;
//     interface PipeIn#(FtileMacTlpHeaderCompletion)          cpltTlpHeaderPipeIn;
//     interface PipeIn#(DtldStreamData#(tData))           cpltTlpDataStreamPipeIn;
    

//     interface PipeIn#(Bit#(TLog#(channelCnt)))                                  writeSourceChannelIdPipeIn;
//     interface PipeIn#(Bit#(TLog#(channelCnt)))                                  readSourceChannelIdPipeIn;

//     interface Vector#(channelCnt, PipeOut#(FtileMacCompletionBufferSlotAllocReq))   tagAllocPipeOutVec;
//     interface Vector#(channelCnt, PipeIn#(FtileMacHeaderFieldExtendedTag))          tagAllocPipeInVec;

//     interface PipeOut#(FtileMacTlpHeaderBuffer)                                     tlpHeaderBufferPipeOut;
//     interface PipeOut#(DtldStreamData#(tData))                                          tlpDataStreamPipeOut;
// endinterface

// module mkFtileMacRequestTlpHeaderGen(FtileMacRequestTlpHeaderGen#(channelCnt, tData, tAddr, tLen)) provisos (
//         Bits#(tData, szData),
//         Bits#(tAddr, szAddr),
//         Bits#(tLen,  szLen),
//         Add#(a__, szLen, szAddr),
//         Add#(d__, 2, szAddr),
//         Arith#(tAddr),
//         Bitwise#(tAddr),
//         Eq#(tAddr),
//         Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
//         Add#(b__, FTILE_MAC_HEADER_FIELD_64_BIT_ADDR_WIDTH, szAddr),
//         Add#(c__, FTILE_MAC_HEADER_FIELD_LENGTH_WIDTH, szAddr),
//         FShow#(DtldStreamData#(tData))
//     );


//     FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))  slaveSideQueueWm         <- mkFIFOF;
//     FIFOF#(DtldStreamData#(tData))                 slaveSideQueueWd         <- mkFIFOF;
//     FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))  slaveSideQueueRm         <- mkFIFOF;
//     FIFOF#(DtldStreamData#(tData))                 slaveSideQueueRd         <- mkFIFOF;

//     FIFOF#(DtldStreamData#(tData)) cpltTlpDataStreamPipeInQueue    <- mkFIFOF;

//     FIFOF#(tChannelIdx)    writeSourceChannelIdPipeInQueue  <- mkFIFOF;
//     FIFOF#(tChannelIdx)    readSourceChannelIdPipeInQueue   <- mkFIFOF;

//     FIFOF#(tChannelIdx)    readTagAllocKeepOrderQueue       <- mkFIFOF;

//     Vector#(channelCnt, FIFOF#(FtileMacCompletionBufferSlotAllocReq))       tagAllocPipeOutQueueVec <- replicateM(mkFIFOF);
//     Vector#(channelCnt, FIFOF#(FtileMacHeaderFieldExtendedTag))             tagAllocPipeInQueueVec  <- replicateM(mkFIFOF);

//     Vector#(channelCnt, PipeOut#(FtileMacCompletionBufferSlotAllocReq))     tagAllocPipeOutVecInst  = newVector;
//     Vector#(channelCnt, PipeIn#(FtileMacHeaderFieldExtendedTag))            tagAllocPipeInVecInst   = newVector;

//     FIFOF#(FtileMacTlpHeaderMemoryRead4Dw)  readTlpQueue                <- mkFIFOF;
//     FIFOF#(FtileMacTlpHeaderMemoryWrite4Dw) writeTlpQueue               <- mkFIFOF;
//     FIFOF#(FtileMacTlpHeaderCompletion)     cpltTlpQueue                <- mkFIFOF;

//     FIFOF#(FtileMacTlpHeaderBuffer)         arbittedTlpBufferQueue      <- mkFIFOF;
//     FIFOF#(DtldStreamData#(tData))      arbittedTlpDataStreamQueue  <- mkFIFOF;
//     Reg#(Bool)                          isOutputingPayloadStreamReg <- mkReg(False);

    
//     FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))  tagAllocToReadTlpGenPipelineQ         <- mkFIFOF;

//     for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
//         tagAllocPipeOutVecInst[channelIdx] = toPipeOut(tagAllocPipeOutQueueVec[channelIdx]);
//         tagAllocPipeInVecInst[channelIdx]  = toPipeIn(tagAllocPipeInQueueVec[channelIdx]);
//     end

//     rule genTlpMwr;
        
//         let wm = slaveSideQueueWm.first;
//         slaveSideQueueWm.deq;

//         // TODO: can reduce the bit width of the add operation.
//         tAddr endAddr = wm.addr + unpack(zeroExtend(pack(wm.totalLen))) - 1;
//         let startDwordAddr = wm.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//         let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//         let lengthInDw = endDwordAddr - startDwordAddr + 1;


//         FtileMacHeaderFieldFirstDwBe    firstDwBe = case (pack(wm.addr)[1:0])
//                                                     2'b00: 4'b1111;
//                                                     2'b01: 4'b1110;
//                                                     2'b10: 4'b1100;
//                                                     2'b11: 4'b1000;
//                                                 endcase;
//         FtileMacHeaderFieldLastDwBe     lastDwBe = case (pack(endAddr)[1:0])
//                                                     2'b00: 4'b0001;
//                                                     2'b01: 4'b0011;
//                                                     2'b10: 4'b0111;
//                                                     2'b11: 4'b1111;
//                                                 endcase;

//         let isOnlyDword = startDwordAddr == endDwordAddr;
//         if (isOnlyDword) begin
//             lastDwBe = 0;
//         end
        
        
//         let commonHeader = FtileMacTlpHeaderCommon {
//             fmt     : `FTILE_MAC_TLP_HEADER_FMT_4DW_WITH_DATA,
//             typ     : `FTILE_MAC_TLP_HEADER_TYPE_MEM_WRITE,
//             t9      : False,
//             tc      : 0,
//             t8      : False,
//             attrh   : False,
//             ln      : False,
//             th      : False,
//             td      : False,
//             ep      : False,
//             attrl   : 0,
//             at      : 0,
//             length  : unpack(truncate(pack(lengthInDw)))
//         };
        
//         let memoryWriteHeader = FtileMacTlpHeaderMemoryWrite {
//             commonHeader    : commonHeader,
//             requesterId     : 0,  // will filled by IP core
//             st              : 0,
//             lastDwBe        : lastDwBe,
//             firstDwBe       : firstDwBe
//         };

//         let tlp = FtileMacTlpHeaderMemoryWrite4Dw {
//             memoryWriteHeader   : memoryWriteHeader,
//             addr                : unpack(truncateLSB(pack(wm.addr))),
//             ph                  : 0
//         };

//         writeTlpQueue.enq(tlp);
//     endrule
    

//     rule sendGenFtileMacTagReq;
//         let rm = slaveSideQueueRm.first;
//         slaveSideQueueRm.deq;

//         let channelIdx = readSourceChannelIdPipeInQueue.first;
//         readSourceChannelIdPipeInQueue.deq;

//         tAddr endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1; 

//         let req = FtileMacCompletionBufferSlotAllocReq {
//             userdata: ?,
//             firstDwInvalidByteNum: truncate(pack(rm.addr)),
//             lastDwInvalidByteNum: maxBound - truncate(pack(endAddr))
//         };

//         tagAllocPipeOutQueueVec[channelIdx].enq(req);
//         readTagAllocKeepOrderQueue.enq(channelIdx);
//         tagAllocToReadTlpGenPipelineQ.enq(rm);
//     endrule

//     rule genTlpMrd;
        
//         let rm = tagAllocToReadTlpGenPipelineQ.first;
//         tagAllocToReadTlpGenPipelineQ.deq;

//         let channelIdx = readTagAllocKeepOrderQueue.first;
//         readTagAllocKeepOrderQueue.deq;

//         let tag = tagAllocPipeInQueueVec[channelIdx].first;
//         tagAllocPipeInQueueVec[channelIdx].deq;

//         // TODO: can reduce the bit width of the add operation.
//         tAddr endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1;
//         let startDwordAddr = rm.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//         let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//         let lengthInDw = endDwordAddr - startDwordAddr + 1;   
        
//         let commonHeader = FtileMacTlpHeaderCommon {
//             fmt     : `FTILE_MAC_TLP_HEADER_FMT_4DW_NO_DATA,
//             typ     : `FTILE_MAC_TLP_HEADER_TYPE_MEM_READ,
//             t9      : unpack(tag[9]),
//             tc      : 0,
//             t8      : unpack(tag[8]),
//             attrh   : False,
//             ln      : False,
//             th      : False,
//             td      : False,
//             ep      : False,
//             attrl   : 0,
//             at      : 0,
//             length  : unpack(truncate(pack(lengthInDw)))
//         };
        
//         let memoryReadHeader = FtileMacTlpHeaderMemoryRead {
//             commonHeader    : commonHeader,
//             requesterId     : 0,  // will filled by IP core
//             tag             : truncate(tag),
//             st              : 0
//         };

//         let tlp = FtileMacTlpHeaderMemoryRead4Dw {
//             memoryReadHeader    : memoryReadHeader,
//             addr                : unpack(truncateLSB(pack(rm.addr))),
//             ph                  : 0
//         };

//         readTlpQueue.enq(tlp);
//     endrule


//     // rule genTlpCplt;
        

//     //     // TODO: can reduce the bit width of the add operation.
//     //     tAddr endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1;
//     //     let startDwordAddr = rm.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//     //     let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//     //     let lengthInDw = endDwordAddr - startDwordAddr + 1;   


//     //     let commonHeader = FtileMacTlpHeaderCommon {
//     //         fmt     : `FTILE_MAC_TLP_HEADER_FMT_3DW_WITH_DATA,
//     //         typ     : `FTILE_MAC_TLP_HEADER_TYPE_CPL_WITH_DATA,
//     //         t9      : unpack(tag[9]),
//     //         tc      : 0,
//     //         t8      : unpack(tag[8]),
//     //         attrh   : False,
//     //         ln      : False,
//     //         th      : False,
//     //         td      : False,
//     //         ep      : False,
//     //         attrl   : 0,
//     //         at      : 0,
//     //         length  : unpack(truncate(pack(lengthInDw)))
//     //     };

//     //     let tlp = FtileMacTlpHeaderCompletion {
//     //         FtileMacTlpHeaderCommon         commonHeader;
//     //         FtileMacHeaderFieldCompleterId  completerId;
//     //         FtileMacHeaderFieldCpltStatus   cpltStatus;
//     //         Bool                        bcm;
//     //         FtileMacHeaderFieldByteCount    byteCount;
//     //         FtileMacHeaderFieldRequesterId  requesterId;
//     //         FtileMacHeaderFieldTag          tag;
//     //         ReservedZero#(1)            rsv1;
//     //         FtileMacHeaderFieldLowerAddress lowerAddress;
//     //     };
//     // endrule


//     rule arbitOutputTlp if (!isOutputingPayloadStreamReg);
//         // we use a fixed priority here. The MWr is for network packet receive, can't be blocked. so it should have the highest priority.
//         // for cplt, it will affect the waiting time of the software, and there is few cplt packet, so it has the middle priority.
//         if (writeTlpQueue.notEmpty) begin
//             arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(writeTlpQueue.first)));
//             writeTlpQueue.deq;
//             let ds = slaveSideQueueWd.first;
//             slaveSideQueueWd.deq;


//             arbittedTlpDataStreamQueue.enq(ds);
//             if (!ds.isLast) begin
//                 isOutputingPayloadStreamReg <= True;
//             end
//         end
//         else if (cpltTlpQueue.notEmpty) begin
//             arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(cpltTlpQueue.first)));
//             cpltTlpQueue.deq;

//             let ds = cpltTlpDataStreamPipeInQueue.first;
//             cpltTlpDataStreamPipeInQueue.deq;
//             arbittedTlpDataStreamQueue.enq(ds);
//             immAssert(
//                 ds.isFirst && ds.isLast && ds.byteNum <= 8 && ds.startByteIdx <= 3,
//                 "for read cplt, only support ONLY cplt TLP with max payload not exceed 64-bits",
//                 $format("ds=", fshow(ds))
//             );
//         end
//         else if (readTlpQueue.notEmpty) begin
//             arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(readTlpQueue.first)));
//             readTlpQueue.deq;
//         end
//     endrule

//     rule arbitOutputDataStream if (isOutputingPayloadStreamReg);
//         let ds = slaveSideQueueWd.first;
//         slaveSideQueueWd.deq;
//         arbittedTlpDataStreamQueue.enq(ds);
//         if (ds.isLast) begin
//             isOutputingPayloadStreamReg <= False;
//         end
//     endrule

//     rule discardWriteSourceChannelId;
//         writeSourceChannelIdPipeInQueue.deq;
//     endrule

//     interface DtldStreamSlavePipes dtldStreamSlavePipes;
//         interface DtldStreamSlaveWritePipes writePipeIfc;
//             interface  writeMetaPipeIn  = toPipeIn(slaveSideQueueWm);
//             interface  writeDataPipeIn  = toPipeIn(slaveSideQueueWd);
//         endinterface

//         interface DtldStreamSlaveReadPipes readPipeIfc;
//             interface  readMetaPipeIn  = toPipeIn(slaveSideQueueRm);
//             interface  readDataPipeOut = toPipeOut(slaveSideQueueRd);
//         endinterface
//     endinterface

//     interface cpltTlpDataStreamPipeIn = toPipeIn(cpltTlpDataStreamPipeInQueue);

//     interface tagAllocPipeOutVec            = tagAllocPipeOutVecInst;
//     interface tagAllocPipeInVec             = tagAllocPipeInVecInst;

//     interface writeSourceChannelIdPipeIn    = toPipeIn(writeSourceChannelIdPipeInQueue);
//     interface readSourceChannelIdPipeIn     = toPipeIn(readSourceChannelIdPipeInQueue);

//     interface cpltTlpHeaderPipeIn           = toPipeIn(cpltTlpQueue);
//     interface tlpHeaderBufferPipeOut        = toPipeOut(arbittedTlpBufferQueue);
//     interface tlpDataStreamPipeOut          = toPipeOut(arbittedTlpDataStreamQueue);
// endmodule



// typedef enum {
//     TlpHeaderAndDataCombinatorStateIdle  = 0,
//     TlpHeaderAndDataCombinatorStateSendA = 1,
//     TlpHeaderAndDataCombinatorStateSendB = 2
// } TlpHeaderAndDataCombinatorState deriving(FShow, Eq, Bits);

// /*
//     ND = NO Data
//     HN = Has Next beat
//     LL = Last beat Less than half of beat used
//     LM = Last beat More than half of beat used
// */
// typedef enum {
//     TlpHeaderAndDataCombinatorChannelDataStateND = 0,
//     TlpHeaderAndDataCombinatorChannelDataStateHN = 1,
//     TlpHeaderAndDataCombinatorChannelDataStateLL = 2,
//     TlpHeaderAndDataCombinatorChannelDataStateLM = 3
// } TlpHeaderAndDataCombinatorChannelDataState deriving(FShow, Eq, Bits);

// typedef 2 CHANNEL_PER_TLP_HEADER_TX_ARBITTER;
// typedef TDiv#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, CHANNEL_PER_TLP_HEADER_TX_ARBITTER) TLP_HEADER_TX_ARBITTER_COUNT;

// interface TlpHeaderAndDataCombinator;
//     interface Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(FtileMacTlpHeaderBuffer))                           tlpHeaderBufferPipeInVec;
//     interface Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(FtileMacStreamData))                                tlpDataStreamPipeInVec;
//     interface PipeIn#(FtileMacStreamData)                                                                       tlpCpltDataPipeIn;
//     interface PipeOut#(FtileMacTxBeat)                                                                          ftilemacTxPipeOut;
// endinterface

// (* synthesize *)
// module mkTlpHeaderAndDataCombinator(TlpHeaderAndDataCombinator);
//     Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(FtileMacTlpHeaderBuffer))                          tlpHeaderBufferPipeInVecInst   = newVector;
//     Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(FtileMacStreamData))                               tlpDataStreamPipeInVecInst     = newVector;

//     Vector#(TLP_HEADER_TX_ARBITTER_COUNT, FIFOF#(FtileMacTlpHeaderBuffer))                           tlpHeaderBufferPipeInQueueVec  <- replicateM(mkFIFOF);
//     Vector#(TLP_HEADER_TX_ARBITTER_COUNT, FIFOF#(FtileMacStreamData))                                tlpDataStreamPipeInQueueVec    <- replicateM(mkFIFOF);

//     for (Integer arbiterChannelIdx = 0; arbiterChannelIdx < valueOf(TLP_HEADER_TX_ARBITTER_COUNT); arbiterChannelIdx = arbiterChannelIdx + 1) begin
//         tlpHeaderBufferPipeInVecInst[arbiterChannelIdx] = toPipeIn(tlpHeaderBufferPipeInQueueVec[arbiterChannelIdx]);
//         tlpDataStreamPipeInVecInst[arbiterChannelIdx]   = toPipeIn(tlpDataStreamPipeInQueueVec[arbiterChannelIdx]);
//     end

//     FIFOF#(FtileMacStreamData)                              tlpCpltDataPipeInQueue  <- mkFIFOF;
//     FIFOF#(FtileMacTxBeat)                                  ftilemacTxPipeOutQueue      <- mkFIFOF;

//     Reg#(Bool) arbiterNextChannelIsChannelZero <- mkReg(True);
//     Reg#(Bool) currentChannelIsChannelZero <- mkReg(True);

//     Reg#(TlpHeaderAndDataCombinatorState) stateReg <- mkReg(TlpHeaderAndDataCombinatorStateIdle);

//     Reg#(Maybe#(FtileMacStreamData)) previousBeatMaybeReg <- mkReg(tagged Invalid);


//     function Bool isDataStreamBeatUseLessThanHalf(FtileMacStreamData ds);
//         let zeroBasedByteNum = ds.byteNum - 1;
//         return msb(pack(zeroBasedByteNum) << 1) == 0;
//     endfunction

//     function Bool isDataStreamSegment1Or3Used(FtileMacStreamData ds);
//         let zeroBasedByteNum = ds.byteNum - 1;
//         return msb(pack(zeroBasedByteNum) << 2) == 0;
//     endfunction


//     rule mixOutputIdle if (stateReg == TlpHeaderAndDataCombinatorStateIdle);
//         let  headerA = unpack(0);
//         let  headerB = unpack(0);

//         Bool hasHeaderA = False;
//         Bool hasHeaderB = False;
//         let  payloadDsA = unpack(0);
//         let  payloadDsB = unpack(0);
//         Bool hasPayloadA = False;
//         Bool hasPayloadB = False;

//         if (tlpHeaderBufferPipeInQueueVec[0].notEmpty) begin
//             hasHeaderA = True;
//             headerA = tlpHeaderBufferPipeInQueueVec[0].first;
//             let isChannelZeroHasPayload = isFtileMacTlpHasPayload(headerA);
//             if (isChannelZeroHasPayload) begin
//                 payloadDsA = tlpDataStreamPipeInQueueVec[0].first;
//                 hasPayloadA = True;
//             end
//         end

//         if (tlpHeaderBufferPipeInQueueVec[1].notEmpty) begin
//             hasHeaderB = True;
//             headerB = tlpHeaderBufferPipeInQueueVec[1].first;
//             let isChannelZeroHasPayload = isFtileMacTlpHasPayload(headerB);
//             if (isChannelZeroHasPayload) begin
//                 payloadDsB = tlpDataStreamPipeInQueueVec[1].first;
//                 hasPayloadB = True;
//             end
//         end
        
//         Bool payloadExceedHalfA = !isDataStreamBeatUseLessThanHalf(payloadDsA);
//         Bool payloadExceedHalfB = !isDataStreamBeatUseLessThanHalf(payloadDsB);

//         // Bool isPayloadOnlyBeatA = payloadDsA.isFirst && payloadDsA.isLast;
//         // Bool isPayloadOnlyBeatB = payloadDsB.isFirst && payloadDsB.isLast;

//         Bool hasMoreDataA = !payloadDsA.isLast;
//         Bool hasMoreDataB = !payloadDsB.isLast;

//         Bool isSegment1Or3UsedA = isDataStreamSegment1Or3Used(payloadDsA);
//         Bool isSegment1Or3UsedB = isDataStreamSegment1Or3Used(payloadDsB);

//         TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateA = ?;
//         TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateB = ?;

//         if (!hasPayloadA) begin
//             channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateND;
//         end
//         else if (hasMoreDataA) begin
//             channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateHN;
//         end
//         else begin
//             channelDataLogicStateA = payloadExceedHalfA ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
//         end

//         if (!hasPayloadB) begin
//             channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateND;
//         end
//         else if (hasMoreDataB) begin
//             channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateHN;
//         end
//         else begin
//             channelDataLogicStateB = payloadExceedHalfB ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
//         end



//         FtileMacDataBusSegBundle         dataOut    = unpack(0);
//         FtileMacTlpHeaderBusSegBundle       headerOut  = unpack(0);
//         SopSignalBundle                 sopOut     = unpack(0);
//         EopSignalBundle                 eopOut     = unpack(0);
//         HvalidSignalBundle              hvalidOut  = unpack(0);
//         DvalidSignalBundle              dvalidOut  = unpack(0);


//         FtileMacDataBusSegBundle payloadAsFtileMacDataBundleA = unpack(payloadDsA.data);
//         FtileMacDataBusSegBundle payloadAsFtileMacDataBundleB = unpack(payloadDsB.data);

        

//         if (hasHeaderA) begin
//             headerOut[0] = headerA;
//             tlpHeaderBufferPipeInQueueVec[0].deq;
//             hvalidOut[0] = 1;
//             sopOut[0] = 1;
//             if (hasPayloadA) begin
//                 tlpDataStreamPipeInQueueVec[0].deq;
//             end

//             dataOut[0] = payloadAsFtileMacDataBundleA[0];
//             dataOut[1] = payloadAsFtileMacDataBundleA[1];
//             dvalidOut[0] = pack(hasPayloadA);
//             dvalidOut[1] = pack(hasPayloadA && (payloadExceedHalfA || (!payloadExceedHalfA && isSegment1Or3UsedA)));


//             $display(
//                 "time=%0t:", $time, toGreen(" mkTlpHeaderAndDataCombinator mixOutputIdle"),
//                 toBlue(", channelDataLogicStateA="), fshow(channelDataLogicStateA),
//                 toBlue(", payloadAsFtileMacDataBundleA="), fshow(payloadAsFtileMacDataBundleA) 
//             );

//             case (channelDataLogicStateA) 
//                 TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                     dataOut[2] = payloadAsFtileMacDataBundleA[2];
//                     dataOut[3] = payloadAsFtileMacDataBundleA[3];
//                     dvalidOut[2] = 1; dvalidOut[3] = 1;
//                     stateReg <= TlpHeaderAndDataCombinatorStateSendA;
//                 end
//                 TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                     dataOut[2] = payloadAsFtileMacDataBundleA[2];
//                     dataOut[3] = payloadAsFtileMacDataBundleA[3];
//                     dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedA);
//                     eopOut[2] = pack(!isSegment1Or3UsedA); eopOut[3] = pack(isSegment1Or3UsedA);
//                 end
//                 TlpHeaderAndDataCombinatorChannelDataStateLL, TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                     if (channelDataLogicStateA == TlpHeaderAndDataCombinatorChannelDataStateLL) begin
//                         eopOut[0] = pack(!isSegment1Or3UsedA); eopOut[1] = pack(isSegment1Or3UsedA);
//                     end
//                     else begin
//                         eopOut[0] = 1;
//                     end

//                     if (hasHeaderB) begin
//                         headerOut[2] = headerB;
//                         tlpHeaderBufferPipeInQueueVec[1].deq;
//                         hvalidOut[2] = 1;
//                         sopOut[2] = 1;
//                     end
//                     if (hasPayloadB) begin
//                         tlpDataStreamPipeInQueueVec[1].deq;
//                     end

//                     $display(
//                         "time=%0t:", $time, toGreen(" mkTlpHeaderAndDataCombinator mixOutputIdle"),
//                         toBlue(", channelDataLogicStateB="), fshow(channelDataLogicStateB),
//                         toBlue(", payloadAsFtileMacDataBundleB="), fshow(payloadAsFtileMacDataBundleB) 
//                     );

//                     case (channelDataLogicStateB)
//                         TlpHeaderAndDataCombinatorChannelDataStateLL: begin
//                             dataOut[2] = payloadAsFtileMacDataBundleB[0];
//                             dataOut[3] = payloadAsFtileMacDataBundleB[1];
//                             dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
//                             eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
//                         end
//                         TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                             dataOut[2] = payloadAsFtileMacDataBundleB[0];
//                             dataOut[3] = payloadAsFtileMacDataBundleB[1];
//                             dvalidOut[2] = 1; dvalidOut[3] = 1;
//                             previousBeatMaybeReg <= tagged Valid payloadDsB;
//                             stateReg <= TlpHeaderAndDataCombinatorStateSendB;
//                         end
//                         TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                             dataOut[2] = payloadAsFtileMacDataBundleB[0];
//                             dataOut[3] = payloadAsFtileMacDataBundleB[1];
//                             dvalidOut[2] = 1; dvalidOut[3] = 1;
//                             previousBeatMaybeReg <= tagged Valid payloadDsB;
//                             stateReg <= TlpHeaderAndDataCombinatorStateSendB;
//                         end
//                         TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                             eopOut[2] = 1;
//                         end
//                     endcase
//                 end
//             endcase

//             let outBeat = FtileMacTxBeat {
//                 data    : dataOut,
//                 header  : headerOut,
//                 sop     : sopOut,
//                 eop     : eopOut,
//                 hvalid  : hvalidOut,
//                 dvalid  : dvalidOut
//             };
//             ftilemacTxPipeOutQueue.enq(outBeat);
//         end
//         else if (hasHeaderB) begin
//             headerOut[0] = headerB;
//             tlpHeaderBufferPipeInQueueVec[1].deq;
//             hvalidOut[0] = 1;
//             sopOut[0] = 1;
//             if (hasPayloadB) begin
//                 tlpDataStreamPipeInQueueVec[1].deq;
//             end

//             dataOut[0] = payloadAsFtileMacDataBundleB[0];
//             dataOut[1] = payloadAsFtileMacDataBundleB[1];
//             dvalidOut[0] = pack(hasPayloadB);
//             dvalidOut[1] = pack(hasPayloadB && (payloadExceedHalfB || (!payloadExceedHalfB && isSegment1Or3UsedB)));

//             case (channelDataLogicStateB) 
//                 TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                     dataOut[2] = payloadAsFtileMacDataBundleB[2];
//                     dataOut[3] = payloadAsFtileMacDataBundleB[3];
//                     dvalidOut[2] = 1; dvalidOut[3] = 1;
//                     stateReg <= TlpHeaderAndDataCombinatorStateSendB;
//                 end
//                 TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                     dataOut[2] = payloadAsFtileMacDataBundleB[2];
//                     dataOut[3] = payloadAsFtileMacDataBundleB[3];
//                     dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
//                     eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
//                 end
//                 TlpHeaderAndDataCombinatorChannelDataStateLL: begin
//                     eopOut[0] = pack(!isSegment1Or3UsedB); eopOut[1] = pack(isSegment1Or3UsedB);
//                 end
//                 TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                     eopOut[0] = 1;
//                 end
//             endcase

//             let outBeat = FtileMacTxBeat {
//                 data    : dataOut,
//                 header  : headerOut,
//                 sop     : sopOut,
//                 eop     : eopOut,
//                 hvalid  : hvalidOut,
//                 dvalid  : dvalidOut
//             };
//             ftilemacTxPipeOutQueue.enq(outBeat);
//         end


//     endrule


//     rule mixOutputSendA if (stateReg == TlpHeaderAndDataCombinatorStateSendA);

//         FtileMacDataBusSegBundle payloadAsFtileMacDataBundleA    = ?;
//         Bool                    payloadExceedHalfA          = ?;
//         Bool                    isSegment1Or3UsedA          = ?;
//         Bool                    hasMoreDataA                = ?;

//         let                     prevPayloadDsA                  = fromMaybe(?, previousBeatMaybeReg);
//         FtileMacDataBusSegBundle previousPayloadAsFtileMacDataBundle = unpack(prevPayloadDsA.data);
//         Bool                    isPreviousBeatSegment1Or3Used   = isDataStreamSegment1Or3Used(prevPayloadDsA);
//         Bool                    isPreviousPayloadExceedHalf     = !isDataStreamBeatUseLessThanHalf(prevPayloadDsA);

//         let newPayloadDsA = unpack(0);
//         if (tlpDataStreamPipeInQueueVec[0].notEmpty) begin
//             newPayloadDsA = tlpDataStreamPipeInQueueVec[0].first;
//             tlpDataStreamPipeInQueueVec[0].deq;
//         end
//         FtileMacDataBusSegBundle newPayloadAsFtileMacDataBundle  = unpack(newPayloadDsA.data);
//         Bool                    isNewBeatSegment1Or3Used    = isDataStreamSegment1Or3Used(newPayloadDsA);
//         Bool                    isNewPayloadExceedHalf      = !isDataStreamBeatUseLessThanHalf(newPayloadDsA);

//         if (isValid(previousBeatMaybeReg)) begin
            
//             payloadAsFtileMacDataBundleA[0] = previousPayloadAsFtileMacDataBundle[2];
//             payloadAsFtileMacDataBundleA[1] = previousPayloadAsFtileMacDataBundle[3];

//             if (prevPayloadDsA.isLast) begin
//                 payloadExceedHalfA = False;
//                 isSegment1Or3UsedA = isPreviousBeatSegment1Or3Used;
//                 hasMoreDataA = False;
//             end
//             else begin
//                 payloadAsFtileMacDataBundleA[2] = newPayloadAsFtileMacDataBundle[0];
//                 payloadAsFtileMacDataBundleA[3] = newPayloadAsFtileMacDataBundle[1];
//                 payloadExceedHalfA = True;
//                 hasMoreDataA = isNewPayloadExceedHalf;
//                 if (isNewPayloadExceedHalf) begin
//                     isSegment1Or3UsedA = True;  // seg 3 must be used.
//                 end
//                 else begin
//                     isSegment1Or3UsedA = isNewBeatSegment1Or3Used;
//                 end
//             end
//         end
//         else begin
//             payloadAsFtileMacDataBundleA    = newPayloadAsFtileMacDataBundle;
//             payloadExceedHalfA          = isNewPayloadExceedHalf;
//             isSegment1Or3UsedA          = isNewBeatSegment1Or3Used;
//             hasMoreDataA                = !newPayloadDsA.isLast;
//         end
        
//         let  headerB = unpack(0);
//         Bool hasHeaderB     = False;
//         let  payloadDsB     = unpack(0);
//         Bool hasPayloadB    = False;

//         if (tlpHeaderBufferPipeInQueueVec[1].notEmpty) begin
//             hasHeaderB = True;
//             headerB = tlpHeaderBufferPipeInQueueVec[1].first;
//             let isChannelZeroHasPayload = isFtileMacTlpHasPayload(headerB);
//             if (isChannelZeroHasPayload) begin
//                 payloadDsB = tlpDataStreamPipeInQueueVec[1].first;
//                 hasPayloadB = True;
//             end
//         end        
//         FtileMacDataBusSegBundle payloadAsFtileMacDataBundleB = unpack(payloadDsB.data);
//         Bool payloadExceedHalfB = !isDataStreamBeatUseLessThanHalf(payloadDsB);
//         Bool hasMoreDataB = !payloadDsB.isLast;
//         Bool isSegment1Or3UsedB = isDataStreamSegment1Or3Used(payloadDsB);


//         TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateA = ?;
//         TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateB = ?;

//         if (hasMoreDataA) begin
//             channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateHN;
//         end
//         else begin
//             channelDataLogicStateA = payloadExceedHalfA ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
//         end

//         if (!hasPayloadB) begin
//             channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateND;
//         end
//         else if (hasMoreDataB) begin
//             channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateHN;
//         end
//         else begin
//             channelDataLogicStateB = payloadExceedHalfB ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
//         end



//         FtileMacDataBusSegBundle         dataOut    = unpack(0);
//         FtileMacTlpHeaderBusSegBundle       headerOut  = unpack(0);
//         SopSignalBundle                 sopOut     = unpack(0);
//         EopSignalBundle                 eopOut     = unpack(0);
//         HvalidSignalBundle              hvalidOut  = unpack(0);
//         DvalidSignalBundle              dvalidOut  = unpack(0);


//         dataOut[0] = payloadAsFtileMacDataBundleA[0];
//         dataOut[1] = payloadAsFtileMacDataBundleA[1];
//         dvalidOut[0] = 1;
//         dvalidOut[1] = pack(payloadExceedHalfA || (!payloadExceedHalfA && isSegment1Or3UsedA));

//         case (channelDataLogicStateA) 
//             TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                 dataOut[2] = payloadAsFtileMacDataBundleA[2];
//                 dataOut[3] = payloadAsFtileMacDataBundleA[3];
//                 dvalidOut[2] = 1; dvalidOut[3] = 1;
//                 if (isValid(previousBeatMaybeReg)) begin
//                     // is the first beat is started at 0, then all the following beat also aligned, no previousBeatReg is needed
//                     // but if the first beat is shared with another channel (not atarted at 0, but started at half of the beat),
//                     // then all the following beat need previousBeatReg to concat the data.
//                     previousBeatMaybeReg <= tagged Valid newPayloadDsA;
//                 end
//             end
//             TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                 dataOut[2] = payloadAsFtileMacDataBundleA[2];
//                 dataOut[3] = payloadAsFtileMacDataBundleA[3];
//                 dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedA);
//                 eopOut[2] = pack(!isSegment1Or3UsedA); eopOut[3] = pack(isSegment1Or3UsedA);
//                 previousBeatMaybeReg <= tagged Invalid;
//                 stateReg <= TlpHeaderAndDataCombinatorStateIdle;
//             end
//             TlpHeaderAndDataCombinatorChannelDataStateLL: begin
//                 eopOut[0] = pack(!isSegment1Or3UsedA); eopOut[1] = pack(isSegment1Or3UsedA);

//                 if (hasHeaderB) begin
//                     headerOut[2] = headerB;
//                     tlpHeaderBufferPipeInQueueVec[1].deq;
//                     hvalidOut[2] = 1;
//                     sopOut[2] = 1;
//                 end
//                 if (hasPayloadB) begin
//                     tlpDataStreamPipeInQueueVec[1].deq;
//                 end

//                 case (channelDataLogicStateB)
//                     TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                         previousBeatMaybeReg <= tagged Invalid;
//                         stateReg <= TlpHeaderAndDataCombinatorStateIdle;
//                         eopOut[2] = 1;
//                     end
//                     TlpHeaderAndDataCombinatorChannelDataStateLL: begin
//                         dataOut[2] = payloadAsFtileMacDataBundleB[0];
//                         dataOut[3] = payloadAsFtileMacDataBundleB[1];
//                         dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
//                         eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
//                         previousBeatMaybeReg <= tagged Invalid;
//                         stateReg <= TlpHeaderAndDataCombinatorStateIdle;
//                     end
//                     TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                         dataOut[2] = payloadAsFtileMacDataBundleB[0];
//                         dataOut[3] = payloadAsFtileMacDataBundleB[1];
//                         dvalidOut[2] = 1; dvalidOut[3] = 1;
//                         previousBeatMaybeReg <= tagged Valid payloadDsB;
//                         stateReg <= TlpHeaderAndDataCombinatorStateSendB;
//                     end
//                     TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                         dataOut[2] = payloadAsFtileMacDataBundleB[0];
//                         dataOut[3] = payloadAsFtileMacDataBundleB[1];
//                         dvalidOut[2] = 1; dvalidOut[3] = 1;
//                         previousBeatMaybeReg <= tagged Valid payloadDsB;
//                         stateReg <= TlpHeaderAndDataCombinatorStateSendB;
//                     end
//                 endcase
//             end
//             TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                 immFail("should not reach here. In this state, channel A must have data", $format(""));
//             end
//         endcase

//         let outBeat = FtileMacTxBeat {
//             data    : dataOut,
//             header  : headerOut,
//             sop     : sopOut,
//             eop     : eopOut,
//             hvalid  : hvalidOut,
//             dvalid  : dvalidOut
//         };
//         ftilemacTxPipeOutQueue.enq(outBeat);
//     endrule

    


//     rule mixOutputSendB if (stateReg == TlpHeaderAndDataCombinatorStateSendB);

//         FtileMacDataBusSegBundle payloadAsFtileMacDataBundleB    = ?;
//         Bool                    payloadExceedHalfB          = ?;
//         Bool                    isSegment1Or3UsedB          = ?;
//         Bool                    hasMoreDataB                = ?;

//         let                     prevPayloadDsB                  = fromMaybe(?, previousBeatMaybeReg);
//         FtileMacDataBusSegBundle previousPayloadAsFtileMacDataBundle = unpack(prevPayloadDsB.data);
//         Bool                    isPreviousBeatSegment1Or3Used   = isDataStreamSegment1Or3Used(prevPayloadDsB);
//         Bool                    isPreviousPayloadExceedHalf     = !isDataStreamBeatUseLessThanHalf(prevPayloadDsB);

//         let newPayloadDsB = unpack(0);
//         if (tlpDataStreamPipeInQueueVec[1].notEmpty) begin
//             newPayloadDsB = tlpDataStreamPipeInQueueVec[1].first;
//             tlpDataStreamPipeInQueueVec[1].deq;
//         end
//         FtileMacDataBusSegBundle newPayloadAsFtileMacDataBundle  = unpack(newPayloadDsB.data);
//         Bool                    isNewBeatSegment1Or3Used    = isDataStreamSegment1Or3Used(newPayloadDsB);
//         Bool                    isNewPayloadExceedHalf      = !isDataStreamBeatUseLessThanHalf(newPayloadDsB);

//         if (isValid(previousBeatMaybeReg)) begin
            
//             payloadAsFtileMacDataBundleB[0] = previousPayloadAsFtileMacDataBundle[2];
//             payloadAsFtileMacDataBundleB[1] = previousPayloadAsFtileMacDataBundle[3];

//             if (prevPayloadDsB.isLast) begin
//                 payloadExceedHalfB = False;
//                 isSegment1Or3UsedB = isPreviousBeatSegment1Or3Used;
//                 hasMoreDataB = False;
//             end
//             else begin
//                 payloadAsFtileMacDataBundleB[2] = newPayloadAsFtileMacDataBundle[0];
//                 payloadAsFtileMacDataBundleB[3] = newPayloadAsFtileMacDataBundle[1];
//                 payloadExceedHalfB = True;
//                 hasMoreDataB = isNewPayloadExceedHalf;
//                 if (isNewPayloadExceedHalf) begin
//                     isSegment1Or3UsedB = True;  // seg 3 must be used.
//                 end
//                 else begin
//                     isSegment1Or3UsedB = isNewBeatSegment1Or3Used;
//                 end
//             end
//         end
//         else begin
//             payloadAsFtileMacDataBundleB    = newPayloadAsFtileMacDataBundle;
//             payloadExceedHalfB          = isNewPayloadExceedHalf;
//             isSegment1Or3UsedB          = isNewBeatSegment1Or3Used;
//             hasMoreDataB                = !newPayloadDsB.isLast;
//         end
        
//         let  headerA = unpack(0);
//         Bool hasHeaderA     = False;
//         let  payloadDsA     = unpack(0);
//         Bool hasPayloadA    = False;

//         if (tlpHeaderBufferPipeInQueueVec[0].notEmpty) begin
//             hasHeaderA = True;
//             headerA = tlpHeaderBufferPipeInQueueVec[0].first;
//             let isChannelZeroHasPayload = isFtileMacTlpHasPayload(headerA);
//             if (isChannelZeroHasPayload) begin
//                 payloadDsA = tlpDataStreamPipeInQueueVec[0].first;
//                 hasPayloadA = True;
//             end
//         end        
//         FtileMacDataBusSegBundle payloadAsFtileMacDataBundleA = unpack(payloadDsA.data);
//         Bool payloadExceedHalfA = !isDataStreamBeatUseLessThanHalf(payloadDsA);
//         Bool hasMoreDataA = !payloadDsA.isLast;
//         Bool isSegment1Or3UsedA = isDataStreamSegment1Or3Used(payloadDsA);


//         TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateA = ?;
//         TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateB = ?;

//         if (hasMoreDataB) begin
//             channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateHN;
//         end
//         else begin
//             channelDataLogicStateB = payloadExceedHalfB ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
//         end

//         if (!hasPayloadA) begin
//             channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateND;
//         end
//         else if (hasMoreDataA) begin
//             channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateHN;
//         end
//         else begin
//             channelDataLogicStateA = payloadExceedHalfA ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
//         end



//         FtileMacDataBusSegBundle         dataOut    = unpack(0);
//         FtileMacTlpHeaderBusSegBundle       headerOut  = unpack(0);
//         SopSignalBundle                 sopOut     = unpack(0);
//         EopSignalBundle                 eopOut     = unpack(0);
//         HvalidSignalBundle              hvalidOut  = unpack(0);
//         DvalidSignalBundle              dvalidOut  = unpack(0);


//         dataOut[0] = payloadAsFtileMacDataBundleB[0];
//         dataOut[1] = payloadAsFtileMacDataBundleB[1];
//         dvalidOut[0] = 1;
//         dvalidOut[1] = pack(payloadExceedHalfB || (!payloadExceedHalfB && isSegment1Or3UsedB));

//         case (channelDataLogicStateB) 
//             TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                 dataOut[2] = payloadAsFtileMacDataBundleB[2];
//                 dataOut[3] = payloadAsFtileMacDataBundleB[3];
//                 dvalidOut[2] = 1; dvalidOut[3] = 1;
//                 if (isValid(previousBeatMaybeReg)) begin
//                     // is the first beat is started at 0, then all the following beat also aligned, no previousBeatReg is needed
//                     // but if the first beat is shared with another channel (not atarted at 0, but started at half of the beat),
//                     // then all the following beat need previousBeatReg to concat the data.
//                     previousBeatMaybeReg <= tagged Valid newPayloadDsB;
//                 end
//             end
//             TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                 dataOut[2] = payloadAsFtileMacDataBundleB[2];
//                 dataOut[3] = payloadAsFtileMacDataBundleB[3];
//                 dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
//                 eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
//                 previousBeatMaybeReg <= tagged Invalid;
//                 stateReg <= TlpHeaderAndDataCombinatorStateIdle;
//             end
//             TlpHeaderAndDataCombinatorChannelDataStateLL: begin
//                 eopOut[0] = pack(!isSegment1Or3UsedB); eopOut[1] = pack(isSegment1Or3UsedB);

//                 if (hasHeaderA) begin
//                     headerOut[2] = headerA;
//                     tlpHeaderBufferPipeInQueueVec[0].deq;
//                     hvalidOut[2] = 1;
//                     sopOut[2] = 1;
//                 end
//                 if (hasPayloadA) begin
//                     tlpDataStreamPipeInQueueVec[0].deq;
//                 end

//                 case (channelDataLogicStateA)
//                     TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                         previousBeatMaybeReg <= tagged Invalid;
//                         stateReg <= TlpHeaderAndDataCombinatorStateIdle;
//                         eopOut[2] = 1;
//                     end
//                     TlpHeaderAndDataCombinatorChannelDataStateLL: begin
//                         dataOut[2] = payloadAsFtileMacDataBundleA[0];
//                         dataOut[3] = payloadAsFtileMacDataBundleA[1];
//                         dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedA);
//                         eopOut[2] = pack(!isSegment1Or3UsedA); eopOut[3] = pack(isSegment1Or3UsedA);
//                         previousBeatMaybeReg <= tagged Invalid;
//                         stateReg <= TlpHeaderAndDataCombinatorStateIdle;
//                     end
//                     TlpHeaderAndDataCombinatorChannelDataStateLM: begin
//                         dataOut[2] = payloadAsFtileMacDataBundleA[0];
//                         dataOut[3] = payloadAsFtileMacDataBundleA[1];
//                         dvalidOut[2] = 1; dvalidOut[3] = 1;
//                         previousBeatMaybeReg <= tagged Valid payloadDsA;
//                         stateReg <= TlpHeaderAndDataCombinatorStateSendA;
//                     end
//                     TlpHeaderAndDataCombinatorChannelDataStateHN: begin
//                         dataOut[2] = payloadAsFtileMacDataBundleA[0];
//                         dataOut[3] = payloadAsFtileMacDataBundleA[1];
//                         dvalidOut[2] = 1; dvalidOut[3] = 1;
//                         previousBeatMaybeReg <= tagged Valid payloadDsA;
//                         stateReg <= TlpHeaderAndDataCombinatorStateSendA;
//                     end
//                 endcase
//             end
//             TlpHeaderAndDataCombinatorChannelDataStateND: begin
//                 immFail("should not reach here. In this state, channel A must have data", $format(""));
//             end
//         endcase

//         let outBeat = FtileMacTxBeat {
//             data    : dataOut,
//             header  : headerOut,
//             sop     : sopOut,
//             eop     : eopOut,
//             hvalid  : hvalidOut,
//             dvalid  : dvalidOut
//         };
//         ftilemacTxPipeOutQueue.enq(outBeat);
//     endrule

//     interface tlpHeaderBufferPipeInVec = tlpHeaderBufferPipeInVecInst;
//     interface tlpDataStreamPipeInVec = tlpDataStreamPipeInVecInst;

//     interface tlpCpltDataPipeIn = toPipeIn(tlpCpltDataPipeInQueue);
//     interface ftilemacTxPipeOut     = toPipeOut(ftilemacTxPipeOutQueue);
// endmodule




// interface FTileMacWithRawIfc;
//     (* always_ready, always_enabled *)
//     interface FTileMacAdaptorRx rxRawIfc;

//     (* always_ready, always_enabled *)
//     interface FTileMacAdaptorTx txRawIfc;

//     interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVec;
// endinterface

// module mkFTileMacWithRawIfc(FTileMacWithRawIfc);
//     let inner <- mkFTileMac;
//     let rawInterfaceAdaptor <- mkFTileMacAdaptor;

//     mkConnection(rawInterfaceAdaptor.ftilemacRxPipeOut, inner.ftilemacRxPipeIn);
//     mkConnection(rawInterfaceAdaptor.ftilemacTxPipeIn, inner.ftilemacTxPipeOut);

//     interface rxRawIfc = rawInterfaceAdaptor.rx;
//     interface txRawIfc = rawInterfaceAdaptor.tx;
//     interface streamSlaveIfcVec = inner.streamSlaveIfcVec;
// endmodule