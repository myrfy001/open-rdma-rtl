import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import Cntrs :: *;
import BRAMCore :: *;
import Arbiter :: * ;
import Connectable :: *;
import ConfigReg :: *;
import MIMO :: *;
import Reserved :: *;

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


typedef 16                                      FTILE_MAC_SEGMENT_CNT;
typedef TLog#(FTILE_MAC_SEGMENT_CNT)            FTILE_MAC_SEGMENT_IDX_WIDTH;
typedef Bit#(FTILE_MAC_SEGMENT_IDX_WIDTH)       FtileMacSegmentIdx;
typedef TAdd#(1, FTILE_MAC_SEGMENT_IDX_WIDTH)   FTILE_MAC_SEGMENT_CNT_WIDTH;
typedef Bit#(FTILE_MAC_SEGMENT_CNT_WIDTH)       FtileMacSegmentCnt;

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
typedef TLog#(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH)                    FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM; // 3
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

typedef 512 FTILE_MAC_RX_BRAM_BUFFER_DEPTH;
typedef TLog#(FTILE_MAC_RX_BRAM_BUFFER_DEPTH) FTILE_MAC_RX_BRAM_BUFFER_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_RX_BRAM_BUFFER_ADDR_WIDTH) FtileMacRxBramBufferAddr;



typedef struct {
    FtileMacRxBramBufferAddr        bufferAddr;         // 10
    SegmentEopEmptySignalBundle     eopEmpty;           // 48
    SegmentSopSignalBundle          sop;                // 16
    SegmentEopSignalBundle          eop;                // 16
    SegmentFcsErrorSignalBundle     fcsError;           // 16
    // SegmentRxMacErrorSignalBundle   error;          // 32
    // SegmentStatusDataSignalBundle   status_data;    // 48
} FtileMacRxPingPongSingleChannelProcessorInputMeta deriving(FShow, Bits);

typedef struct {
    FtileMacRxBramBufferAddr        bufferAddr;                // 10
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

                // $display(
                //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongSingleChannelProcessor handle output to meta buffer"),
                //     toBlue(", outPacketMeta="), fshow(outPacketMeta)
                // );
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

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongSingleChannelProcessor handle"),
        //     toBlue(", curProcessingSegIdx="), fshow(curProcessingSegIdx),
        //     toBlue(", startSegIdx="), fshow(startSegIdx),
        //     toBlue(", curProcessingMeta="), fshow(currentMeta),
        //     toBlue(", zeroBasedValidSegCntForPacket="), fshow(zeroBasedValidSegCntForPacket),
        //     toBlue(", curOutChannelIdx="), fshow(curOutChannelIdx),
        //     toBlue(", isPacketNumOverflow="), fshow(isPacketNumOverflow),
        //     toBlue(", isFirstForOutput="), fshow(isFirstForOutput),
        //     toBlue(", hasMetEopButNotSop="), fshow(hasMetEopButNotSop)
        // );
    endrule



    interface beatMetaPipeIn = toPipeIn(beatMetaPipeInQueue);
    interface packetsChunkMetaPipeOut = toPipeOut(packetsChunkMetaPipeOutQueue);
endmodule


typedef FTILE_MAC_SEGMENT_CNT FTILE_MAC_RX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT)) FtileMacRxPingPongChannelIdx;

