// TopFTileMacAdaptorTest.bsv
// Stress test top-level for FTileMacAdaptor.
//
// Instantiates FTileMacAdaptor + FTileMac (the real 4-channel 400G MAC
// wrapper), then attaches four independent packet-generator modules – one per
// TX channel – that continuously inject back-to-back Ethernet frames.
// The RX loopback path is connected to four packet-sink modules that drain
// whatever the MAC delivers.
//
// RTile PCIe is stubbed out with fake inline interfaces (tie-off).
//
// The design is fully synthesisable.

import Connectable  :: *;
import FIFOF        :: *;
import Vector       :: *;
import Clocks       :: *;
import GetPut       :: *;

import Settings         :: *;
import BasicDataTypes    :: *;
import PrimUtils         :: *;
import ConnectableF      :: *;
import DtldStream       :: *;
import RTilePcieAdaptor :: *;
import FTileMacAdaptor  :: *;

import Utils4Test :: *;


// ---------------------------------------------------------------------------
// Top-level interface
// (Same as Top.bsv so the synthesised module can share the same wrapper.)
// ---------------------------------------------------------------------------
interface BsvTop;
    method Bit#(16) getKeepSignal;

    (* always_ready, always_enabled *)
    method Action trigger_transfer(Bit#(4) val);

    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rtilePcieAdaptorRxRawIfc;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx rtilePcieAdaptorTxRawIfc;

    (* always_ready, always_enabled *)
    interface FTileMacAdaptorRx ftileMacAdaptorRxRawIfc;
    (* always_ready, always_enabled *)
    interface FTileMacAdaptorTx ftileMacAdaptorTxRawIfc;
    
endinterface


// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

// Number of 256-bit beats per generated packet.
// 8 beats × 32 bytes = 256-byte payload.
typedef 4 TEST_PACKET_BEATS;

// Derived width of the beat-index field inside the payload word.
// TLog#(8) = 3 bits.
typedef TLog#(TEST_PACKET_BEATS) TEST_BEAT_IDX_WIDTH;


// ---------------------------------------------------------------------------
// mkPktGen
// One-channel TX packet generator.
// Produces an infinite, back-to-back stream of packets.
//
// 256-bit payload layout:
//   [255:254]  channelId  (2 bits)
//   [253:251]  beat index (3 bits, TLog#(TEST_PACKET_BEATS))
//   [250: 32]  zeros      (219 bits)
//   [ 31:  0]  packet sequence number (32 bits)
// ---------------------------------------------------------------------------
interface PktGen;
    method Action trigger(Bit#(4) val);
    interface PipeOut#(FtileMacTxUserStream) pipeOut;
endinterface

(* synthesize *)
module mkPktGen#(Bit#(2) channelId)(PktGen);
    FIFOF#(FtileMacTxUserStream) outQ <- mkFIFOF;

    Reg#(Bit#(TEST_BEAT_IDX_WIDTH)) beatIdxReg <- mkReg(0);
    Reg#(Bit#(32))                  seqNumReg  <- mkReg(0);

    Bit#(TEST_BEAT_IDX_WIDTH) maxBeatIdx;

    if (channelId <=1) begin
        maxBeatIdx = fromInteger(2 - 1);
    end
    else begin
        maxBeatIdx = fromInteger(3 - 1);
    end

    Reg#(Bool) runningReg <- mkReg(False);



    rule produce (outQ.notFull && runningReg);
        Bool isFirst = (beatIdxReg == 0);
        Bool isLast  = (beatIdxReg == maxBeatIdx);


        DATA payload = {32'heeeeeeee, 32'hdddddddd, 32'hcccccccc, 30'b0, channelId, 32'hbbbbbbbb, 30'b0, beatIdxReg, 32'haaaaaaaa, seqNumReg};

        // byteNum field width = TAdd#(1, TLog#(DATA_BUS_BYTE_WIDTH)) = 6 bits
        // DATA_BUS_BYTE_WIDTH = 32; full beat carries 32 bytes.
        FtileMacTxUserStream beat = DtldStreamData {
            data        : payload,
            byteNum     : fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)),
            startByteIdx: 0,
            isFirst     : isFirst,
            isLast      : isLast
        };

        outQ.enq(beat);

        if (isLast) begin
            beatIdxReg <= 0;
            seqNumReg  <= seqNumReg + 1;
        end
        else begin
            beatIdxReg <= beatIdxReg + 1;
        end
    endrule

    method Action trigger(Bit#(4) val);
        // runningReg <= val;
    endmethod

    interface pipeOut = toPipeOut(outQ);
endmodule


// ---------------------------------------------------------------------------
// mkPktSink
// One-channel RX packet sink – simply drains all arriving beats.
// ---------------------------------------------------------------------------
interface PktSink;
    interface PipeInB0#(FtileMacRxUserStream) pipeIn;
    method Bit#(16) getKeepSignal;
endinterface

(* synthesize *)
module mkPktSink(PktSink);
    PipeInAdapterB0#(FtileMacRxUserStream) inQ <- mkPipeInAdapterB0;

    ForceKeepWideSignals#(FtileMacRxUserStream, Bit#(16)) signalKeeper1 <- mkForceKeepWideSignals; 

    rule drain;
        inQ.deq;
        signalKeeper1.bitsPipeIn.enq(inQ.first);
    endrule

    method getKeepSignal = signalKeeper1.out;
    interface pipeIn = toPipeInB0(inQ);
endmodule


// ---------------------------------------------------------------------------
// mkBsvTopOnlyHardIp
// Encapsulates both hard-IP adaptors and the FTile CDC crossing FIFOs.
// Exposes the user-facing stream vectors for easy top-level connection.
// ---------------------------------------------------------------------------
interface BsvTopOnlyHardIp;
    (* always_ready, always_enabled *)
    interface FTileMacAdaptorRx ftileMacAdaptorRxRawIfc;
    (* always_ready, always_enabled *)
    interface FTileMacAdaptorTx ftileMacAdaptorTxRawIfc;

    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT,
                      PipeInB0#(FtileMacTxUserStream))  ftilemacTxStreamPipeInVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT,
                      PipeOut#(FtileMacRxUserStream))   ftilemacRxStreamPipeOutVec;

    method Action trigger(Bit#(4) val);
endinterface

(* synthesize *)
module mkBsvTopOnlyHardIp#(
        Clock ftileClk,
        Reset ftileRst
    )(BsvTopOnlyHardIp);

    // FTile MAC adaptor (runs in ftileClk domain)
    FTileMacAdaptor ftileMacAdaptor <-
        mkFTileMacAdaptor(clocked_by ftileClk, reset_by ftileRst);

    // FTile MAC user-logic block (runs in core clock domain)
    FTileMac ftileMac <- mkFTileMac;

    // ---- Clock-domain crossing (FTile ↔ core) ----------------------------
    SyncFIFOIfc#(FtileMacRxBeat) ftileRxSyncQ <-
        mkSyncFIFOToCC(valueOf(NUMERIC_TYPE_FOUR), ftileClk, ftileRst);
    SyncFIFOIfc#(FtileMacTxBeat) ftileTxSyncQ <-
        mkSyncFIFOFromCC(valueOf(NUMERIC_TYPE_FOUR), ftileClk);

    // RX path: adaptor → CDC FIFO → FTileMac
    mkConnection(ftileMacAdaptor.ftilemacRxPipeOut,
                 toPipeInSync(ftileRxSyncQ));
    // mkConnection(toPipeOutSync(ftileRxSyncQ),
    //              ftileMac.ftilemacRxPipeIn);

    // TX path: FTileMac → CDC FIFO → adaptor
    // mkConnection(toPipeInSync(ftileTxSyncQ),
    //              ftileMac.ftilemacTxPipeOut);
    mkConnection(ftileMacAdaptor.ftilemacTxPipeIn,
                 toPipeOutSync(ftileTxSyncQ));

    Reg#(Bool) isBusyReg <- mkReg(True);

    Reg#(Bit#(4)) curModeReg <- mkReg(0);
    Reg#(Bit#(20)) triggerCounterReg <- mkReg(0);    

    
    // 连续发送满拍的
    rule genBeatForTx1 if (curModeReg == 1);
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7FFF;
        ftileTxSyncQ.enq(beat);
    endrule

    // 满拍发送，但隔一拍会有一个inframe全0的情况
    rule genBeatForTx2 if (curModeReg == 2);
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7FFF;
        isBusyReg <= !isBusyReg;
        if (isBusyReg) begin
            beat.inframe = 16'h0000;
        end
        ftileTxSyncQ.enq(beat);
    endrule

    // 满拍发送，但隔一拍发一次
    rule genBeatForTx3 if (curModeReg == 3);
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7FFF;
        isBusyReg <= !isBusyReg;
        if (isBusyReg) begin
            ftileTxSyncQ.enq(beat);
        end
        
    endrule

    // inframe首尾均为0，连续发送
    rule genBeatForTx4 if (curModeReg == 4);
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7FFE;
        ftileTxSyncQ.enq(beat);
    endrule

    // 一拍里两个包
    rule genBeatForTx5 if (curModeReg == 5);
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7F7F;
        ftileTxSyncQ.enq(beat);
    endrule

    // 满拍发包，但时间间隔很长
    rule genBeatForTx6 if (curModeReg == 6);
        triggerCounterReg <= triggerCounterReg + 1;
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7FFF;
        if (triggerCounterReg == 0) begin
            ftileTxSyncQ.enq(beat);
        end
    endrule

    // 满拍发包，但时间间隔很长，且ethernet frame包含0800的IPv4类型
    rule genBeatForTx7 if (curModeReg == 7);
        triggerCounterReg <= triggerCounterReg + 1;
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEAD0008, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h7FFF;
        if (triggerCounterReg == 0) begin
            ftileTxSyncQ.enq(beat);
        end
    endrule

        // 发小包，但时间间隔很长，且ethernet frame包含0800的IPv4类型
    rule genBeatForTx8 if (curModeReg == 8);
        triggerCounterReg <= triggerCounterReg + 1;
        let beat = FtileMacTxBeat {
            data: unpack(0),
            inframe: unpack(0),
            eop_empty: unpack(0),
            error: unpack(0),
            skip_crc: unpack(0)
        };

        beat.data = unpack({
            32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333, 32'hDEADC0DE, 32'h33333333,
            32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222, 32'hDEADC0DE, 32'h22222222,
            32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111, 32'hDEADC0DE, 32'h11111111,
            32'hDEADC0DE, 32'h00000000, 32'hDEADC0DE, 32'h00000000, 32'hDEAD0008, 32'h00000000, 32'hDEADC0DE, 32'h00000000
        });

        beat.inframe = 16'h07FF;
        if (triggerCounterReg == 0) begin
            ftileTxSyncQ.enq(beat);
        end
    endrule

    method Action trigger(Bit#(4) val);
        curModeReg <= val;
    endmethod

    interface ftileMacAdaptorRxRawIfc    = ftileMacAdaptor.rx;
    interface ftileMacAdaptorTxRawIfc    = ftileMacAdaptor.tx;
    interface ftilemacTxStreamPipeInVec  = ftileMac.ftilemacTxStreamPipeInVec;
    interface ftilemacRxStreamPipeOutVec = ftileMac.ftilemacRxStreamPipeOutVec;
endmodule


// ---------------------------------------------------------------------------
// mkBsvTop – stress-test top
// ---------------------------------------------------------------------------
module mkBsvTop#(
        Clock ftileClk,
        Reset ftileRst
    )(BsvTop);

    BsvTopOnlyHardIp hardIp <- mkBsvTopOnlyHardIp(ftileClk, ftileRst);

    // ---- Packet generators – instantiated with per-channel ID ------------
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PktGen)  pktGenVec  = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PktSink) pktSinkVec = newVector;

    for (Integer i = 0; i < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); i = i + 1) begin
        pktGenVec[i]  <- mkPktGen(fromInteger(i));
        pktSinkVec[i] <- mkPktSink;
    end

    // ---- Connect all four channels concurrently --------------------------
    for (Integer i = 0; i < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); i = i + 1) begin
        // Generator → TX input of FTileMac
        mkConnection(pktGenVec[i].pipeOut,
                     hardIp.ftilemacTxStreamPipeInVec[i]);
        // RX output of FTileMac → Sink
        mkConnection(hardIp.ftilemacRxStreamPipeOutVec[i],
                     pktSinkVec[i].pipeIn);
    end


    method Action trigger_transfer(Bit#(4) val);
        hardIp.trigger(val);
    endmethod

    method getKeepSignal = pktSinkVec[0].getKeepSignal ^ pktSinkVec[1].getKeepSignal ^ pktSinkVec[2].getKeepSignal ^ pktSinkVec[3].getKeepSignal;
    // ---- Fake RTile PCIe raw interfaces (tie-off, no PCIe in this test) -----
    // RX: accept all inputs, report ready=True, output credit signals all-zero.
    interface RTilePcieAdaptorRx rtilePcieAdaptorRxRawIfc;
        method Action setRxInputData(
            PcieTlpDataBusSegBundle         data,
            PcieTlpHeaderBusSegBundle       hdr,
            SopSignalBundle                 sop,
            EopSignalBundle                 eop,
            HvalidSignalBundle              hvalid,
            DvalidSignalBundle              dvalid,
            BarIdSignalBundle               bar,
            SegmentEmptySignalBundle        empty,
            HeaderCreditInitAckSignalBundle hcrdt_init_ack,
            DataCreditInitAckSignalBundle   dcrdt_init_ack
        );
            noAction;
        endmethod
        method Bool ready = True;
        method HeaderCreditInitSignalBundle hcrdt_init =
            HeaderCreditInitSignalBundle { cplh: False, nph: False, ph: False };
        method HeaderCreditUpdateSignalBundle hcrdt_update =
            HeaderCreditUpdateSignalBundle { cplh: False, nph: False, ph: False };
        method HeaderCreditUpdateCntSignalBundle hcrdt_update_cnt =
            HeaderCreditUpdateCntSignalBundle { cplh: 0, nph: 0, ph: 0 };
        method DataCreditInitSignalBundle dcrdt_init =
            DataCreditInitSignalBundle { cpld: False, npd: False, pd: False };
        method DataCreditUpdateSignalBundle dcrdt_update =
            DataCreditUpdateSignalBundle { cpld: False, npd: False, pd: False };
        method DataCreditUpdateCntSignalBundle dcrdt_update_cnt =
            DataCreditUpdateCntSignalBundle { cpld: 0, npd: 0, pd: 0 };
    endinterface

    // TX: accept credit inputs, output valid=False and data/hdr all-zero.
    interface RTilePcieAdaptorTx rtilePcieAdaptorTxRawIfc;
        method Action setTxInputData(
            HeaderCreditInitSignalBundle        hcrdt_init,
            HeaderCreditUpdateSignalBundle      hcrdt_update,
            HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt,
            DataCreditInitSignalBundle          dcrdt_init,
            DataCreditUpdateSignalBundle        dcrdt_update,
            DataCreditUpdateCntSignalBundle     dcrdt_update_cnt,
            Bool                                ready
        );
            noAction;
        endmethod
        method HeaderCreditInitAckSignalBundle hcrdt_init_ack =
            HeaderCreditInitAckSignalBundle { cplh: False, nph: False, ph: False };
        method DataCreditInitAckSignalBundle dcrdt_init_ack =
            DataCreditInitAckSignalBundle { cplh: False, nph: False, ph: False };
        method PcieTlpHeaderBusSegBundle    hdr      = unpack(0);
        method PcieTlpDataBusSegBundle      data     = unpack(0);
        method SopSignalBundle              sop      = 0;
        method EopSignalBundle              eop      = 0;
        method HvalidSignalBundle           hvalid   = 0;
        method DvalidSignalBundle           dvalid   = 0;
    endinterface

    interface ftileMacAdaptorRxRawIfc   = hardIp.ftileMacAdaptorRxRawIfc;
    interface ftileMacAdaptorTxRawIfc   = hardIp.ftileMacAdaptorTxRawIfc;

endmodule





module mkBsvTopTB(Empty);
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset; 
    let dut <- mkBsvTop(clk, rst);

    rule forward1;
        dut.ftileMacAdaptorRxRawIfc.setRxInputData(
            dut.ftileMacAdaptorTxRawIfc.data,
            dut.ftileMacAdaptorTxRawIfc.valid,
            dut.ftileMacAdaptorTxRawIfc.inframe,
            dut.ftileMacAdaptorTxRawIfc.eop_empty,
            unpack(0),
            unpack(0),
            unpack(0)
        );
    endrule
    
    
    rule forward2;
        dut.ftileMacAdaptorTxRawIfc.setTxInputData(
                dut.ftileMacAdaptorRxRawIfc.ready
            );
    endrule
endmodule