typedef struct {
    FtileMacRxBramBufferAddr addr;
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

    Reg#(FtileMacRxBramBufferAddr) addrPtrReg <- mkReg(0);

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

        $display(
            "time=%0t:", $time, toGreen(" mkFtileMacRxBeatFork handleInputBeat"),
            toBlue(", channelIdxReg="), fshow(channelIdxReg)
        );
    endrule
    

    interface rxBetaPipeIn                      = toPipeIn(rxBetaPipeInQueue);
    interface rxPingPongChannelMetaPipeOutVec   = rxPingPongChannelMetaPipeOutVecInst;
    interface rxBramWriteReqPipeOut             = toPipeOut(rxBramWriteReqPipeOutQueue);
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

    Reg#(FtileMacUserLogicChannelIdx)  currentOutputChannelIdxReg       <- mkReg(0);
    Reg#(Bool)                         isCurrentPacketNotEndReg         <- mkReg(False);
    Reg#(Bool)                         isCurrentPacketShouldSkipReg     <- mkReg(False);
    Reg#(FtileMacRxPingPongChannelIdx) pingPongChannelIdxReg            <- mkReg(0);

    // use ConfigReg to solve conflict
    Reg#(Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacUserLogicChannelIdx)) curUserLogicChannelDispatchOrderReg <- mkConfigReg(vec(0, 1, 2, 3));


    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacRxPacketChunkMeta)) packetChunkMetaOutputBufferVec <- replicateM(mkSizedFIFOF(valueOf(PACKET_CHUNK_META_OUTPUT_BUFFER_DEPTH)));
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Count#(PacketBeatSegCnt)) outputChannelBufferUsedSegCounterVec <- replicateM(mkCount(0));

    // Pipeline FIFOs and Regs
    FIFOF#(FtileMacRxPingPongSingleChannelProcessorOutputMeta) selectedPingPongOutputChannelMetaPipelineQ <- mkFIFOF;
    FIFOF#(Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry)) dispatchPacketChunkMetaPipelineQ <- mkFIFOF;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(Bool)) discardOrOutputSignalPipelineQueueVec <- replicateM(mkFIFOF);

    Reg#(Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)))  bitonicSortPipelineReg <- mkRegU;

    rule generateNextDispatchOrderByBufferUsageStage1;
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep1Vec = vec (
            tuple2(0, outputChannelBufferUsedSegCounterVec[0]),
            tuple2(1, outputChannelBufferUsedSegCounterVec[1]),
            tuple2(2, outputChannelBufferUsedSegCounterVec[2]),
            tuple2(3, outputChannelBufferUsedSegCounterVec[3])
        );

        // first swap
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep2Vec = newVector;
        if (tpl_2(bitonicSortStep1Vec[0]) > tpl_2(bitonicSortStep1Vec[1])) begin
            bitonicSortStep2Vec[1] = bitonicSortStep1Vec[0];
            bitonicSortStep2Vec[0] = bitonicSortStep1Vec[1];
        end
        else begin
            bitonicSortStep2Vec[0] = bitonicSortStep1Vec[0];
            bitonicSortStep2Vec[1] = bitonicSortStep1Vec[1];
        end

        if (tpl_2(bitonicSortStep1Vec[2]) > tpl_2(bitonicSortStep1Vec[3])) begin
            bitonicSortStep2Vec[2] = bitonicSortStep1Vec[2];
            bitonicSortStep2Vec[3] = bitonicSortStep1Vec[3];
        end
        else begin
            bitonicSortStep2Vec[3] = bitonicSortStep1Vec[2];
            bitonicSortStep2Vec[2] = bitonicSortStep1Vec[3];
        end

        bitonicSortPipelineReg <= bitonicSortStep2Vec;
    endrule

    rule generateNextDispatchOrderByBufferUsageStage2;
        // second swap
        let bitonicSortStep2Vec = bitonicSortPipelineReg;
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep3Vec = newVector;
        if (tpl_2(bitonicSortStep2Vec[0]) > tpl_2(bitonicSortStep2Vec[2])) begin
            bitonicSortStep3Vec[2] = bitonicSortStep2Vec[0];
            bitonicSortStep3Vec[0] = bitonicSortStep2Vec[2];
        end
        else begin
            bitonicSortStep3Vec[0] = bitonicSortStep2Vec[0];
            bitonicSortStep3Vec[2] = bitonicSortStep2Vec[2];
        end

        if (tpl_2(bitonicSortStep2Vec[1]) > tpl_2(bitonicSortStep2Vec[3])) begin
            bitonicSortStep3Vec[3] = bitonicSortStep2Vec[1];
            bitonicSortStep3Vec[1] = bitonicSortStep2Vec[3];
        end
        else begin
            bitonicSortStep3Vec[1] = bitonicSortStep2Vec[1];
            bitonicSortStep3Vec[3] = bitonicSortStep2Vec[3];
        end

        // third swap
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep4Vec = newVector;
        if (tpl_2(bitonicSortStep3Vec[0]) > tpl_2(bitonicSortStep3Vec[1])) begin
            bitonicSortStep4Vec[1] = bitonicSortStep3Vec[0];
            bitonicSortStep4Vec[0] = bitonicSortStep3Vec[1];
        end
        else begin
            bitonicSortStep4Vec[0] = bitonicSortStep3Vec[0];
            bitonicSortStep4Vec[1] = bitonicSortStep3Vec[1];
        end

        if (tpl_2(bitonicSortStep3Vec[2]) > tpl_2(bitonicSortStep3Vec[3])) begin
            bitonicSortStep4Vec[3] = bitonicSortStep3Vec[2];
            bitonicSortStep4Vec[2] = bitonicSortStep3Vec[3];
        end
        else begin
            bitonicSortStep4Vec[2] = bitonicSortStep3Vec[2];
            bitonicSortStep4Vec[3] = bitonicSortStep3Vec[3];
        end

        curUserLogicChannelDispatchOrderReg <= vec(
            tpl_1(bitonicSortStep4Vec[0]),
            tpl_1(bitonicSortStep4Vec[1]),
            tpl_1(bitonicSortStep4Vec[2]),
            tpl_1(bitonicSortStep4Vec[3])
        );

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin generateNextDispatchOrderByBufferUsage"),
        //     toBlue(", bitonicSortStep1Vec="), fshow(bitonicSortStep1Vec), 
        //     toBlue(", bitonicSortStep4Vec="), fshow(bitonicSortStep4Vec)
        // );

    endrule

    rule selectAndForwardPingPongChannel;
        pingPongChannelIdxReg <= pingPongChannelIdxReg + 1;

        let pingPongOutputMeta = metaPipeInQueueVec[pingPongChannelIdxReg].first;
        metaPipeInQueueVec[pingPongChannelIdxReg].deq;

        selectedPingPongOutputChannelMetaPipelineQ.enq(pingPongOutputMeta);
    endrule

    rule forwardPacketsInOnePingPongChannelToFourOutputChannels;

        Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry) outputEntryVec = newVector;

        let inputPingPongMeta = selectedPingPongOutputChannelMetaPipelineQ.first;
        selectedPingPongOutputChannelMetaPipelineQ.deq;

        immAssert(
            isValid(inputPingPongMeta.packetChunkMetaVector[0]),
            "the input Vector's first element should not be Invalid",
            $format("")
        );

        for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT); idx = idx + 1) begin
            outputEntryVec[idx].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[idx];
        end

        let isCurrentPacketNotEnd       = isCurrentPacketNotEndReg;
        let isCurrentPacketShouldSkip   = isCurrentPacketShouldSkipReg;
        let currentOutputChannelIdx     = currentOutputChannelIdxReg;

        Vector#(TSub#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, 1), FtileMacUserLogicChannelIdx) dispatchOrderWithoutCurrentChannel = case (currentOutputChannelIdx)
            curUserLogicChannelDispatchOrderReg[0]: vec(curUserLogicChannelDispatchOrderReg[1], curUserLogicChannelDispatchOrderReg[2], curUserLogicChannelDispatchOrderReg[3]);
            curUserLogicChannelDispatchOrderReg[1]: vec(curUserLogicChannelDispatchOrderReg[0], curUserLogicChannelDispatchOrderReg[2], curUserLogicChannelDispatchOrderReg[3]);
            curUserLogicChannelDispatchOrderReg[2]: vec(curUserLogicChannelDispatchOrderReg[0], curUserLogicChannelDispatchOrderReg[1], curUserLogicChannelDispatchOrderReg[3]);
            curUserLogicChannelDispatchOrderReg[3]: vec(curUserLogicChannelDispatchOrderReg[0], curUserLogicChannelDispatchOrderReg[1], curUserLogicChannelDispatchOrderReg[2]);
        endcase;
        
        let isFirstPacketUseNewChannel  = False;

        // There is at most 3 packet to handle here.
        // Now handle the first one.
        let firstInputMeta = fromMaybe(?, inputPingPongMeta.packetChunkMetaVector[0]);
        if (isCurrentPacketNotEnd) begin
            if (isCurrentPacketShouldSkip) begin
                outputEntryVec[0].packetChunkMetaMaybe = tagged Invalid;
            end
            else begin
                outputEntryVec[0].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[0];
                outputEntryVec[0].targetChannelIdx = currentOutputChannelIdx;
            end
            if (firstInputMeta.isLast) begin
                isCurrentPacketShouldSkip   = False;
                isCurrentPacketNotEnd       = False;
            end
        end
        else begin
            immAssert(
                firstInputMeta.isFirst && !isCurrentPacketShouldSkip,
                "if the packet has finished in previous beat, then this must be first. And for a first beat, isCurrentPacketShouldSkip must already be set to False in previous beat",
                $format("firstInputMeta=", fshow(firstInputMeta), "isCurrentPacketShouldSkip=", fshow(isCurrentPacketShouldSkip))
            );

            currentOutputChannelIdx = dispatchOrderWithoutCurrentChannel[0];
            isFirstPacketUseNewChannel = True;
            outputEntryVec[0].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[0];
            outputEntryVec[0].targetChannelIdx = currentOutputChannelIdx;
            if (firstInputMeta.isLast) begin
                isCurrentPacketNotEnd       = False;
            end
            else begin
                isCurrentPacketNotEnd       = True;
            end
        end

        // Now handle the second one.
        if (inputPingPongMeta.packetChunkMetaVector[1] matches tagged Valid .secondInputMeta) begin
            immAssert(
                !isCurrentPacketNotEnd,
                "since the second meta is valid, the previous packet must be eop",
                $format("firstInputMeta=", fshow(firstInputMeta), "secondInputMeta=", fshow(secondInputMeta))
            );

            currentOutputChannelIdx = isFirstPacketUseNewChannel ? dispatchOrderWithoutCurrentChannel[1] : dispatchOrderWithoutCurrentChannel[0];
            outputEntryVec[1].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[1];
            outputEntryVec[1].targetChannelIdx = currentOutputChannelIdx;
            if (secondInputMeta.isLast) begin
                isCurrentPacketNotEnd       = False;
            end
            else begin
                isCurrentPacketNotEnd       = True;
            end
        end

        // Now handle the third one.
        if (inputPingPongMeta.packetChunkMetaVector[2] matches tagged Valid .thirdInputMeta) begin
            immAssert(
                !isCurrentPacketNotEnd,
                "since the third meta is valid, the previous packet must be eop",
                $format("thirdInputMeta=", fshow(thirdInputMeta))
            );

            currentOutputChannelIdx = isFirstPacketUseNewChannel ? dispatchOrderWithoutCurrentChannel[2] : dispatchOrderWithoutCurrentChannel[1];
            outputEntryVec[2].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[2];
            outputEntryVec[2].targetChannelIdx = currentOutputChannelIdx;
            if (thirdInputMeta.isLast) begin
                isCurrentPacketNotEnd       = False;
            end
            else begin
                isCurrentPacketNotEnd       = True;
            end
        end
        
        if (inputPingPongMeta.packetNumOverflowAffectNextBeat) begin
            isCurrentPacketShouldSkip = True;
            isCurrentPacketNotEnd     = True;
        end


        currentOutputChannelIdxReg <= currentOutputChannelIdx;
        isCurrentPacketNotEndReg <= isCurrentPacketNotEnd;
        isCurrentPacketShouldSkipReg <= isCurrentPacketShouldSkip;

        dispatchPacketChunkMetaPipelineQ.enq(outputEntryVec);

        $display(
            "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin forwardPacketsInOnePingPongChannelToFourOutputChannels"),
            toBlue(", inputPingPongMeta="), fshow(inputPingPongMeta), 
            toBlue(", outputEntryVec="), fshow(outputEntryVec),
            toBlue(", isCurrentPacketNotEndReg="), fshow(isCurrentPacketNotEndReg),
            toBlue(", isCurrentPacketNotEnd="), fshow(isCurrentPacketNotEnd)
        );
    endrule

    rule dispatchToOutputBuffer;
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
                if (metaToOutput.isLast) begin
                    let needDiscard = metaToOutput.isError;
                    discardOrOutputSignalPipelineQueueVec[userChannelIdx].enq(needDiscard);
                end
            end            
        end 
    endrule

    for (Integer userChannelIdx = 0; userChannelIdx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); userChannelIdx = userChannelIdx + 1) begin
        rule forwardFromOutputBufferToOutputIfc;
            let needDiscard = discardOrOutputSignalPipelineQueueVec[userChannelIdx].first;

            let metaToForward = packetChunkMetaOutputBufferVec[userChannelIdx].first;
            packetChunkMetaOutputBufferVec[userChannelIdx].deq;

            if (!needDiscard) begin
                packetChunkMetaPipeOutQueueVec[userChannelIdx].enq(metaToForward);
            end
            if (metaToForward.isLast) begin
                discardOrOutputSignalPipelineQueueVec[userChannelIdx].deq;
            end

            outputChannelBufferUsedSegCounterVec[userChannelIdx].decr(zeroExtend(metaToForward.zeroBasedValidSegCnt)+1);
        endrule
    end

    interface metaPipeInVec             = metaPipeInVecInst;
    interface packetChunkMetaPipeOutVec = packetChunkMetaPipeOutVecInst;
endmodule


typedef DtldStreamData#(DATA) FtileMacRxUserStream;
typedef FtileMacRxUserStream FtileMacTxUserStream;
typedef TDiv#(SizeOf#(FtileMacDataBusSegBundle), SizeOf#(DATA)) RTILE_RX_BRAM_BLOCK_CNT;   // 4
typedef TDiv#(SizeOf#(DATA), FTILE_MAC_DATA_SEGMENT_WIDTH) RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT;  // 4

typedef struct {
    Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT))    startBramBlockIdx;
    Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT))    endBramBlockIdx;
    FtileMacSegmentIdx                      firstOutputBeatShiftSegCnt;
    ByteEnBitNum                            firstOutputBeatByteNum;
    ByteEnBitNum                            lastOutputBeatByteNum;
    Bool                                    isFirst;             
    Bool                                    isLast;                    
} FtileMacRxGearBoxMeta deriving(Bits, FShow);

interface FtileMacRxPayloadStorageAndGearBox;
    interface PipeIn#(FtileMacRxBramBufferWriteReq)     rxBramWriteReqPipeIn;
    interface PipeIn#(FtileMacRxPacketChunkMeta)        packetChunkMetaPipeIn;
    interface PipeOut#(FtileMacRxUserStream)            streamPipeOut;
endinterface

module mkFtileMacRxPayloadStorageAndGearBox(FtileMacRxPayloadStorageAndGearBox);
    FIFOF#(FtileMacRxBramBufferWriteReq)    rxBramWriteReqPipeInQ   <- mkFIFOF;
    FIFOF#(FtileMacRxPacketChunkMeta)       packetChunkMetaPipeInQ  <- mkFIFOF;

    Vector#(RTILE_RX_BRAM_BLOCK_CNT, AutoInferBramQueuedOutput#(FtileMacRxBramBufferAddr, DATA))  dataStreamStorageVec  <- replicateM(mkAutoInferBramQueuedOutput(False, ""));

    UniDirStreamShifter#(DATA) outputShifter <- mkLsbRightStreamRightShifterG;

    Reg#(FtileMacRxBramBufferAddr)                  curReadAddrReg          <- mkRegU;
    Reg#(Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT)))      curReadBramBlockIdxReg  <- mkRegU;
    Reg#(Bool)                                      isReadIdleReg           <- mkReg(True);

    Reg#(Vector#(RTILE_RX_BRAM_BLOCK_CNT, DATA)) readBackDataVecReg <- mkRegU;

    // Pipeline Queue
    FIFOF#(FtileMacRxGearBoxMeta)           packetChunkMetaPipelineQ  <- mkSizedFIFOF(4); 


    // rule debug;
    //     $display(
    //         "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox debug"),
    //         toBlue(", dataStreamStorageVec[0].notEmpty="), fshow(dataStreamStorageVec[0].readRespPipeOut.notEmpty),
    //         toBlue(", packetChunkMetaPipelineQ.notEmpty="), fshow(packetChunkMetaPipelineQ.notEmpty)
    //     );
    // endrule

    rule handleWriteReq;
        let req = rxBramWriteReqPipeInQ.first;
        rxBramWriteReqPipeInQ.deq;

        for (Integer idx = 0; idx < valueOf(RTILE_RX_BRAM_BLOCK_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].write(req.addr, {req.data[idx * 4 + 3], req.data[idx * 4 + 2], req.data[idx * 4 + 1], req.data[idx * 4 + 0]});
        end
    endrule

    rule handleReadReq;
        let rawReq = packetChunkMetaPipeInQ.first;
        packetChunkMetaPipeInQ.deq;
        

        for (Integer idx = 0; idx < valueOf(RTILE_RX_BRAM_BLOCK_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].putReadReq(rawReq.bufferAddr);
        end

        let endSegIdx                                            = rawReq.startSegIdx + rawReq.zeroBasedValidSegCnt;
        Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT)) startBramBlockIdx   = truncateLSB(rawReq.startSegIdx);
        Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT)) endBramBlockIdx     = truncateLSB(endSegIdx);

        ByteEnBitNum lastOutputBeatByteNum = ?;
        ByteEnBitNum firstOutputBeatByteNum = ?;

        if (startBramBlockIdx == endBramBlockIdx) begin
            lastOutputBeatByteNum = ((zeroExtend(rawReq.zeroBasedValidSegCnt) + 1) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM)) - (rawReq.isLast ? zeroExtend(rawReq.lastSegEmptyByteCnt) : 0);
            firstOutputBeatByteNum = lastOutputBeatByteNum;
        end
        else begin
            Bit#(TLog#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)) zeroBasedSegCntInFirstBlock = maxBound - truncate(rawReq.startSegIdx);
            Bit#(TLog#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)) zeroBasedSegCntInLastBlock = truncate(endSegIdx);
    
            firstOutputBeatByteNum = ((zeroExtend(zeroBasedSegCntInFirstBlock) + 1) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM));
            lastOutputBeatByteNum = ((zeroExtend(zeroBasedSegCntInLastBlock) + 1) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM)) - (rawReq.isLast ? zeroExtend(rawReq.lastSegEmptyByteCnt) : 0);        
        end

        let meta = FtileMacRxGearBoxMeta {
            startBramBlockIdx           : startBramBlockIdx,
            endBramBlockIdx             : endBramBlockIdx,
            firstOutputBeatShiftSegCnt  : rawReq.startSegIdx,
            firstOutputBeatByteNum      : firstOutputBeatByteNum,
            lastOutputBeatByteNum       : lastOutputBeatByteNum,
            isFirst                     : rawReq.isFirst,
            isLast                      : rawReq.isLast
        };
        packetChunkMetaPipelineQ.enq(meta);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleReadReq"),
        //     toBlue(", meta="), fshow(meta)
        // );
    endrule

    rule handleReadResp;
        let meta = packetChunkMetaPipelineQ.first;

        if (isReadIdleReg) begin
            Vector#(RTILE_RX_BRAM_BLOCK_CNT, DATA) readBackDataVec = newVector;
            for (Integer idx = 0; idx < valueOf(RTILE_RX_BRAM_BLOCK_CNT); idx = idx + 1) begin
                readBackDataVec[idx] = dataStreamStorageVec[idx].readRespPipeOut.first;
                dataStreamStorageVec[idx].readRespPipeOut.deq;
            end


            let isLastBlock = meta.startBramBlockIdx == meta.endBramBlockIdx;
            let isFirst     = meta.isFirst;
            let isLast      = isLastBlock && meta.isLast;

            let byteNum = ?;
            if (isFirst) begin
                byteNum = meta.firstOutputBeatByteNum;
            end
            else if (isLast) begin
                byteNum = meta.lastOutputBeatByteNum;
            end
            else begin
                byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
            end

            let startByteIdx = isFirst ? zeroExtend(meta.firstOutputBeatShiftSegCnt) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM) : 0;
            let ds = FtileMacRxUserStream {
                data        : readBackDataVec[meta.startBramBlockIdx],
                byteNum     : byteNum,
                startByteIdx: startByteIdx,
                isFirst     : isFirst,
                isLast      : isLast
            };
            
            readBackDataVecReg <= readBackDataVec;
            curReadBramBlockIdxReg <= meta.startBramBlockIdx + 1;

            outputShifter.streamPipeIn.enq(ds);

            if (isFirst) begin
                outputShifter.offsetPipeIn.enq(startByteIdx);
            end

            if (!isLastBlock) begin
                isReadIdleReg <= False;
            end
            else begin
                packetChunkMetaPipelineQ.deq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleReadResp - FIRST"),
                toBlue(", ds="), fshow(ds),
                toBlue(", meta="), fshow(meta)
            );
        end
        else begin
            let isLastBlock = curReadBramBlockIdxReg == meta.endBramBlockIdx;
            let isLast      = isLastBlock && meta.isLast;

            let byteNum = ?;
            if (isLast) begin
                byteNum = meta.lastOutputBeatByteNum;
            end
            else begin
                byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
            end

            let ds = FtileMacRxUserStream {
                data        : readBackDataVecReg[curReadBramBlockIdxReg],
                byteNum     : byteNum,
                startByteIdx: 0,
                isFirst     : False,
                isLast      : isLast
            };
            outputShifter.streamPipeIn.enq(ds);

            curReadBramBlockIdxReg <= curReadBramBlockIdxReg + 1;

            if (isLastBlock) begin
                isReadIdleReg <= True;
                packetChunkMetaPipelineQ.deq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleReadResp - MORE"),
                toBlue(", ds="), fshow(ds),
                toBlue(", isLastBlock="), fshow(isLastBlock)
            );
        end
    endrule


    interface rxBramWriteReqPipeIn = toPipeIn(rxBramWriteReqPipeInQ);
    interface packetChunkMetaPipeIn = toPipeIn(packetChunkMetaPipeInQ);
    interface streamPipeOut = outputShifter.streamPipeOut;
endmodule



typedef 512 FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH;
typedef TLog#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH) FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH) FtileMacTxChannelBufferAddr;

// input DATA is buffered in a BRAM, each BRAM row has an address, and we further divide one row into segemnts, and give each segment and index.
// in this way, the higher part of the address is BRAM row address, and the lower part of the address is the segment index inside a row;
typedef TLog#(TDiv#(SizeOf#(DATA), FTILE_MAC_DATA_SEGMENT_WIDTH)) FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH;
typedef Bit#(FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH) FtileMacTxChannelBufferRowSegIdx;

typedef TAdd#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH, FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH) FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_SEG_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_SEG_ADDR_WIDTH) FtileMacTxChannelBufferSegAddr;
typedef FtileMacTxChannelBufferSegAddr FtileMacTxChannelBufferSegCnt;  // infact, we can redefine it to a shorter type to just hold a 4kB packte and addtional header part.


typedef struct {
    FtileMacTxChannelBufferSegAddr startSegAddr;
    FtileMacTxChannelBufferSegCnt  segCnt;
    FtileMacEopEmpty               eopEmpty;
} FtileMacTxBufferRange deriving(Bits, FShow);

typedef struct {
    FtileMacUserLogicChannelIdx         srcChannelIdx;
    FtileMacTxChannelBufferSegAddr      startSegAddr;
    FtileMacTxChannelBufferSegCnt       segCnt;
    FtileMacEopEmpty                    eopEmpty;
    FtileMacTxChannelBufferRowSegIdx    destSegOffset;
    ReservedZero#(3)                    reserved;           // make this struct's size is power of two, or the MIMO FIFO will use dsp block to implement multiply operation. cause very bad timing.
} FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset deriving(Bits, FShow);

typedef struct {
    FtileMacUserLogicChannelIdx         srcChannelIdx;
    FtileMacTxBramBufferAddr            startRowAddr;
    FtileMacSegmentIdx                  zeroBasedSegCnt;
    FtileMacEopEmpty                    eopEmpty;
    FtileMacTxChannelBufferRowSegIdx    destSegOffset;
    Bool                                isLast;
    // Bool                                isOutputBeatLast;
} FtileMacTxPingPongChannelMetaEntry deriving(Bits, FShow);


typedef 2 FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT;  // since the beta width is 1024 bits(128 bytes), and min eth packet is 64 bytes.
typedef 3 FTILE_MAC_TX_MAX_PACKET_PER_BEAT;
typedef TSub#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT, 1) FTILE_MAC_TX_MAX_OVERFLOW_SEG_CNT_PER_BEAT;
typedef FTILE_MAC_USER_LOGIC_CHANNEL_CNT FTILE_MAC_TX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT)) FtileMacTxOutputBeatNewPacketIndex;

typedef Vector#(FTILE_MAC_TX_MAX_PACKET_PER_BEAT, Maybe#(FtileMacTxPingPongChannelMetaEntry)) FtileMacTxPingPongChannelMetaBundle;

interface FtileMacTxPingPongFork;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(FtileMacTxBufferRange)) packetMetaPipeInVec;
    interface Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeOut#(FtileMacTxPingPongChannelMetaBundle))  pingpongChannelMetaPipeOutVec;
endinterface

(* synthesize *)
module mkFtileMacTxPingPongFork(FtileMacTxPingPongFork);
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(FtileMacTxBufferRange)) packetMetaPipeInVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacTxBufferRange)) packetMetaPipeInQueueVec <- replicateM(mkFIFOF);

    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeOut#(FtileMacTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, FIFOF#(FtileMacTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    

    for (Integer idx=0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        packetMetaPipeInVecInst[idx] = toPipeIn(packetMetaPipeInQueueVec[idx]);
    end

    for (Integer idx=0; idx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongChannelMetaPipeOutVecInst[idx] = toPipeOut(pingpongChannelMetaPipeOutQueueVec[idx]);
    end


    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Reg#(Maybe#(FtileMacTxBufferRange))) curDataRangeRegVec <- replicateM(mkReg(tagged Invalid));
    Reg#(FtileMacUserLogicChannelIdx) curInputRoundRobinIdxReg <- mkReg(0);
    Reg#(FtileMacUserLogicChannelIdx) curOutputRoundRobinIdxReg <- mkReg(0);
    Reg#(FtileMacTxChannelBufferRowSegIdx) prevDestSegOffsetReg <- mkReg(0);
    Reg#(FtileMacTxChannelBufferRowSegIdx) prevBeatSegOverflowCntReg <- mkReg(0);

    let mimoCfg = MIMOConfiguration {
        unguarded: False,
        bram_based: False
    };
    MIMO#(
        FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT,
            FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT,
            TMul#(2, FTILE_MAC_USER_LOGIC_CHANNEL_CNT),
            FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset
    ) selectedInputChannelMetaMIMO <- mkMIMO(mimoCfg);
    

    Reg#(Maybe#(FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) curMetaMaybeReg <- mkReg(tagged Invalid);

    // Pipeline Queues
    FIFOF#(Tuple2#(
        Vector#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT, FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset),
        LUInt#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT)
    ))  mimoInputPipelineQueue <- mkFIFOF;


    rule prepareRoundRobinChannelOrder;
        Vector#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT, FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset) vecToEnq = newVector;
        let curInputRoundRobinIdx = curInputRoundRobinIdxReg;
        let prevDestSegOffset = prevDestSegOffsetReg;
        let enqCnt = 0;
        case ({ pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].notEmpty)
            }) matches
            4'b0000: begin
            end
            4'b0001: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 1;
            end
            4'b0010: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    eopEmpty        : inMeta0.eopEmpty, 
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 1;
            end
            4'b0011: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].deq;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b0100: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 1;
            end
            4'b0101: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].deq;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b011?: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].deq;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b1000: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    eopEmpty        : inMeta0.eopEmpty, 
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 1;
                enqCnt = 1;
            end
            4'b1001: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].deq;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b101?: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].deq;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b11??: begin
                packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].deq;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].deq;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 2;
            end
        endcase

        curInputRoundRobinIdxReg <= curInputRoundRobinIdx;
        prevDestSegOffsetReg <= prevDestSegOffset;

        if (enqCnt != 0) begin
            selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
        end

        // mimoInputPipelineQueue.enq(tuple2(vecToEnq, enqCnt));
    endrule

    // rule forwardRoundRobinResultToMimoBuffer;
    //     let {vecToEnq, enqCnt} = mimoInputPipelineQueue.first;
    //     mimoInputPipelineQueue.deq;
    //     if (enqCnt != 0) begin
    //         selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
    //     end
    // endrule


    function FtileMacSegmentCnt roundUpUsedSegCount(FtileMacSegmentCnt inputCnt);
        // each user input 256-bit beat has 4 64-bit segment.
        // if we use only one segment, we also need to read 4 segment from BRAM
        return ((inputCnt >> 2) + 1) << 2;
    endfunction

    rule dispatch;
        FtileMacTxPingPongChannelMetaBundle outputMetaBundle = replicate(tagged Invalid);

        if (curMetaMaybeReg matches tagged Valid .curMeta) begin
            let                 prevBeatSegOverflowCnt  = prevBeatSegOverflowCntReg;
            FtileMacSegmentCnt  curBeatUsedSegCnt       = zeroExtend(prevBeatSegOverflowCnt);

            let onePacketMetaAvailable      = True;
            let twoPacketMetaAvailable      = selectedInputChannelMetaMIMO.deqReadyN(1);
            let threePacketMetaAvailable    = selectedInputChannelMetaMIMO.deqReadyN(2);

            let packetOneMeta   = curMeta;
            let packetTwoMeta   = selectedInputChannelMetaMIMO.first[0];
            let packetThreeMeta = selectedInputChannelMetaMIMO.first[1];

            // I don't want to define a new type, but I need to make sure that the add will not overflow. So we pre-allocate three signal will bigger size.
            Bit#(TAdd#(2, SizeOf#(FtileMacTxChannelBufferSegCnt))) zeroPacketSegCnt   = zeroExtend(curBeatUsedSegCnt);
            Bit#(TAdd#(2, SizeOf#(FtileMacTxChannelBufferSegCnt))) onePacketSegCnt    = zeroExtend(packetOneMeta.segCnt) + zeroExtend(curBeatUsedSegCnt);
            Bit#(TAdd#(2, SizeOf#(FtileMacTxChannelBufferSegCnt))) twoPacketSegCnt    = zeroExtend(packetOneMeta.segCnt) + zeroExtend(packetTwoMeta.segCnt) + zeroExtend(curBeatUsedSegCnt);
            Bit#(TAdd#(2, SizeOf#(FtileMacTxChannelBufferSegCnt))) threePacketSegCnt  = zeroExtend(packetOneMeta.segCnt) + zeroExtend(packetTwoMeta.segCnt) + zeroExtend(packetThreeMeta.segCnt) + zeroExtend(curBeatUsedSegCnt);

            let beatWillHoldOnePacket   = onePacketMetaAvailable;
            let beatWillHoldTwoPacket   = twoPacketMetaAvailable   && onePacketSegCnt < fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT));
            let beatWillHoldThreePacket = threePacketMetaAvailable && twoPacketSegCnt < fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT));

            FtileMacSegmentCnt segLeftForPacketOne     = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)) - zeroPacketSegCnt);
            FtileMacSegmentCnt segLeftForPacketTwo     = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)) - onePacketSegCnt);
            FtileMacSegmentCnt segLeftForPacketThree   = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)) - twoPacketSegCnt);
            FtileMacSegmentIdx zeroBasedSegLeftForPacketOne     = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)) - zeroPacketSegCnt - 1);
            FtileMacSegmentIdx zeroBasedSegLeftForPacketTwo     = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)) - onePacketSegCnt - 1);
            FtileMacSegmentIdx zeroBasedSegLeftForPacketThree   = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)) - twoPacketSegCnt - 1);

            FtileMacTxChannelBufferSegCnt segLeftToCheckIfPacketOneWillEndInThisBeat   = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT) + valueOf(FTILE_MAC_TX_MAX_OVERFLOW_SEG_CNT_PER_BEAT)) - zeroPacketSegCnt);
            FtileMacTxChannelBufferSegCnt segLeftToCheckIfPacketTwoWillEndInThisBeat   = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT) + valueOf(FTILE_MAC_TX_MAX_OVERFLOW_SEG_CNT_PER_BEAT)) - onePacketSegCnt);
            FtileMacTxChannelBufferSegCnt segLeftToCheckIfPacketThreeWillEndInThisBeat = truncate(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT) + valueOf(FTILE_MAC_TX_MAX_OVERFLOW_SEG_CNT_PER_BEAT)) - twoPacketSegCnt);

            let packetOneWillEndInThisBeat   = packetOneMeta.segCnt     <= segLeftToCheckIfPacketOneWillEndInThisBeat;
            let packetTwoWillEndInThisBeat   = packetTwoMeta.segCnt     <= segLeftToCheckIfPacketTwoWillEndInThisBeat;
            let packetThreeWillEndInThisBeat = packetThreeMeta.segCnt   <= segLeftToCheckIfPacketThreeWillEndInThisBeat;

            if (beatWillHoldThreePacket) begin
                outputMetaBundle[0] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetOneMeta.segCnt-1),
                    eopEmpty        : packetOneMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : True
                    // isOutputBeatLast: 
                };
                outputMetaBundle[1] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetTwoMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetTwoMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetTwoMeta.segCnt-1),
                    eopEmpty        : packetTwoMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : True
                    // isOutputBeatLast: 
                };
                outputMetaBundle[2] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetThreeMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetThreeMeta.startSegAddr),
                    zeroBasedSegCnt : packetThreeWillEndInThisBeat ? truncate(packetThreeMeta.segCnt-1) : zeroBasedSegLeftForPacketThree,
                    eopEmpty        : packetThreeMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : packetThreeWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                selectedInputChannelMetaMIMO.deq(2);

                if (packetThreeWillEndInThisBeat) begin
                    curMetaMaybeReg <= tagged Invalid;
                    immFail("should not reach here, each packet is at least 64 Byte, 3 packet can't end in single 128 Byte", $format(""));
                end
                else begin
                    let nextCurMeta = packetThreeMeta;
                    nextCurMeta.segCnt = nextCurMeta.segCnt - zeroExtend(roundUpUsedSegCount(segLeftForPacketThree));
                    curMetaMaybeReg <= tagged Valid nextCurMeta;
                    prevBeatSegOverflowCnt = truncate(packetOneMeta.segCnt + packetTwoMeta.segCnt + zeroExtend(roundUpUsedSegCount(segLeftForPacketThree)) - fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)));
                end
            end
            else if (beatWillHoldTwoPacket) begin
                outputMetaBundle[0] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetOneMeta.segCnt-1),
                    eopEmpty        : packetOneMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : True
                    // isOutputBeatLast: 
                };
                outputMetaBundle[1] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetTwoMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetTwoMeta.startSegAddr),
                    zeroBasedSegCnt : packetTwoWillEndInThisBeat ? truncate(packetTwoMeta.segCnt-1) : zeroBasedSegLeftForPacketTwo,
                    eopEmpty        : packetTwoMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : packetTwoWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                selectedInputChannelMetaMIMO.deq(1);

                if (packetTwoWillEndInThisBeat) begin
                    curMetaMaybeReg <= tagged Invalid;
                end
                else begin
                    let nextCurMeta = packetTwoMeta;
                    nextCurMeta.segCnt = nextCurMeta.segCnt - zeroExtend(roundUpUsedSegCount(segLeftForPacketTwo));
                    curMetaMaybeReg <= tagged Valid nextCurMeta;
                    prevBeatSegOverflowCnt = truncate(packetOneMeta.segCnt + zeroExtend(roundUpUsedSegCount(segLeftForPacketTwo)) - fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)));
                end
            end
            else if (beatWillHoldOnePacket) begin
                outputMetaBundle[0] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : packetOneWillEndInThisBeat ? truncate(packetOneMeta.segCnt - 1) : fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT))-1,
                    eopEmpty        : packetOneMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : packetOneWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                if (packetOneWillEndInThisBeat) begin
                    curMetaMaybeReg <= tagged Invalid;
                end
                else begin
                    let nextCurMeta = packetOneMeta;
                    nextCurMeta.segCnt = nextCurMeta.segCnt - fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT));
                    curMetaMaybeReg <= tagged Valid nextCurMeta;
                    prevBeatSegOverflowCnt = prevBeatSegOverflowCnt;  // in this case, full beat, overflow cnt will not change
                end
            end
            pingpongChannelMetaPipeOutQueueVec[curOutputRoundRobinIdxReg].enq(outputMetaBundle);
            curOutputRoundRobinIdxReg <= curOutputRoundRobinIdxReg + 1;
            prevBeatSegOverflowCntReg <= prevBeatSegOverflowCnt;
        end
        else begin
            if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                selectedInputChannelMetaMIMO.deq(1);
                prevBeatSegOverflowCntReg <= 0;
            end 
        end
    endrule

    interface packetMetaPipeInVec = packetMetaPipeInVecInst;
    interface pingpongChannelMetaPipeOutVec = pingpongChannelMetaPipeOutVecInst;
endmodule


typedef 512 FTILE_MAC_TX_BRAM_BUFFER_DEPTH;
typedef TLog#(FTILE_MAC_TX_BRAM_BUFFER_DEPTH) FTILE_MAC_TX_BRAM_BUFFER_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_TX_BRAM_BUFFER_ADDR_WIDTH) FtileMacTxBramBufferAddr;

// typedef TAdd#(FTILE_MAC_SEGMENT_CNT, TSub#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT, 1)) FTILE_MAC_RX_PING_PONG_CHANNEL_BUF_WITH_ADDITIONAL_TAIL_SEG_CNT;
// typedef Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_BUF_WITH_ADDITIONAL_TAIL_SEG_CNT, FtileMacDataSegment)  FtileMacRxPingPongChannelWithTailSegDataBundle;
// typedef Bit#(FTILE_MAC_RX_PING_PONG_CHANNEL_BUF_WITH_ADDITIONAL_TAIL_SEG_CNT) FtileMacRxPingPongChannelWithTailSegInframeSignalBundle;

typedef struct {
    FtileMacTxBramBufferAddr addr;
    DATA                     data;
} FtileMacTxBramBufferWriteReq deriving (FShow, Bits);

typedef struct {
    FtileMacTxBramBufferAddr addr;
} FtileMacTxBramBufferReadReq deriving (FShow, Bits);

typedef struct {
    FtileMacUserLogicChannelIdx         srcChannelIdx;
    FtileMacTxChannelBufferRowSegIdx    zeroBasedValidSegCnt;
    Bool                                isLast;
    Bool                                isOutputBeatLast;
} FtileMacTxPingPongChannelBramReadPipelineEntry deriving (FShow, Bits);


typedef struct {
    FtileMacDataBusSegBundle            dataBuf;
    SegmentInframeSignalBundle          inFrameSignal;
    FtileMacSegmentIdx                  finalSegShiftOffset;
    FtileMacTxChannelBufferRowSegIdx    overflowSegCnt;
} FtileMacTxPingPongChannelOutputEntry deriving (FShow, Bits);

interface FtileMacTxPingPongSingleChannel;
    interface PipeIn#(FtileMacTxPingPongChannelMetaBundle)  metaPipeIn;

    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacTxBramBufferReadReq))  bramReadReqPipeOutVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(DATA))  bramReadRespPipeInVec;
    
    // interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(FtileMacRxBramBufferWriteReq))   txBramWriteReqPipeInVec;
endinterface

(* synthesize *)
module mkFtileMacTxPingPongSingleChannel(FtileMacTxPingPongSingleChannel);
    FIFOF#(FtileMacTxPingPongChannelMetaBundle)  metaPipeInQueue <- mkFIFOF;

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacTxBramBufferReadReq))  bramReadReqPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacTxBramBufferReadReq))    bramReadReqPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(DATA))   bramReadRespPipeInVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(DATA))    bramReadRespPipeInQueueVec <- replicateM(mkFIFOF);

    for (Integer idx=0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        bramReadReqPipeOutVecInst[idx] = toPipeOut(bramReadReqPipeOutQueueVec[idx]);
        bramReadRespPipeInVecInst[idx] = toPipeIn(bramReadRespPipeInQueueVec[idx]);
    end

    // Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(FtileMacRxBramBufferWriteReq))   txBramWriteReqPipeInVecInst = newVector;
    // Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacRxBramBufferWriteReq))    txBramWriteReqPipeInQueueVec <- replicateM(mkFIFOF);
    // for (Integer idx=0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
    //     txBramWriteReqPipeInVecInst[idx] = toPipeIn(txBramWriteReqPipeInQueueVec[idx]);
    // end


    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, AutoInferBramQueuedOutput#(FtileMacTxBramBufferAddr, DATA))  dataStreamStorageVec  <- replicateM(mkAutoInferBramQueuedOutput(False, ""));
    
    Reg#(Maybe#(FtileMacTxPingPongChannelMetaEntry)) curMetaEntryMaybeReg <- mkReg(tagged Invalid);
    Reg#(FtileMacTxPingPongChannelMetaBundle) curInputMetaBundleReg <- mkRegU;

    Reg#(FtileMacSegmentCnt) outputBeatEmptySegCntReg <- mkReg(fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT)));


    Reg#(FtileMacTxPingPongChannelOutputEntry) outputEntryReg <- mkReg(unpack(0));

    // Pipeline FIFOs
    FIFOF#(FtileMacTxPingPongChannelBramReadPipelineEntry) bramReadPipelineQueue <- mkSizedFIFOF(8);
    FIFOF#(FtileMacTxPingPongChannelOutputEntry)           finalShiftPipelineQ <- mkFIFOF;

    rule sendBramReadReq;
        let zeroBasedValidSegCnt = ?;

        if (curMetaEntryMaybeReg matches tagged Valid .curMetaEntry) begin
            let metaBundle = metaPipeInQueue.first;

            let isLast = curMetaEntry.zeroBasedSegCnt <= fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)-1);
            let haveNextValidPacketMeta = isValid(curInputMetaBundleReg[0]);
            let isOutputBeatLast = isLast && !haveNextValidPacketMeta;

            if (!isLast) begin
                zeroBasedValidSegCnt = fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)-1);
            end
            else begin
                zeroBasedValidSegCnt = truncate(curMetaEntry.zeroBasedSegCnt);
            end

            bramReadReqPipeOutQueueVec[curMetaEntry.srcChannelIdx].enq(FtileMacTxBramBufferReadReq{addr: curMetaEntry.startRowAddr});
            bramReadPipelineQueue.enq(FtileMacTxPingPongChannelBramReadPipelineEntry {
                srcChannelIdx: curMetaEntry.srcChannelIdx,
                zeroBasedValidSegCnt: zeroBasedValidSegCnt,
                isLast: isLast,
                isOutputBeatLast: isOutputBeatLast
            });

            let nextCurMetaEntryMaybe;
            if (!isLast) begin
                let nextCurMetaEntry = curMetaEntry;
                nextCurMetaEntry.zeroBasedSegCnt = nextCurMetaEntry.zeroBasedSegCnt - fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT));
                nextCurMetaEntry.startRowAddr = nextCurMetaEntry.startRowAddr + 1;
                nextCurMetaEntryMaybe = tagged Valid nextCurMetaEntry;
            end
            else begin
                if (haveNextValidPacketMeta) begin
                    curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, curInputMetaBundleReg, 1);
                    nextCurMetaEntryMaybe = curInputMetaBundleReg[0];
                end
                else begin
                    if (metaPipeInQueue.notEmpty) begin
                        curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, metaPipeInQueue.first, 1);
                        nextCurMetaEntryMaybe = metaPipeInQueue.first[0];
                        metaPipeInQueue.deq;
                    end
                    else begin
                        nextCurMetaEntryMaybe = tagged Invalid;
                    end
                end
            end
            curMetaEntryMaybeReg <= nextCurMetaEntryMaybe;
        end
        else begin
            curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, metaPipeInQueue.first, 1);
            curMetaEntryMaybeReg <= metaPipeInQueue.first[0];
            metaPipeInQueue.deq;
        end
    endrule


    rule handleBramReadResp;
        let bramReadBeatMeta = bramReadPipelineQueue.first;
        bramReadPipelineQueue.deq;

        let readResp = bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].first;
        bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].deq;

        let outputEntry             = outputEntryReg;
        let outputBeatEmptySegCnt   = outputBeatEmptySegCntReg;

        Vector#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT, FtileMacDataSegment) readRespAsSegBundle = unpack(readResp);
        case (bramReadBeatMeta.zeroBasedValidSegCnt)
            0: begin
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);

                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 1'b0: 1'b1, truncateLSB(outputEntry.inFrameSignal)};
            end
            1: begin
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[1]);

                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 2'b01: 2'b11, truncateLSB(outputEntry.inFrameSignal)};
            end
            2: begin
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[1]);
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[2]);

                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 3'b011: 3'b111, truncateLSB(outputEntry.inFrameSignal)};
            end
            3: begin
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[1]);
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[2]);
                outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[3]);

                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 4'b0111: 4'b1111, truncateLSB(outputEntry.inFrameSignal)};
            end
        endcase

        outputBeatEmptySegCnt = outputBeatEmptySegCnt - zeroExtend(bramReadBeatMeta.zeroBasedValidSegCnt) - 1;

        outputEntryReg <= outputEntry;
        if (bramReadBeatMeta.isOutputBeatLast) begin
            outputEntry.finalSegShiftOffset = truncate(outputBeatEmptySegCnt);
            finalShiftPipelineQ.enq(outputEntry);
            outputBeatEmptySegCntReg <= fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT));
        end
        else begin
            outputBeatEmptySegCntReg <= outputBeatEmptySegCnt;
        end
    endrule

    rule finalShift;
        let outputEntry = finalShiftPipelineQ.first;
        finalShiftPipelineQ.deq;
        outputEntry.dataBuf = shiftOutFrom0(?, outputEntry.dataBuf, outputEntry.finalSegShiftOffset);

    endrule

    interface metaPipeIn = toPipeIn(metaPipeInQueue);
    interface bramReadReqPipeOutVec = bramReadReqPipeOutVecInst;
    interface bramReadRespPipeInVec = bramReadRespPipeInVecInst;

    // interface txBramWriteReqPipeInVec   = txBramWriteReqPipeInVecInst;
endmodule




// interface FtileMacTxPayloadStorageAndGearBox;
//     interface PipeOut#(FtileMacDataBusSegBundle)        txDataBusSegBundlePipeOut;
//     // interface PipeOut#(FtileMacTxPacketChunkMeta)       packetChunkMetaPipeOut;
//     interface PipeIn#(FtileMacTxUserStream)             streamPipeIn;
// endinterface


// (* synthesize *)
// module mkFtileMacTxPayloadStorageAndGearBox(FtileMacTxPayloadStorageAndGearBox);

// endmodule


interface FTileMac;
    interface PipeIn#(FtileMacRxBeat) ftilemacRxPipeIn;
    // interface PipeOut#(FtileMacTxBeat) ftilemacTxPipeOut;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxUserStream))  ftilemacRxStreamPipeOutVec;
endinterface


(* synthesize *)
module mkFTileMac(FTileMac);
    // FIFOF#(FtileMacRxBeat) ftilemacRxPipeInQueue    <- mkFIFOF;
    // FIFOF#(FtileMacTxBeat) ftilemacTxPipeOutQueue   <- mkFIFOF;

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxUserStream))  ftilemacRxStreamPipeOutVecInst = newVector;

    let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 
    let ftileMacRxBeatJoin <- mkFtileMacRxPingPongChannelMetaJoin;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacRxPayloadStorageAndGearBox) storageAndGearBoxVec <- replicateM(mkFtileMacRxPayloadStorageAndGearBox);


    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);
        mkConnection(pingPongChannelVec[idx].packetsChunkMetaPipeOut, ftileMacRxBeatJoin.metaPipeInVec[idx]);
    end

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx], storageAndGearBoxVec[idx].packetChunkMetaPipeIn);
        ftilemacRxStreamPipeOutVecInst[idx] = storageAndGearBoxVec[idx].streamPipeOut;
    end

    rule forwardBramWriteReq;
        for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
           storageAndGearBoxVec[idx].rxBramWriteReqPipeIn.enq(ftileMacRxBeatFork.rxBramWriteReqPipeOut.first);
        end
        ftileMacRxBeatFork.rxBramWriteReqPipeOut.deq;
    endrule
    


    interface ftilemacRxPipeIn              = ftileMacRxBeatFork.rxBetaPipeIn;
    // interface ftilemacTxPipeOut             = toPipeOut(ftilemacTxPipeOutQueue);
    interface ftilemacRxStreamPipeOutVec    = ftilemacRxStreamPipeOutVecInst;
endmodule



