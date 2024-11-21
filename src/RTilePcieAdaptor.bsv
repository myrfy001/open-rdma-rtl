import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import PcieTypes :: *;
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

`include "PcieMacros.bsv"

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} HeaderCreditInitSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} HeaderCreditInitAckSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} HeaderCreditUpdateSignalBundle deriving(Bits, FShow, Eq);

typedef 2 HEADER_CREDIT_UPDATE_CNT_WIDTH;
typedef Bit#(HEADER_CREDIT_UPDATE_CNT_WIDTH) HeaderCreditUpdateCnt;

typedef struct {
    HeaderCreditUpdateCnt cplh;
    HeaderCreditUpdateCnt nph;
    HeaderCreditUpdateCnt ph;
} HeaderCreditUpdateCntSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cpld;
    Bool npd;
    Bool pd;
} DataCreditInitSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} DataCreditInitAckSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cpld;
    Bool npd;
    Bool pd;
} DataCreditUpdateSignalBundle deriving(Bits, FShow, Eq);

typedef 4 DATA_CREDIT_UPDATE_CNT_WIDTH;
typedef Bit#(DATA_CREDIT_UPDATE_CNT_WIDTH) DataCreditUpdateCnt;

typedef struct {
    DataCreditUpdateCnt cpld;
    DataCreditUpdateCnt npd;
    DataCreditUpdateCnt pd;
} DataCreditUpdateCntSignalBundle deriving(Bits, FShow, Eq);

typedef 4 PCIE_SEGMENT_CNT;
typedef TLog#(PCIE_SEGMENT_CNT) PCIE_SEGMENT_IDX_WIDTH;
typedef Bit#(PCIE_SEGMENT_IDX_WIDTH) PcieSegmentIdx;


typedef Bit#(PCIE_SEGMENT_CNT) SegmentSopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) SegmentEopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) SegmentDvalidSignalBundle;

typedef 3 PCIE_RX_EMPTY_WIDTH;
typedef Bit#(PCIE_RX_EMPTY_WIDTH) PcieRxEmpty;
typedef Vector#(PCIE_SEGMENT_CNT, PcieRxEmpty) SegmentEmptySignalBundle;

typedef 3 PCIE_BAR_ID_WIDTH;
typedef Bit#(PCIE_BAR_ID_WIDTH) PcieBarId;
typedef Vector#(PCIE_SEGMENT_CNT, PcieBarId) BarIdSignalBundle;

typedef 512 PCIE_TLP_HEADER_BUNDLE_WIDTH;
typedef TDiv#(PCIE_TLP_HEADER_BUNDLE_WIDTH, PCIE_SEGMENT_CNT) PCIE_TLP_HEADER_BUFFER_WIDTH;
typedef Bit#(PCIE_TLP_HEADER_BUFFER_WIDTH) PcieTlpHeaderBuffer;
typedef Vector#(PCIE_SEGMENT_CNT, PcieTlpHeaderBuffer) PcieTlpHeaderBusSegBundle;

typedef 1024 PCIE_TLP_DATA_BUNDLE_WIDTH;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, PCIE_SEGMENT_CNT) PCIE_TLP_DATA_SEGMENT_WIDTH;    // 256
typedef TDiv#(PCIE_TLP_DATA_SEGMENT_WIDTH, BYTE_WIDTH) PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH;    // 32
typedef Bit#(PCIE_TLP_DATA_SEGMENT_WIDTH) PcieTlpDataSegment;
typedef Vector#(PCIE_SEGMENT_CNT, PcieTlpDataSegment) PcieTlpDataBusSegBundle;

typedef Bit#(PCIE_SEGMENT_CNT) SopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) EopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) HvalidSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) DvalidSignalBundle;

typedef 12 CREDIT_COUNTER_WIDTH;
typedef Bit#(CREDIT_COUNTER_WIDTH) CreditCount;

typedef Bit#(TLog#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT)) DispatchChannelIdx;

typedef struct {
    PcieTlpDataBusSegBundle         data;
    PcieTlpHeaderBusSegBundle       header;
    SopSignalBundle                 sop;
    EopSignalBundle                 eop;
    HvalidSignalBundle              hvalid;
    DvalidSignalBundle              dvalid;
    BarIdSignalBundle               bar;
    SegmentEmptySignalBundle        empty;
} PcieRxBeat deriving (Bits, FShow);

typedef struct {
    PcieTlpDataBusSegBundle         data;
    PcieTlpHeaderBusSegBundle       header;
    SopSignalBundle                 sop;
    EopSignalBundle                 eop;
    HvalidSignalBundle              hvalid;
    DvalidSignalBundle              dvalid;
} PcieTxBeat deriving (Bits, FShow);

typedef 13 PCIE_TLP_DATA_BYTE_COUNT_WIDTH;
typedef Bit#(PCIE_TLP_DATA_BYTE_COUNT_WIDTH) PcieTlpDataByteCnt;

interface RTilePcieAdaptorRx;

    // input port
    (* prefix="" *)
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

    // output port
    method Bool                                 ready;
    method HeaderCreditInitSignalBundle         hcrdt_init;
    method HeaderCreditUpdateSignalBundle       hcrdt_update;
    method HeaderCreditUpdateCntSignalBundle    hcrdt_update_cnt;

    method DataCreditInitSignalBundle           dcrdt_init;
    method DataCreditUpdateSignalBundle         dcrdt_update;
    method DataCreditUpdateCntSignalBundle      dcrdt_update_cnt;

endinterface

interface RTilePcieAdaptorTx;

    // input port
    (* prefix="" *)
    method Action setTxInputData(
        HeaderCreditInitSignalBundle        hcrdt_init,
        HeaderCreditUpdateSignalBundle      hcrdt_update,
        HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt,
        DataCreditInitSignalBundle          dcrdt_init,
        DataCreditUpdateSignalBundle        dcrdt_update,
        DataCreditUpdateCntSignalBundle     dcrdt_update_cnt,
        Bool                                ready
    );

    // output port
    method HeaderCreditInitAckSignalBundle      hcrdt_init_ack;
    method DataCreditInitAckSignalBundle        dcrdt_init_ack;
    
    method PcieTlpHeaderBusSegBundle    hdr;
    method PcieTlpDataBusSegBundle      data;
    

    method SopSignalBundle              sop;
    method EopSignalBundle              eop;
    method HvalidSignalBundle           hvalid;
    method DvalidSignalBundle           dvalid;

endinterface

interface RTilePcieAdaptor;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rx;

    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx tx;

    interface PipeOut#(PcieRxBeat) pcieRxPipeOut;
    interface PipeIn#(PcieTxBeat) pcieTxPipeIn;
endinterface

(* synthesize *)
module mkRTilePcieAdaptor(RTilePcieAdaptor);

    PcieCreditCounterSink#(CreditCount, HeaderCreditUpdateCnt) rxCreditPH <- mkPcieCreditCounterSink(784);
    PcieCreditCounterSink#(CreditCount, HeaderCreditUpdateCnt) rxCreditNPH <- mkPcieCreditCounterSink(784);
    PcieCreditCounterSink#(CreditCount, HeaderCreditUpdateCnt) rxCreditCPLH <- mkPcieCreditCounterSink(0);

    PcieCreditCounterSink#(CreditCount, DataCreditUpdateCnt) rxCreditPD <- mkPcieCreditCounterSink(1456);
    PcieCreditCounterSink#(CreditCount, DataCreditUpdateCnt) rxCreditNPD <- mkPcieCreditCounterSink(392);
    PcieCreditCounterSink#(CreditCount, DataCreditUpdateCnt) rxCreditCPLD <- mkPcieCreditCounterSink(0);

    PcieCreditCounterSource#(CreditCount, HeaderCreditUpdateCnt) txCreditPH <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, HeaderCreditUpdateCnt) txCreditNPH <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, HeaderCreditUpdateCnt) txCreditCPLH <- mkPcieCreditCounterSource;

    PcieCreditCounterSource#(CreditCount, DataCreditUpdateCnt) txCreditPD <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, DataCreditUpdateCnt) txCreditNPD <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, DataCreditUpdateCnt) txCreditCPLD <- mkPcieCreditCounterSource;

    FIFOF#(PcieRxBeat) pcieRxPipeOutQueue <- mkUGFIFOF;
    FIFOF#(PcieTxBeat) pcieTxPipeInQueue <- mkUGFIFOF;

    Reg#(Bool) txReadySignalOutputReg <- mkReg(False);

    Bool txValid = pcieTxPipeInQueue.notEmpty && txReadySignalOutputReg;

    rule deq;
        if (txValid && pcieTxPipeInQueue.notEmpty) begin
            pcieTxPipeInQueue.deq;
        end
    endrule


    interface RTilePcieAdaptorRx rx;
        // input port
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
            rxCreditPH.setInitAckSignal(hcrdt_init_ack.ph);
            rxCreditNPH.setInitAckSignal(hcrdt_init_ack.nph);
            rxCreditCPLH.setInitAckSignal(hcrdt_init_ack.cplh);
            rxCreditPD.setInitAckSignal(dcrdt_init_ack.ph);
            rxCreditNPD.setInitAckSignal(dcrdt_init_ack.nph);
            rxCreditCPLD.setInitAckSignal(dcrdt_init_ack.cplh);

            if ( (hvalid != 0) || (dvalid != 0) ) begin
                let beat = PcieRxBeat {
                    data: data, 
                    header: hdr,
                    sop: sop,
                    eop: eop,
                    hvalid: hvalid,
                    dvalid: dvalid,
                    bar: bar,
                    empty: empty
                };

                immAssert(
                    pcieRxPipeOutQueue.notFull,
                    "pcieRxPipeOutQueue is Full",
                    $format("")
                );

                pcieRxPipeOutQueue.enq(beat);
            end
        endmethod

        // output port
        method Bool                                 ready               = True;   // according to ug20316 Table 56
        method HeaderCreditInitSignalBundle         hcrdt_init          = unpack({pack(rxCreditCPLH.initSignal), pack(rxCreditNPH.initSignal), pack(rxCreditPH.initSignal)});
        method HeaderCreditUpdateSignalBundle       hcrdt_update        = unpack({pack(rxCreditCPLH.updateSignal), pack(rxCreditNPH.updateSignal), pack(rxCreditPH.updateSignal)});
        method HeaderCreditUpdateCntSignalBundle    hcrdt_update_cnt    = unpack({pack(rxCreditCPLH.updateCntSignal), pack(rxCreditNPH.updateCntSignal), pack(rxCreditPH.updateCntSignal)});

        method DataCreditInitSignalBundle           dcrdt_init          = unpack({pack(rxCreditCPLD.initSignal), pack(rxCreditNPD.initSignal), pack(rxCreditPD.initSignal)});
        method DataCreditUpdateSignalBundle         dcrdt_update        = unpack({pack(rxCreditCPLD.updateSignal), pack(rxCreditNPD.updateSignal), pack(rxCreditPD.updateSignal)});
        method DataCreditUpdateCntSignalBundle      dcrdt_update_cnt    = unpack({pack(rxCreditCPLD.updateCntSignal), pack(rxCreditNPD.updateCntSignal), pack(rxCreditPD.updateCntSignal)});
    endinterface

    interface RTilePcieAdaptorTx tx;
        // input port
        method Action setTxInputData(
            HeaderCreditInitSignalBundle        hcrdt_init,
            HeaderCreditUpdateSignalBundle      hcrdt_update,
            HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt,
            DataCreditInitSignalBundle          dcrdt_init,
            DataCreditUpdateSignalBundle        dcrdt_update,
            DataCreditUpdateCntSignalBundle     dcrdt_update_cnt,
            Bool                                ready
        );
            txCreditPH.setInputSignal(hcrdt_init.ph, hcrdt_update.ph, hcrdt_update_cnt.ph);
            txCreditNPH.setInputSignal(hcrdt_init.nph, hcrdt_update.nph, hcrdt_update_cnt.nph);
            txCreditCPLH.setInputSignal(hcrdt_init.cplh, hcrdt_update.cplh, hcrdt_update_cnt.cplh);
        
            txCreditPD.setInputSignal(dcrdt_init.pd, dcrdt_update.pd, dcrdt_update_cnt.pd);
            txCreditNPD.setInputSignal(dcrdt_init.npd, dcrdt_update.npd, dcrdt_update_cnt.npd);
            txCreditCPLD.setInputSignal(dcrdt_init.cpld, dcrdt_update.cpld, dcrdt_update_cnt.cpld);

            txReadySignalOutputReg <= ready;
        endmethod

        // output port
        method HeaderCreditInitAckSignalBundle      hcrdt_init_ack = unpack({pack(txCreditCPLH.initAckSignal), pack(txCreditNPH.initAckSignal), pack(txCreditPH.initAckSignal)});
        method DataCreditInitAckSignalBundle        dcrdt_init_ack = unpack({pack(txCreditCPLD.initAckSignal), pack(txCreditNPD.initAckSignal), pack(txCreditPD.initAckSignal)});
        
        method PcieTlpHeaderBusSegBundle    hdr = txValid ? pcieTxPipeInQueue.first.header : unpack(0);
        method PcieTlpDataBusSegBundle      data = txValid ? pcieTxPipeInQueue.first.data : unpack(0);

        method SopSignalBundle              sop = txValid ? pcieTxPipeInQueue.first.sop : unpack(0);
        method EopSignalBundle              eop = txValid ? pcieTxPipeInQueue.first.eop : unpack(0);
        method HvalidSignalBundle           hvalid = txValid ? pcieTxPipeInQueue.first.hvalid : unpack(0);
        method DvalidSignalBundle           dvalid = txValid ? pcieTxPipeInQueue.first.dvalid : unpack(0);
    endinterface

    interface pcieRxPipeOut = ugToPipeOut(pcieRxPipeOutQueue);
    interface pcieTxPipeIn = ugToPipeIn(pcieTxPipeInQueue);
endmodule


interface PcieCreditCounterSink#(type tCounter, type tDelta);
    (* always_ready, always_enabled *) method Bool     initSignal;
    (* always_ready, always_enabled *) method Action   setInitAckSignal(Bool signal);
    (* always_ready, always_enabled *) method Bool     updateSignal;
    (* always_ready, always_enabled *) method tDelta   updateCntSignal;

    method Action releaseCredit(tCounter delta);
endinterface

typedef enum {
    PcieCreditCounterSinkStateWaitingAck = 0,
    PcieCreditCounterSinkStateTransferInitValue = 1,
    PcieCreditCounterSinkStateDelayInitRelease1 = 2,
    PcieCreditCounterSinkStateDelayInitRelease2 = 3,
    PcieCreditCounterSinkStateNormalOperation = 4
} PcieCreditCounterSinkState deriving(Bits, Eq, FShow);

module mkPcieCreditCounterSink#(tCounter initValue)(PcieCreditCounterSink#(tCounter, tDelta)) provisos(
        Bits#(tCounter, szCounter),
        Bits#(tDelta, szDelta),
        Bounded#(tDelta),
        Arith#(tCounter),
        ModArith#(tCounter),
        Add#(a__, szDelta, szCounter),
        Eq#(tCounter)
    );

    Reg#(PcieCreditCounterSinkState) stateReg <- mkReg(PcieCreditCounterSinkStateWaitingAck);

    Reg#(Bool) initSignalReg <- mkReg(True);
    Reg#(Bool) updateSignalReg <- mkReg(False);
    Reg#(tDelta) updateCntSignalReg <- mkReg(unpack(0));


    Wire#(Bool) initAckSignalWire <- mkBypassWire;
    Count#(tCounter) initCounter <- mkCount(initValue);
    Count#(tCounter) updateCounter <- mkCount(unpack(0));


    tDelta maxDelta = maxBound;
    rule waitingAck if (stateReg == PcieCreditCounterSinkStateWaitingAck);
        if (initAckSignalWire) begin
            stateReg <= PcieCreditCounterSinkStateTransferInitValue;
            tDelta delta = unpack(pack(initCounter) > zeroExtend(pack(maxDelta)) ? pack(maxDelta) : truncate(pack(initCounter)));

            updateSignalReg <= True;
            updateCntSignalReg <= delta;
            initCounter.decr(unpack(zeroExtend(pack(delta))));
        end
    endrule

    rule transferInitValue if (stateReg == PcieCreditCounterSinkStateTransferInitValue);
        if (initCounter == 0) begin
            updateSignalReg <= False;
            stateReg <= PcieCreditCounterSinkStateDelayInitRelease1;
        end
        else begin
            tDelta delta = unpack(pack(initCounter) > zeroExtend(pack(maxDelta)) ? pack(maxDelta) : truncate(pack(initCounter)));
            updateCntSignalReg <= delta;
            initCounter.decr(unpack(zeroExtend(pack(delta))));
        end
    endrule

    rule delayInitRelease1 if (stateReg == PcieCreditCounterSinkStateDelayInitRelease1);
        stateReg <= PcieCreditCounterSinkStateDelayInitRelease2;
    endrule

    rule delayInitRelease2 if (stateReg == PcieCreditCounterSinkStateDelayInitRelease2);
        initSignalReg <= False;
        stateReg <= PcieCreditCounterSinkStateNormalOperation;
    endrule

    rule normalOperation if (stateReg == PcieCreditCounterSinkStateNormalOperation);
        if (updateCounter == 0) begin
            updateSignalReg <= False;
        end
        else begin
            updateSignalReg <= True;
            tDelta delta = unpack(pack(initCounter) > zeroExtend(pack(maxDelta)) ? pack(maxDelta) : truncate(pack(initCounter)));
            updateCntSignalReg <= delta;
            updateCounter.decr(unpack(zeroExtend(pack(delta))));
        end
    endrule

    method setInitAckSignal = initAckSignalWire._write;
    method Bool     initSignal = initSignalReg;
    method Bool     updateSignal = updateSignalReg;
    method tDelta   updateCntSignal = updateCntSignalReg;

    method Action releaseCredit(tCounter delta);
        updateCounter.incr(delta);
    endmethod
endmodule



interface PcieCreditCounterSource#(type tCounter, type tDelta);

    (* always_ready, always_enabled *) method Bool     initAckSignal;
    (* always_ready, always_enabled *) method Action   setInputSignal(Bool initSignal, Bool updateSignal, tDelta updateCntSignal);

    method ActionValue#(Bool) consumeCredit(tCounter delta);
endinterface

typedef enum {
    PcieCreditCounterSourceStateWaitingInit = 0,
    PcieCreditCounterSourceStateSendAck = 1,
    PcieCreditCounterSourceStateRecvInitValue = 2,
    PcieCreditCounterSourceStateNormalOperation = 3
} PcieCreditCounterSourceState deriving(Bits, Eq, FShow);

module mkPcieCreditCounterSource(PcieCreditCounterSource#(tCounter, tDelta)) provisos(
        Bits#(tCounter, szCounter),
        Bits#(tDelta, szDelta),
        Bounded#(tDelta),
        Arith#(tCounter),
        ModArith#(tCounter),
        Add#(a__, szDelta, szCounter),
        Eq#(tCounter),
        Ord#(tCounter)
    );
    Reg#(PcieCreditCounterSourceState) stateReg <- mkReg(PcieCreditCounterSourceStateWaitingInit);

    Reg#(Bool) initAckSignalReg <- mkReg(False);

    Wire#(Bool) initSignalWire <- mkBypassWire;
    Wire#(Bool) updateSignalWire <- mkBypassWire;
    Wire#(tDelta) updateCntSignalWire <- mkBypassWire;

    Count#(tCounter) counter <- mkCount(unpack(0));

    rule waitingInit if (stateReg == PcieCreditCounterSourceStateWaitingInit);
        if (initSignalWire) begin
            stateReg <= PcieCreditCounterSourceStateSendAck;
            initAckSignalReg <= True;
        end
    endrule

    rule sendAck if (stateReg == PcieCreditCounterSourceStateSendAck);
        initAckSignalReg <= False;
        stateReg <= PcieCreditCounterSourceStateRecvInitValue;
       
    endrule

    rule recvInitValue if (stateReg == PcieCreditCounterSourceStateRecvInitValue);
        if (!initSignalWire) begin
            stateReg <= PcieCreditCounterSourceStateNormalOperation;
        end
        else begin
            if (updateSignalWire) begin
                counter.incr(unpack(zeroExtend(pack(updateCntSignalWire))));
            end
        end
    endrule

    rule normalOperation if (stateReg == PcieCreditCounterSourceStateNormalOperation);   
        if (updateSignalWire) begin
            counter.incr(unpack(zeroExtend(pack(updateCntSignalWire))));
        end 
    endrule

    method Action setInputSignal(Bool initSignal, Bool updateSignal, tDelta updateCntSignal);
        initSignalWire <= initSignal;
        updateSignalWire <= updateSignal;
        updateCntSignalWire <= updateCntSignal;
    endmethod

    method initAckSignal = initAckSignalReg;

    method ActionValue#(Bool) consumeCredit(tCounter delta);
        if (delta <= counter) begin
            counter.decr(unpack(zeroExtend(pack(delta))));
            return True;
        end
        else begin
            return False;
        end
    endmethod
endmodule


typedef 3 PCIE_MAX_TLP_CNT;
typedef TLog#(PCIE_MAX_TLP_CNT) PCIE_RX_HANDLER_IDX_WIDTH;
typedef Bit#(PCIE_RX_HANDLER_IDX_WIDTH) PcieRxHandlerIdx;


typedef struct {
    PcieRxBeat rxBeat;
    PcieSegmentIdx startSegIdx;
} RawPcieRxStreamWithMeta deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderBuffer rawTlpHeader;
    PcieSegmentIdx startSegIdx;
} RawPcieRxTlpWithMeta deriving(Bits, FShow);

typedef Bit#(PCIE_TLP_DATA_BUNDLE_WIDTH) PcieDataStreamDataLsbRight;
typedef Bit#(PCIE_TLP_DATA_BUNDLE_WIDTH) PcieDataStreamDataLsbLeft;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, BYTE_WIDTH) PCIE_TLP_DATA_BUNDLE_BYTE_CNT;
typedef Bit#(TAdd#(1, TLog#(PCIE_TLP_DATA_BUNDLE_BYTE_CNT))) PcieDataStreamByteCnt;
typedef Bit#(TLog#(TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, BYTE_WIDTH))) PcieDataStreamByteIdx;

typedef DtldStreamData#(PcieDataStreamDataLsbRight) PcieDataStreamLsbRight;
typedef DtldStreamData#(PcieDataStreamDataLsbLeft) PcieDataStreamLsbLeft;

typedef 2048 RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_CNT;    // TODO: maybe can change to 1024
typedef TLog#(RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_CNT)  RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_INDEX_WIDTH;
typedef TAdd#(1, RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_INDEX_WIDTH)  RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_COUNT_WIDTH;

typedef Bit#(RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_INDEX_WIDTH) RtilePcieRxPayloadStorageRowIdx;
typedef Bit#(RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_COUNT_WIDTH) RtilePcieRxPayloadStorageRowCnt;
typedef RtilePcieRxPayloadStorageRowIdx RtilePcieRxPayloadStorageAddr;

typedef 4 RTILE_PCIE_USER_LOGIC_CHANNEL_CNT;
typedef Bit#(TLog#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT)) RTilePcieUserChannelIdx;

typedef 3 RTILE_PCIE_BYTE_CNT_IN_DW_WIDTH;
typedef Bit#(RTILE_PCIE_BYTE_CNT_IN_DW_WIDTH) RtilePcieByteCntInDw;

typedef struct {
    RtilePcieRxPayloadStorageAddr   addr;
    PcieTlpDataBusSegBundle         dataBundles;
} RtilePcieRxPayloadStorageWriteReq deriving(Bits, FShow);

typedef struct {

} RtilePcieRxTlpInfoMrRead deriving(Bits, FShow);

typedef struct {

} RtilePcieRxTlpInfoMrWrite deriving(Bits, FShow);

typedef struct {
    RtilePcieRxPayloadStorageAddr   firstBeatStorageAddr;       // 12
    PcieSegmentIdx                  firstBeatSegIdx;            // 2
    RtilePcieByteCntInDw            firstBeCnt;                 // 3
    PcieTlpDataByteCnt              byteCountInThisTlp;         // 13
    PcieHeaderFieldExtendedTag      tag;                        // 10
    Bool                            isLastCplt;                 // 1
} RtilePcieRxTlpInfoCplt deriving(Bits, FShow);

typedef union tagged {
    RtilePcieRxTlpInfoMrRead    TlpTypeMrRead;
    RtilePcieRxTlpInfoMrWrite   TlpTypeMrWrite;
    RtilePcieRxTlpInfoCplt      TlpTypeCplt;
    void                        TlpTypeInvalid;
} RtilePcieRxTlpInfo deriving(Bits, FShow);


interface PcieRxStreamSegmentFork;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutVec;
    interface PipeOut#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) memReadWriteReqTlpVecPipeOut;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpVecPipeOutVec;
endinterface

// (* synthesize *)
// module mkPcieRxStreamSegmentFork(PcieRxStreamSegmentFork);
//     FIFOF#(PcieRxBeat) pcieRxPipeInQueue <- mkFIFOF;
//     FIFOF#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) memReadWriteReqTlpVecPipeOutQueue <- mkFIFOF;

//     Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutQueueVec <- replicateM(mkFIFOF);
//     Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpPipeOutQueueVec <- replicateM(mkFIFOF);

//     Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutVecInst = newVector;
//     Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpVecPipeOutVecInst = newVector;


//     for (Integer handlerIdx = 0; handlerIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); handlerIdx = handlerIdx + 1) begin
//         tlpRawBeatDataStorageWriteReqPipeOutVecInst[handlerIdx] = toPipeOut(tlpRawBeatDataStorageWriteReqPipeOutQueueVec[handlerIdx]);
//         // tlpHeaderPipeOutInstVec[handlerIdx] = toPipeOut(tlpHeaderPipeOutQueueVec[handlerIdx]);
//     end

//     Reg#(RtilePcieRxPayloadStorageAddr) storageWriteAddrReg <- mkReg(0);

//     // Pipeline FIFOs
//     FIFOF#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) dispatchTlpInfoPipelineQueue <- mkFIFOF;

//     rule calcRxBeatMetaAndForkPayloadStorage;

//         let beat = pcieRxPipeInQueue.first;
//         pcieRxPipeInQueue.deq;

//         for (Integer idx = 0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
//             tlpRawBeatDataStorageWriteReqPipeOutQueueVec[idx].enq(RtilePcieRxPayloadStorageWriteReq {
//                 addr: storageWriteAddrReg,
//                 dataBundles: beat.data
//             });
//         end
//         storageWriteAddrReg <= storageWriteAddrReg + 1;


//         Bool isSopFlagLegal = case (pack(beat.sop))
//             'b0100, 'b1000, 'b1100, 'b1111: False;
//             default: True;
//         endcase;
//         immAssert(
//             isSopFlagLegal,
//             "one of the following 2 assumption not hold: \n \
//                1.The R-Tile PCIe IP does not use segment 2 and segment 3 if segment 0 AND segment 1 are unused \n\
//                2.At most 3 TLPs in a beat\n",
//             $format("beat=", fshow(beat))
//         );


//         Vector#(PCIE_MAX_TLP_CNT, Maybe#(PcieSegmentIdx)) tlpFirstSegmentIdxVec = case (pack(beat.sop)) matches
//             'b0000: vec(tagged Invalid, tagged Invalid, tagged Invalid);
//             'b0001: vec(tagged Valid 0, tagged Invalid, tagged Invalid);
//             'b0010: vec(tagged Valid 1, tagged Invalid, tagged Invalid);
//             'b0011: vec(tagged Valid 0, tagged Valid 1, tagged Invalid);
//             'b0100: vec(tagged Valid 2, tagged Invalid, tagged Invalid);
//             'b0101: vec(tagged Valid 0, tagged Valid 2, tagged Invalid);
//             'b0110: vec(tagged Valid 1, tagged Valid 2, tagged Invalid);
//             'b0111: vec(tagged Valid 0, tagged Valid 1, tagged Valid 2);
//             'b1000: vec(tagged Valid 3, tagged Invalid, tagged Invalid);
//             'b1001: vec(tagged Valid 0, tagged Valid 3, tagged Invalid);
//             'b1010: vec(tagged Valid 1, tagged Valid 3, tagged Invalid);
//             'b1011: vec(tagged Valid 0, tagged Valid 1, tagged Valid 3);
//             'b1100: vec(tagged Valid 2, tagged Valid 3, tagged Invalid);
//             'b1101: vec(tagged Valid 0, tagged Valid 2, tagged Valid 3);
//             'b1110: vec(tagged Valid 1, tagged Valid 2, tagged Valid 3);
//             'b1111: vec(tagged Invalid, tagged Invalid, tagged Invalid);
//         endcase;
        
//         Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) simpleTlpInfoVec = newVector;
//         for (Integer idx = 0; idx < valueOf(PCIE_MAX_TLP_CNT); idx = idx + 1) begin
//             if (tlpFirstSegmentIdxVec[idx] matches tagged Valid .segIdx) begin
//                 simpleTlpInfoVec[idx] = convertTlpToInternalDataType(beat.header[segIdx], storageWriteAddrReg, segIdx);
//             end
//             else begin
//                 simpleTlpInfoVec[idx] = tagged TlpTypeInvalid;
//             end
//         end

//         dispatchTlpInfoPipelineQueue.enq(simpleTlpInfoVec);
//         // $display(
//         //     "time=%0t:", $time,
//         //     ", tlpCnt=", fshow(tlpCnt),
//         //     ", simpleTlpInfoVec=", fshow(simpleTlpInfoVec)
//         // );

//     endrule

//     rule dispatchTlpHeader;
//         let simpleTlpInfoVec = dispatchTlpInfoPipelineQueue.first;
//         dispatchTlpInfoPipelineQueue.deq;

//         Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) memRdWrTlpInfoVec = replicate(tagged TlpTypeInvalid);
//         Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt))) cpltTlpInfoVec = replicate(replicate(tagged Invalid));

//         Bool memRdWrHasTlp = False;
//         Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) channelHasClptTlpVec = replicate(False);

//         for (Integer tlpIdx = 0; tlpIdx < valueOf(PCIE_MAX_TLP_CNT); tlpIdx = tlpIdx + 1) begin
//             case (simpleTlpInfoVec[tlpIdx]) matches
//                 tagged TlpTypeMrRead .tlp: begin
//                     memRdWrTlpInfoVec[tlpIdx] = simpleTlpInfoVec[tlpIdx];
//                     memRdWrHasTlp = True;
//                 end
//                 tagged TlpTypeMrWrite .tlp: begin
//                     memRdWrTlpInfoVec[tlpIdx] = simpleTlpInfoVec[tlpIdx];
//                     memRdWrHasTlp = True;
//                 end
//                 tagged TlpTypeCplt .tlp: begin
//                     DispatchChannelIdx dispatchIdx = truncate(tlp.tag);
//                     cpltTlpInfoVec[dispatchIdx][tlpIdx] = tagged Valid tlp;
//                     channelHasClptTlpVec[dispatchIdx] = True;
//                 end
//                 default: begin
//                     // Nothing to do
//                 end
//             endcase
//         end

//         for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
//             case ({pack(isValid(cpltTlpInfoVec[channelIdx][2])), pack(isValid(cpltTlpInfoVec[channelIdx][1])), pack(isValid(cpltTlpInfoVec[channelIdx][0]))})
//                 'b010: begin
//                     cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][1], tagged Invalid, tagged Invalid);
//                 end
//                 'b100: begin
//                     cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][2], tagged Invalid, tagged Invalid);
//                 end
//                 'b101: begin
//                     cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][0], cpltTlpInfoVec[channelIdx][2], tagged Invalid);
//                 end
//                 'b110: begin
//                     cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][1], cpltTlpInfoVec[channelIdx][2], tagged Invalid);
//                 end
//                 default: begin
//                     // Nothing to do, since no order need to change.
//                 end
//             endcase
//         end


//         case ({memRdWrTlpInfoVec[2] matches TlpTypeInvalid ? 1'b0 : 1'b1, memRdWrTlpInfoVec[1] matches TlpTypeInvalid ? 1'b0 : 1'b1, memRdWrTlpInfoVec[0] matches TlpTypeInvalid ? 1'b0 : 1'b1})
//             'b010: begin
//                 memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[1], tagged TlpTypeInvalid, tagged TlpTypeInvalid);
//             end
//             'b100: begin
//                 memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[2], tagged TlpTypeInvalid, tagged TlpTypeInvalid);
//             end
//             'b101: begin
//                 memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[0], memRdWrTlpInfoVec[2], tagged TlpTypeInvalid);
//             end
//             'b110: begin
//                 memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[1], memRdWrTlpInfoVec[2], tagged TlpTypeInvalid);
//             end
//             default: begin
//                 // Nothing to do, since no order need to change.
//             end
//         endcase


//     for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
//         if (channelHasClptTlpVec[channelIdx]) begin
//             cpltTlpPipeOutQueueVec[channelIdx].enq(cpltTlpInfoVec[channelIdx]);
//         end
//     end

//     if (memRdWrHasTlp) begin
//         memReadWriteReqTlpVecPipeOutQueue.enq(memRdWrTlpInfoVec);
//     end

//     endrule
    

//     interface pcieRxPipeIn = toPipeIn(pcieRxPipeInQueue);
//     interface tlpRawBeatDataStorageWriteReqPipeOutVec = tlpRawBeatDataStorageWriteReqPipeOutVecInst;
//     interface cpltTlpVecPipeOutVec = cpltTlpVecPipeOutVecInst;
//     interface memReadWriteReqTlpVecPipeOut = toPipeOut(memReadWriteReqTlpVecPipeOutQueue);
// endmodule


function RtilePcieRxTlpInfo convertTlpToInternalDataType(PcieTlpHeaderBuffer tlpBuffer, RtilePcieRxPayloadStorageAddr storageAddr, PcieSegmentIdx firstSegIdx);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    case ({pack(headerFirstDW.fmt), pack(headerFirstDW.typ)})
        {`PCIE_TLP_HEADER_FMT_4DW_NO_DATA, `PCIE_TLP_HEADER_TYPE_MEM_READ}: begin
            return tagged TlpTypeMrRead RtilePcieRxTlpInfoMrRead{};
        end
        {`PCIE_TLP_HEADER_FMT_4DW_WITH_DATA, `PCIE_TLP_HEADER_TYPE_MEM_WRITE}: begin
            return tagged TlpTypeMrWrite RtilePcieRxTlpInfoMrWrite{};
        end
        {`PCIE_TLP_HEADER_FMT_3DW_WITH_DATA, `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA}: begin
            let {byteCountInThisTlp, firstBeCnt, isLastCplt} = getDataLenFromTlpHeaderOfTypeCplt(tlpBuffer);
            let tag = getExtendedTagFromTlpCpltHeader(tlpBuffer);

            return tagged TlpTypeCplt RtilePcieRxTlpInfoCplt{
                firstBeatStorageAddr: storageAddr,
                firstBeatSegIdx: firstSegIdx,
                firstBeCnt: firstBeCnt,
                byteCountInThisTlp: byteCountInThisTlp,
                tag: tag,
                isLastCplt: isLastCplt
            };
        end
        default: begin
            return tagged TlpTypeInvalid;
        end

    endcase
endfunction

function Bool isPcieTlpHasPayload(PcieTlpHeaderBuffer tlpBuffer);
    PcieHeaderFieldFmt fmt = unpack(truncateLSB(tlpBuffer));
    return fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA || fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA;
endfunction

function PcieTlpHeaderCommon getPcieTlpHeaderCommon(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = unpack(truncateLSB(tlpBuffer));
    return headerFirstDW;
endfunction

function Bool isPcieTlpReadCplt(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    return (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA);
endfunction

function PcieHeaderFieldExtendedTag getExtendedTagFromTlpCpltHeader(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
    return unpack(truncate({pack(tlpHeader.commonHeader.t9), pack(tlpHeader.commonHeader.t8), pack(tlpHeader.tag)}));
endfunction

// function Bool isPcieTlpLastReadCplt(PcieTlpHeaderBuffer tlpBuffer);
//     PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
//     let tlpDataLenMaybe = getDataLenFromTlpHeader(tlpBuffer);

//     PcieTlpDataByteCnt extendedByteCount = zeroExtend(tlpHeader.byteCount);
//     extendedByteCount[valueOf(PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

//     let tlpDataLen = fromMaybe(0, tlpDataLenMaybe);
//     return extendedByteCount == tlpDataLen;
// endfunction




function PcieTlpDataByteCnt getPayloadLengthInDW(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteCnt length = zeroExtend(headerFirstDW.length);
    length[valueOf(SizeOf#(PcieHeaderFieldLength))] = pack(headerFirstDW.length == 0);  // length == 0 means 4096 bytes
    return length;
endfunction

function Tuple2#(PcieTlpDataByteCnt, RtilePcieByteCntInDw) getDataLenFromTlpHeaderWithByteEn(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteCnt lengthInDw = getPayloadLengthInDW(tlpBuffer);
    PcieTlpDataByteCnt length = lengthInDw << 2; // convert from DW to Byte
    
    PcieTlpHeaderMemoryAccess tlpHeader = unpack(truncateLSB(tlpBuffer));
    RtilePcieByteCntInDw subValFirstBe = case (pack(tlpHeader.firstDwBe)) matches
        4'b???1: 0;
        4'b??10: 1;
        4'b?100: 2;
        4'b1000: 3;
        4'b0000: 4;
        default: 0;
    endcase;

    RtilePcieByteCntInDw subValLastBe = case (pack(tlpHeader.lastDwBe)) matches
        4'b1???: 0;
        4'b01??: 1;
        4'b001?: 2;
        4'b0001: 3;
        default: 0;
    endcase;

    length = length - zeroExtend(subValFirstBe + subValLastBe);
    RtilePcieByteCntInDw firstDwByteEnCnt = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - subValFirstBe;
    return tuple2(length, firstDwByteEnCnt);
endfunction

function Tuple3#(PcieTlpDataByteCnt, RtilePcieByteCntInDw, Bool) getDataLenFromTlpHeaderOfTypeCplt(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteCnt lengthInDw = getPayloadLengthInDW(tlpBuffer);
    PcieTlpDataByteCnt length = lengthInDw << 2; // convert from DW to Byte

    PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

    // for the first cplt, lowerAddr's 2-lsb means the address offset, which is the count of invalid bytes in the first payload DW
    // for other cplt, lowerAddr's 2-lsb must be zero, so the length won't be modified.
    RtilePcieByteCntInDw firstDwByteEnCnt = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - zeroExtend(tlpHeader.lowerAddress[1:0]);
    let adjustedLength = length - zeroExtend(tlpHeader.lowerAddress[1:0]);

    PcieTlpDataByteCnt extendedByteCount = zeroExtend(tlpHeader.byteCount);
    extendedByteCount[valueOf(PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

    Bool isLastCplt = adjustedLength >= extendedByteCount;
    return tuple3(isLastCplt ? extendedByteCount : adjustedLength, firstDwByteEnCnt, isLastCplt);
endfunction

function Maybe#(PcieDataStreamByteCnt) getSignedBiDirByteShiftOffsetFromTlpHeader(PcieTlpHeaderBuffer tlpBuffer, PcieSegmentIdx startSegIdx);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);

    if (!isPcieTlpHasPayload(tlpBuffer)) begin
        return tagged Invalid;
    end
    else begin
        Integer dwordInSegmentNumberWidth = valueOf(TLog#(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH)) - valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        PcieDataStreamByteCnt sourceLowerDwAddr = zeroExtend(startSegIdx) << dwordInSegmentNumberWidth;
        
        if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_MEM_WRITE) begin
            ADDR addrDw = truncate(tlpBuffer) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);  // convert from byte aligned addr to DW aligned;

            Bit#(TSub#(TLog#(SizeOf#(PcieDataStreamByteIdx)), BYTE_DWORD_CONVERT_SHIFT_NUM)) tmpTruncateVar = truncate(addrDw);
            PcieDataStreamByteCnt targetLowerDwAddr = zeroExtend(tmpTruncateVar);

            return tagged Valid ((sourceLowerDwAddr - targetLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA) begin
            PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

            PcieDataStreamByteCnt targetLowerDwAddr = zeroExtend(tlpHeader.lowerAddress) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);

            return tagged Valid ((sourceLowerDwAddr - targetLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else begin
            return tagged Invalid;
        end
    end
endfunction

typedef struct {
    Bool isCplt;
    PcieHeaderFieldExtendedTag extTag;
    Bool isLastCplt;
} MetaForReceivedTlpDispatch deriving(Bits, FShow);

typedef struct {
    PcieDataStreamLsbRight  ds;
    PcieExtendTagHighPart   tagHigherPart;
    Bool                    isLastCplt;
} MemoeyMapAlignedDataStreamWithMetadata deriving(Bits, FShow);

typedef StreamShifterG#(PcieDataStreamDataLsbRight) PcieStreamShifter;

typedef 512                                                             PCIE_MRRS;
typedef TMul#(PCIE_MRRS, BYTE_WIDTH)                                    PCIE_MRRS_WIDTH_IN_BITS;

typedef 512                                                             PCIE_MPS;
typedef TAdd#(1, TDiv#(PCIE_MPS, PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH))     PCIE_MAX_PAYLOAD_SEGMENT_CNT_PER_TLP;
typedef TLog#(PCIE_MAX_PAYLOAD_SEGMENT_CNT_PER_TLP)                     PCIE_SEGMENT_IDX_IN_TLP_WIDTH;
typedef TAdd#(1, PCIE_SEGMENT_IDX_IN_TLP_WIDTH)                         PCIE_SEGMENT_CNT_IN_TLP_WIDTH;
typedef Bit#(PCIE_SEGMENT_IDX_IN_TLP_WIDTH)                             PcieSegIdxInTlp;
typedef Bit#(PCIE_SEGMENT_CNT_IN_TLP_WIDTH)                             PcieSegCntInTlp;

typedef 64                                                              PCIE_RCB;
typedef TAdd#(1, TDiv#(PCIE_MRRS, PCIE_RCB))                            PCIE_MAX_CPLT_TLP_CNT_PER_READ_REQUEST;
typedef TLog#(PCIE_MAX_CPLT_TLP_CNT_PER_READ_REQUEST)                   PCIE_CPLT_TLP_IDX_IN_READ_REQUEST_WIDTH;
typedef TAdd#(1, PCIE_CPLT_TLP_IDX_IN_READ_REQUEST_WIDTH)               PCIE_CPLT_TLP_CNT_IN_READ_REQUEST_WIDTH;
typedef Bit#(PCIE_CPLT_TLP_IDX_IN_READ_REQUEST_WIDTH)                   PcieClptTlpIdxInReadRequest;
typedef Bit#(PCIE_CPLT_TLP_CNT_IN_READ_REQUEST_WIDTH)                   PcieClptTlpCntInReadRequest;

typedef 64                                                                  PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT;
typedef TAdd#(1, TDiv#(PCIE_MRRS, PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT))       PCIE_MAX_CPLT_DATA_SLOT_CNT_PER_READ_REQUEST;
typedef TLog#(PCIE_MAX_CPLT_DATA_SLOT_CNT_PER_READ_REQUEST)                 PCIE_CPLT_DATA_SLOT_IDX_IN_READ_REQUEST_WIDTH;
typedef TAdd#(1, PCIE_CPLT_DATA_SLOT_IDX_IN_READ_REQUEST_WIDTH)             PCIE_CPLT_DATA_SLOT_CNT_IN_READ_REQUEST_WIDTH;
typedef Bit#(PCIE_CPLT_DATA_SLOT_IDX_IN_READ_REQUEST_WIDTH)                 PcieClptDataSlotIdxInReadRequest;
typedef Bit#(PCIE_CPLT_DATA_SLOT_CNT_IN_READ_REQUEST_WIDTH)                 PcieClptDataSlotCntInReadRequest;

typedef 1444 RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH;
typedef 2016 RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_DEPTH;

typedef TLog#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_INDEX_WIDTH;
typedef TLog#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_DEPTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_INDEX_WIDTH;
typedef TAdd#(1, RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_INDEX_WIDTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_COUNT_WIDTH;
typedef TAdd#(1, RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_INDEX_WIDTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_COUNT_WIDTH;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_INDEX_WIDTH) PcieHwCpltBufferHeaderSlotIdx;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_INDEX_WIDTH) PcieHwCpltBufferDataSlotIdx;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_COUNT_WIDTH) PcieHwCpltBufferHeaderSlotCnt;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_COUNT_WIDTH) PcieHwCpltBufferDataSlotCnt;

typedef struct {
    PcieHwCpltBufferHeaderSlotCnt   headerSlotCnt;
    PcieHwCpltBufferDataSlotCnt     dataSlotCnt;
} PcieSharedCompletionBufferSlotAllocReq deriving(Bits, FShow);

typedef struct {
    PcieHwCpltBufferHeaderSlotCnt   headerSlotCnt;
    PcieHwCpltBufferDataSlotCnt     dataSlotCnt;
} PcieSharedCompletionBufferSlotDeAllocReq deriving(Bits, FShow);

interface PcieHwCpltBufferAllocator;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotAllocReq)) tagAllocReqPipeInVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(void)) tagAllocRespPipeOutVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotDeAllocReq)) tagDeAllocPipeInVec;
endinterface

(* synthesize *)
module mkPcieHwCpltBufferAllocator(PcieHwCpltBufferAllocator);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotAllocReq))     tagAllocReqPipeInVecInst    = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(void))                                      tagAllocRespPipeOutVecInst  = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotDeAllocReq))   tagDeAllocPipeInVecInst     = newVector;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(PcieSharedCompletionBufferSlotAllocReq))     tagAllocReqPipeInQueueVec    <- replicateM(mkFIFOF);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(void))                                       tagAllocRespPipeOutQueueVec  <- replicateM(mkFIFOF);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(PcieSharedCompletionBufferSlotDeAllocReq))   tagDeAllocPipeInQueueVec     <- replicateM(mkFIFOF);


    for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        tagAllocReqPipeInVecInst[idx]   = toPipeIn(tagAllocReqPipeInQueueVec[idx]);
        tagAllocRespPipeOutVecInst[idx] = toPipeOut(tagAllocRespPipeOutQueueVec[idx]);
        tagDeAllocPipeInVecInst[idx]    = toPipeIn(tagDeAllocPipeInQueueVec[idx]);
    end
    
    Reg#(PcieHwCpltBufferHeaderSlotCnt) headerUsedReg   <- mkReg(0);
    Reg#(PcieHwCpltBufferDataSlotCnt)   dataUsedReg     <- mkReg(0);

    // Pipeline Queues
    FIFOF#(Tuple5#(PcieHwCpltBufferHeaderSlotCnt, PcieHwCpltBufferDataSlotCnt, Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool), PcieHwCpltBufferHeaderSlotCnt, PcieHwCpltBufferDataSlotCnt)) preCalcPipelineQueue <- mkFIFOF;

    rule perCalc;
        PcieHwCpltBufferHeaderSlotCnt   decrHeader  = 0;
        PcieHwCpltBufferDataSlotCnt     decrData    = 0;
        for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            if (tagDeAllocPipeInQueueVec[idx].notEmpty) begin
                decrHeader  = decrHeader    + tagDeAllocPipeInQueueVec[idx].first.headerSlotCnt;
                decrData    = decrData      + tagDeAllocPipeInQueueVec[idx].first.dataSlotCnt;
            end
        end

        PcieHwCpltBufferHeaderSlotCnt   incrHeader    = 0;
        PcieHwCpltBufferDataSlotCnt     incrData      = 0;
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) incrReqChannelFlag = replicate(False);
        for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            // important, we need to make sure the output channel is also not full, so the merge rule can't block.
            if (tagAllocReqPipeInQueueVec[idx].notEmpty && tagAllocRespPipeOutQueueVec[idx].notFull) begin
                incrHeader  = incrHeader    + tagAllocReqPipeInQueueVec[idx].first.headerSlotCnt;
                incrData    = incrData      + tagAllocReqPipeInQueueVec[idx].first.dataSlotCnt;
                incrReqChannelFlag[idx] = True;
                tagAllocReqPipeInQueueVec[idx].deq;
            end
        end
        
        preCalcPipelineQueue.enq(tuple5(incrHeader, incrData, incrReqChannelFlag, decrHeader, decrData));
    endrule

    rule merge;
        let {incrHeader, incrData, incrReqChannelFlag, decrHeader, decrData} = preCalcPipelineQueue.first;
        preCalcPipelineQueue.deq;

        let enoughHeaderToAlloc = headerUsedReg + incrHeader    <= fromInteger(valueOf(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH));
        let enoughDataToAlloc   = dataUsedReg   + incrData      <= fromInteger(valueOf(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_DEPTH));

        if (enoughHeaderToAlloc && enoughDataToAlloc) begin
            for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
                if (incrReqChannelFlag[idx] && tagAllocRespPipeOutQueueVec[idx].notFull) begin
                    tagAllocRespPipeOutQueueVec[idx].enq(unpack(0));
                end
            end
            headerUsedReg   <= headerUsedReg    + incrHeader - decrHeader;
            dataUsedReg     <= dataUsedReg      + incrData   - decrData;
        end
        else begin
            headerUsedReg   <= headerUsedReg    - decrHeader;
            dataUsedReg     <= dataUsedReg      - decrData;
        end
        
    endrule

    interface tagAllocReqPipeInVec      = tagAllocReqPipeInVecInst;
    interface tagAllocRespPipeOutVec    = tagAllocRespPipeOutVecInst;
    interface tagDeAllocPipeInVec       = tagDeAllocPipeInVecInst;
endmodule



// typedef 32 PCIE_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH;
// typedef Bit#(PCIE_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH) PcieCompletionBufferSlotUserData;

// according to UG21036, Total tag allowed is from 256 to 1023. We use the lower 2 bits of the 10 bits tag as channel index,
// so the higher 8 bits should range between 64~255.
typedef 64 PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE;
typedef 255 PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE;

typedef 8 PCIE_EXTENDED_TAG_HIGH_PART_WIDTH;
typedef Bit#(PCIE_EXTENDED_TAG_HIGH_PART_WIDTH) PcieExtendTagHighPart;

// typedef 512 PCIE_MIN_RCB_BIT_WIDTH;
// typedef TDiv#(PCIE_MIN_RCB_BIT_WIDTH, BYTE_WIDTH) PCIE_MIN_RCB_BYTE_WIDTH;
// typedef Bit#(PCIE_MIN_RCB_BIT_WIDTH) PcieRcbDataBlock;

typedef TAdd#(1, TSub#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE, PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)) PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT;
typedef TExp#(TLog#(TMul#(2, RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH))) PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT;  // mul by 2 to leave enough space to prevent wrap around. use TExp to align power of 2.

typedef TLog#(PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT) PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_IDX_WIDTH;
typedef TAdd#(1, PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_IDX_WIDTH) PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT_WIDTH;

typedef Bit#(PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_IDX_WIDTH) CpltBufferCpltTlpInfoBufferAddr;
typedef Bit#(PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT_WIDTH) CpltBufferCpltTlpInfoBufferCnt;

typedef PCIE_EXTENDED_TAG_HIGH_PART_WIDTH PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH;   // 8

typedef Bit#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH)           PcieCompletionBufferSlotIdx;
typedef Bit#(TLog#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE)) PcieCompletionBufferSlotCnt;


typedef Bit#(TLog#(PCIE_HEADER_FIELD_FIRST_DW_BE_WIDTH))            InvalidByteNumInDw;



typedef struct {
    PcieClptTlpCntInReadRequest         maxCpltTlpCntNeeded;
    PcieClptDataSlotCntInReadRequest    hwClptBufDataSlotCntNeeded;

    InvalidByteNumInDw                  firstDwInvalidByteNum;
    InvalidByteNumInDw                  lastDwInvalidByteNum;
} PcieChannelPrivateCompletionBufferSlotAllocReq deriving(Bits, FShow);

// each PCIe read request correspond to a Tag, so each tag slot correspond to a PCIe read request
typedef struct {
    CpltBufferCpltTlpInfoBufferAddr                     cpltTlpListStartAddr; 
    PcieClptTlpIdxInReadRequest                         cpltTlpListCurWriteOffset;

    PcieClptTlpCntInReadRequest                         maxCpltTlpCntNeeded;
    PcieClptDataSlotCntInReadRequest                    hwClptBufDataSlotCntNeeded;

    Bool                                                isCompleted; 
} PcieCompletionBufferTagSlotMeta deriving(Bits, FShow);

typedef struct {
    CpltBufferCpltTlpInfoBufferAddr                     cpltTlpListStartAddr; 
    PcieClptTlpIdxInReadRequest                         cpltTlpListCurReadOffset;
    PcieClptTlpIdxInReadRequest                         cpltTlpListLastReadOffset;
} PcieCompletionBufferTagSlotMetaForOutputStage deriving(Bits, FShow);

typedef struct {
    RtilePcieRxPayloadStorageAddr   storageRowAddr;             // 12
    PcieSegmentIdx                  storageSegOffset;           // 2
    RtilePcieByteCntInDw            firstBeCnt;                 // 3
    PcieSegCntInTlp                 segCntLeftToRead;           // 6     
    PcieTlpDataByteCnt              byteCountLeftInThisTlp;     // 13
    Bool                            isLastCplt;                 // 1
} PcieCompletionBufferCpltTlpInfoForOutputStage deriving(Bits, FShow);

typedef struct {
    PcieSegmentIdx                  srcSegIdx;                  // 2
    RtilePcieByteCntInDw            firstBeCnt;                 // 3    
    PcieTlpDataByteCnt              byteCountLeftInThisTlp;     // 13
    Bool                            isLast;                     // 1
} PcieCompletionBufferBeatInfoForOutputDataStreamGenerate deriving(Bits, FShow);

typedef enum {
    PcieCompletionBufferOutputStateSendStateQueryReq = 0,
    PcieCompletionBufferOutputStateWaitStateQueryResp = 1
} PcieCompletionBufferOutputState deriving(Bits, Eq, FShow);

interface PcieCompletionBuffer;
    interface PipeIn#(PcieChannelPrivateCompletionBufferSlotAllocReq) tagAllocPipeIn;
    interface PipeOut#(PcieHeaderFieldExtendedTag) tagAllocPipeOut;
    interface PipeIn#(RtilePcieRxPayloadStorageWriteReq) tlpRawBeatDataStorageWriteReqPipeIn;
    interface PipeIn#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt))) cpltTlpVecPipeIn;
    interface PipeOut#(PcieSharedCompletionBufferSlotDeAllocReq) sharedHwCpltBufferSlotDeAllocReqPipeOut;
    interface PipeOut#(DataStream) dataStreamPipeOut;
    (* always_enabled, always_ready *)
    method Action setChannelIdx(RTilePcieUserChannelIdx idx);
endinterface

(* synthesize *)
module mkPcieCompletionBuffer(PcieCompletionBuffer);

    FIFOF#(PcieChannelPrivateCompletionBufferSlotAllocReq)              tagAllocPipeInQueue                             <- mkFIFOF;
    FIFOF#(PcieHeaderFieldExtendedTag)                                  tagAllocPipeOutQueue                            <- mkFIFOF;
    FIFOF#(RtilePcieRxPayloadStorageWriteReq)                           tlpRawBeatDataStorageWriteReqPipeInQueue        <- mkFIFOF;
    FIFOF#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))   cpltTlpVecPipeInQueue                           <- mkFIFOF;
    FIFOF#(PcieSharedCompletionBufferSlotDeAllocReq)                    sharedHwCpltBufferSlotDeAllocReqPipeOutQueue    <- mkFIFOF;
    FIFOF#(DataStream)                                                  dataStreamPipeOutQueue                          <- mkFIFOF;

    Wire#(RTilePcieUserChannelIdx) channelIdxWire <- mkBypassWire;
    Reg#(PcieExtendTagHighPart) tagAllocHeadReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Reg#(PcieExtendTagHighPart) tagAllocTailReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Count#(PcieCompletionBufferSlotCnt) busySlotCounter <- mkCount(0);

    Reg#(PcieExtendTagHighPart) doneReadReqToHandlePtrReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Count#(PcieCompletionBufferSlotCnt) readReqDoneCounter <- mkCount(0);

    Reg#(CpltBufferCpltTlpInfoBufferAddr)   curCpltTlpBufferAddrToAllocReg <- mkReg(0);  

    Vector#(PCIE_SEGMENT_CNT, AutoInferBramQueuedOutput#(RtilePcieRxPayloadStorageAddr, PcieTlpDataSegment))    dataStreamStorageVec            <- replicateM(mkAutoInferBramQueuedOutput(False, ""));
    AutoInferBramQueuedOutput#(PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta)                    slotMetaStorage                 <- mkAutoInferBramQueuedOutput(False, "");
    AutoInferBramQueuedOutput#(CpltBufferCpltTlpInfoBufferAddr, RtilePcieRxTlpInfoCplt)                         cpltTlpInfoStorage              <- mkAutoInferBramQueuedOutput(False, "");

    FIFOF#(Tuple2#(PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta)) slotMetaUpdateReqQueueForTagAlloc <- mkFIFOF;
    FIFOF#(Tuple2#(PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta)) slotMetaUpdateReqQueueForWritePtrUpdate <- mkFIFOF;

    FIFOF#(PcieCompletionBufferSlotIdx) slotMetaReadReqQueueForPtrUpdate <- mkFIFOF;
    FIFOF#(PcieCompletionBufferSlotIdx) slotMetaReadReqQueueForOutputData <- mkSizedFIFOF(8);

    FIFOF#(PcieCompletionBufferTagSlotMeta) slotMetaReadRespQueueForPtrUpdate <- mkFIFOF;
    FIFOF#(PcieCompletionBufferTagSlotMeta) slotMetaReadRespQueueForOutputData <- mkFIFOF;

    FIFOF#(Bool) slotMetaReadReqKeepOrderQueue <- mkFIFOF;

    Reg#(Maybe#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) curInputCpltTlpVecMaybeReg <- mkReg(tagged Invalid);
    
    Reg#(Maybe#(PcieCompletionBufferTagSlotMetaForOutputStage))     curOutputSlotMetaMaybeReg   <- mkReg(tagged Invalid);
    Reg#(Maybe#(PcieCompletionBufferCpltTlpInfoForOutputStage))     curOutputCpltTlpMaybeReg    <- mkReg(tagged Invalid);

    // Pipeline FIFOs
    FIFOF#(RtilePcieRxTlpInfoCplt)                                              handleInputCpltTlpVecStep2PipelineQueue             <- mkFIFOF;
    FIFOF#(PcieCompletionBufferTagSlotMetaForOutputStage)                       readCpltTlpInfoForOutputPipelineQueue               <- mkFIFOF;
    FIFOF#(PcieCompletionBufferTagSlotMetaForOutputStage)                       readDataStorageForOutputPipelineQueue               <- mkFIFOF;
    FIFOF#(PcieCompletionBufferBeatInfoForOutputDataStreamGenerate)             outputDataStreamGenPipelineQueue                    <- mkFIFOF;
    FIFOF#(Tuple2#(CpltBufferCpltTlpInfoBufferAddr, RtilePcieRxTlpInfoCplt))    handleCpltTlpInfoStorageWritePipelineQueue          <- mkLFIFOF;

    PrioritySearchBuffer#(NUMERIC_TYPE_SIX, PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta) slotMetaUpdateForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_SIX));
 
    Reg#(Bool) newCompleteSlotSignalReg[3] <- mkCReg(3, False);

    Reg#(PcieCompletionBufferOutputState) outputStateReg <- mkReg(PcieCompletionBufferOutputStateSendStateQueryReq);

    Reg#(Bool) isOutputFirstBeatReg <- mkReg(True);


    rule handleDataStreamInput;
        let req = tlpRawBeatDataStorageWriteReqPipeInQueue.first;
        tlpRawBeatDataStorageWriteReqPipeInQueue.deq;

        for (Integer idx = 0; idx < valueOf(PCIE_SEGMENT_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].write(req.addr, req.dataBundles[idx]);
        end
    endrule

    rule assertChecker;
        // since the PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT is not 2^n now, maybe in the future it will become 2^n. If it become 2^n,
        // some width calculated by TLog#() will be wrong, so we need to check it. 
        immAssert(
            valueOf(PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT) < valueOf(TExp#(SizeOf#(PcieCompletionBufferSlotCnt))),
            "value overflow",
            $format("")
        );
    endrule

    rule muxSlotMetaUpdateReq;
        // writePtr update has higher priority
        if (slotMetaUpdateReqQueueForWritePtrUpdate.notEmpty) begin
            let {addr, data} = slotMetaUpdateReqQueueForWritePtrUpdate.first;
            slotMetaUpdateReqQueueForWritePtrUpdate.deq;
            slotMetaStorage.write(addr, data);
        end
        else if (slotMetaUpdateReqQueueForTagAlloc.notEmpty) begin
            let {addr, data} = slotMetaUpdateReqQueueForTagAlloc.first;
            slotMetaUpdateReqQueueForTagAlloc.deq;
            slotMetaStorage.write(addr, data);
        end
    endrule

    rule muxSlotMetaQueryReq;
        // writePtr query has higher priority
        if (slotMetaReadReqQueueForPtrUpdate.notEmpty) begin
            let addr = slotMetaReadReqQueueForPtrUpdate.first;
            slotMetaReadReqQueueForPtrUpdate.deq;
            slotMetaStorage.putReadReq(addr);
            Bool isForPtrUpdate = True;
            slotMetaReadReqKeepOrderQueue.enq(isForPtrUpdate);
        end
        else if (slotMetaReadReqQueueForOutputData.notEmpty) begin
            let addr = slotMetaReadReqQueueForOutputData.first;
            slotMetaReadReqQueueForOutputData.deq;
            slotMetaStorage.putReadReq(addr);
            Bool isForPtrUpdate = False;
            slotMetaReadReqKeepOrderQueue.enq(isForPtrUpdate);
        end
    endrule 

    rule muxSlotMetaQueryResp;
        if (slotMetaStorage.readRespPipeOut.notEmpty) begin
            let resp = slotMetaStorage.readRespPipeOut.first;
            let isForPtrUpdate = slotMetaReadReqKeepOrderQueue.first;
            slotMetaReadReqKeepOrderQueue.deq;
            slotMetaStorage.readRespPipeOut.deq;
            if (isForPtrUpdate) begin
                slotMetaReadRespQueueForPtrUpdate.enq(resp);
            end
            else begin
                slotMetaReadRespQueueForOutputData.enq(resp);
            end
        end
    endrule

    rule handleTagAlloc;
        if (busySlotCounter != fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT))) begin
            let req = tagAllocPipeInQueue.first;
            tagAllocPipeInQueue.deq;

            let newSlot = PcieCompletionBufferTagSlotMeta {
                cpltTlpListStartAddr        : curCpltTlpBufferAddrToAllocReg,
                cpltTlpListCurWriteOffset   : 0,
                isCompleted                 : False,
                maxCpltTlpCntNeeded         : req.maxCpltTlpCntNeeded,
                hwClptBufDataSlotCntNeeded  : req.hwClptBufDataSlotCntNeeded
            };
            
            PcieHeaderFieldExtendedTag tag = unpack({pack(tagAllocHeadReg), pack(channelIdxWire)});
            slotMetaUpdateReqQueueForTagAlloc.enq(tuple2(tagAllocHeadReg, newSlot));

            tagAllocPipeOutQueue.enq(tag);

            if (tagAllocHeadReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                tagAllocHeadReg <= fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
            end
            else begin
                tagAllocHeadReg <= tagAllocHeadReg + 1;
            end
            busySlotCounter.incr(1);
            curCpltTlpBufferAddrToAllocReg <= curCpltTlpBufferAddrToAllocReg + zeroExtend(req.maxCpltTlpCntNeeded);

            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleTagAlloc"),
                toBlue(", channelIdx="), fshow(channelIdxWire),
                toBlue(", tag="), fshow(tag)
            );
        end

    endrule

    rule handleInputCpltTlpVecStep1;
        if (curInputCpltTlpVecMaybeReg matches tagged Valid .curInputCpltTlpVec) begin
            immAssert(
                isValid(curInputCpltTlpVec[0]),
                "input vector's first element must be valid",
                $format("")
            );

            let curCplt = fromMaybe(?, curInputCpltTlpVec[0]);

            PcieExtendTagHighPart slotIdx = unpack(truncateLSB(curCplt.tag));
            slotMetaReadReqQueueForPtrUpdate.enq(slotIdx);
            handleInputCpltTlpVecStep2PipelineQueue.enq(curCplt);

            let newInputCpltTlpVec = shiftOutFrom0(tagged Invalid, curInputCpltTlpVec, 1);
            if (isValid(newInputCpltTlpVec[0])) begin
                curInputCpltTlpVecMaybeReg <= tagged Valid newInputCpltTlpVec;
            end
            else begin
                if (cpltTlpVecPipeInQueue.notEmpty) begin
                    curInputCpltTlpVecMaybeReg <= tagged Valid cpltTlpVecPipeInQueue.first;
                    cpltTlpVecPipeInQueue.deq;
                end
                else begin
                    curInputCpltTlpVecMaybeReg <= tagged Invalid;
                end
            end

        end
        else begin
            curInputCpltTlpVecMaybeReg <= tagged Valid cpltTlpVecPipeInQueue.first;
            cpltTlpVecPipeInQueue.deq;

            immAssert(
                isValid(cpltTlpVecPipeInQueue.first[0]),
                "input vector's first element must be valid",
                $format("")
            );
        end
    endrule

    rule handleInputCpltTlpVecStep2;
        let curCplt = handleInputCpltTlpVecStep2PipelineQueue.first;
        handleInputCpltTlpVecStep2PipelineQueue.deq;

        PcieExtendTagHighPart slotIdx = unpack(truncateLSB(curCplt.tag));

        let slotMetaReadFromBram = slotMetaReadRespQueueForPtrUpdate.first;
        slotMetaReadRespQueueForPtrUpdate.deq;
        let slotMetaFromForwardBufferMaybe      <- slotMetaUpdateForwardBuffer.search(slotIdx);
        PcieCompletionBufferTagSlotMeta slotMeta   = isValid(slotMetaFromForwardBufferMaybe) ? fromMaybe(?, slotMetaFromForwardBufferMaybe) : slotMetaReadFromBram;

        let cpltTlpEntryWriteAddr = slotMeta.cpltTlpListStartAddr + zeroExtend(slotMeta.cpltTlpListCurWriteOffset);
        handleCpltTlpInfoStorageWritePipelineQueue.enq(tuple2(cpltTlpEntryWriteAddr, curCplt));
        slotMeta.cpltTlpListCurWriteOffset = slotMeta.cpltTlpListCurWriteOffset + 1;
        
        if (curCplt.isLastCplt) begin
            newCompleteSlotSignalReg[1] <= True;
            sharedHwCpltBufferSlotDeAllocReqPipeOutQueue.enq(PcieSharedCompletionBufferSlotDeAllocReq{
                headerSlotCnt   : zeroExtend(slotMeta.maxCpltTlpCntNeeded),
                dataSlotCnt     : zeroExtend(slotMeta.hwClptBufDataSlotCntNeeded)
            });
        end

        slotMetaUpdateReqQueueForWritePtrUpdate.enq(tuple2(slotIdx, slotMeta));
        slotMetaUpdateForwardBuffer.enq(slotIdx, slotMeta);

    endrule

    rule handleCpltTlpInfoStorageWrite;
        // for timing fix
        let {cpltTlpEntryWriteAddr, curCplt} = handleCpltTlpInfoStorageWritePipelineQueue.first;
        handleCpltTlpInfoStorageWritePipelineQueue.deq;
        cpltTlpInfoStorage.write(cpltTlpEntryWriteAddr, curCplt);
    endrule

    rule outputSendStateQuery if (outputStateReg == PcieCompletionBufferOutputStateSendStateQueryReq);
        if (newCompleteSlotSignalReg[0] == True) begin
            newCompleteSlotSignalReg[0] <= False;
            slotMetaReadReqQueueForOutputData.enq(tagAllocTailReg);
            outputStateReg <= PcieCompletionBufferOutputStateWaitStateQueryResp;
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer outputSendStateQuery"),
                toBlue(", tagAllocTailReg="), fshow(tagAllocTailReg)
            );
        end
    endrule

    rule outputWaitStateQueryResp if (outputStateReg == PcieCompletionBufferOutputStateWaitStateQueryResp);
        if (slotMetaReadRespQueueForOutputData.notEmpty) begin
            let slotMeta = slotMetaReadRespQueueForOutputData.first;
            slotMetaReadRespQueueForOutputData.deq;
            if (slotMeta.isCompleted) begin
                readReqDoneCounter.incr(1);
                readCpltTlpInfoForOutputPipelineQueue.enq(PcieCompletionBufferTagSlotMetaForOutputStage {
                    cpltTlpListStartAddr        : slotMeta.cpltTlpListStartAddr,
                    cpltTlpListCurReadOffset    : 0,
                    cpltTlpListLastReadOffset   : slotMeta.cpltTlpListCurWriteOffset
                });

                let newTagAllocTail;
                if (tagAllocTailReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                    newTagAllocTail = fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
                end 
                else begin
                    newTagAllocTail = tagAllocTailReg + 1;
                end
                tagAllocTailReg <= newTagAllocTail;
                slotMetaReadReqQueueForOutputData.enq(newTagAllocTail);
            end
            else begin
                outputStateReg <= PcieCompletionBufferOutputStateSendStateQueryReq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer outputWaitStateQueryResp"),
                toBlue(", slotMeta="), fshow(slotMeta)
            );
        end
    endrule

    rule readCpltTlpInfoForOutput;
        if (curOutputSlotMetaMaybeReg matches tagged Valid .curOutputSlotMeta) begin
            let isLast = curOutputSlotMeta.cpltTlpListCurReadOffset == curOutputSlotMeta.cpltTlpListLastReadOffset;
            // let isFirst = cpltTlpListCurReadOffset == 0;
            let cpltTlpMetaAddr = curOutputSlotMeta.cpltTlpListStartAddr + zeroExtend(curOutputSlotMeta.cpltTlpListCurReadOffset);
            cpltTlpInfoStorage.putReadReq(cpltTlpMetaAddr);

            if (isLast) begin
                if (readDataStorageForOutputPipelineQueue.notEmpty) begin
                    let slotMeta = readCpltTlpInfoForOutputPipelineQueue.first;
                    readCpltTlpInfoForOutputPipelineQueue.deq;
                    curOutputSlotMetaMaybeReg <= tagged Valid slotMeta;
                    readDataStorageForOutputPipelineQueue.enq(slotMeta);
                end
                else begin
                    curOutputSlotMetaMaybeReg <= tagged Invalid;
                end
            end
            else begin
                let newOutputSlotMeta = curOutputSlotMeta;
                newOutputSlotMeta.cpltTlpListCurReadOffset = newOutputSlotMeta.cpltTlpListCurReadOffset + 1;
                curOutputSlotMetaMaybeReg <= tagged Valid newOutputSlotMeta;
            end
        end
        else begin
            let slotMeta = readCpltTlpInfoForOutputPipelineQueue.first;
            readCpltTlpInfoForOutputPipelineQueue.deq;
            curOutputSlotMetaMaybeReg <= tagged Valid slotMeta;
            readDataStorageForOutputPipelineQueue.enq(slotMeta);
        end
    endrule

    rule readDataStorageForOutput;

        PcieCompletionBufferCpltTlpInfoForOutputStage nextNewOutputCpltTlpInfo = ?;
        if (cpltTlpInfoStorage.readRespPipeOut.notEmpty) begin
            let cpltTlpInfoIn = cpltTlpInfoStorage.readRespPipeOut.first;
            let invalidByteCntInFirstDw = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - cpltTlpInfoIn.firstBeCnt;
            let totalBytesCntIncludeInvalidInThisTlp = cpltTlpInfoIn.byteCountInThisTlp + zeroExtend(invalidByteCntInFirstDw);

            immAssert(
                pack(totalBytesCntIncludeInvalidInThisTlp)[valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM)-1:0] == 2'b0,
                "totalBytesCntIncludeInvalidInThisTlp must be aligned to DWord",
                $format("")
            );
            let segCntInThisTlp = 1 + ((totalBytesCntIncludeInvalidInThisTlp - 1) >> fromInteger(valueOf(TLog#(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH))));

            nextNewOutputCpltTlpInfo = PcieCompletionBufferCpltTlpInfoForOutputStage {
                storageRowAddr          : cpltTlpInfoIn.firstBeatStorageAddr, 
                storageSegOffset        : cpltTlpInfoIn.firstBeatSegIdx,      
                firstBeCnt              : cpltTlpInfoIn.firstBeCnt,                
                segCntLeftToRead        : truncate(segCntInThisTlp),
                byteCountLeftInThisTlp  : cpltTlpInfoIn.byteCountInThisTlp,
                isLastCplt              : cpltTlpInfoIn.isLastCplt
            };
        end

        if (curOutputCpltTlpMaybeReg matches tagged Valid .curOutputCpltTlp) begin
            let curSegAddrInStorage = {pack(curOutputCpltTlp.storageRowAddr), pack(curOutputCpltTlp.storageSegOffset)};
            let isLastSegInThisCpltTlp = curOutputCpltTlp.segCntLeftToRead == 1;

            dataStreamStorageVec[curOutputCpltTlp.storageSegOffset].putReadReq(curOutputCpltTlp.storageRowAddr);
            outputDataStreamGenPipelineQueue.enq(PcieCompletionBufferBeatInfoForOutputDataStreamGenerate{
                srcSegIdx               : curOutputCpltTlp.storageSegOffset,             
                firstBeCnt              : curOutputCpltTlp.firstBeCnt,                
                byteCountLeftInThisTlp  : curOutputCpltTlp.byteCountLeftInThisTlp,
                isLast                  : isLastSegInThisCpltTlp             
            });

            let nextOutputCpltTlp = curOutputCpltTlp;

            let nextSegAddrInStorage = curSegAddrInStorage + 1;
            RtilePcieRxPayloadStorageAddr   nextStorageRowAddr      = truncateLSB(nextSegAddrInStorage);
            PcieSegmentIdx                  nextStorageSegOffset    = truncate(nextSegAddrInStorage);

            let invalidByteCntInFirstDw = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - curOutputCpltTlp.firstBeCnt;
            let byteReadInThisSeg = fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH)) - zeroExtend(invalidByteCntInFirstDw);
            // in PCIe cplt, only the first DW in first cplt tlp can have leading invalid bytes
            // so set it to BYTE_CNT_PER_DWOED for the following read.
            nextOutputCpltTlp.firstBeCnt                = fromInteger(valueOf(BYTE_CNT_PER_DWOED));
            nextOutputCpltTlp.storageRowAddr            = nextStorageRowAddr;
            nextOutputCpltTlp.storageSegOffset          = nextStorageSegOffset;
            nextOutputCpltTlp.segCntLeftToRead          = nextOutputCpltTlp.segCntLeftToRead - 1;
            nextOutputCpltTlp.byteCountLeftInThisTlp    = nextOutputCpltTlp.byteCountLeftInThisTlp - byteReadInThisSeg;

            if (isLastSegInThisCpltTlp) begin
                if (cpltTlpInfoStorage.readRespPipeOut.notEmpty) begin
                    cpltTlpInfoStorage.readRespPipeOut.deq;
                    curOutputCpltTlpMaybeReg <= tagged Valid nextNewOutputCpltTlpInfo;
                end
                else begin
                    curOutputCpltTlpMaybeReg <= tagged Invalid;
                end
            end
            else begin
                curOutputCpltTlpMaybeReg <= tagged Valid nextOutputCpltTlp;
            end
        end
        else begin
            cpltTlpInfoStorage.readRespPipeOut.deq;
            curOutputCpltTlpMaybeReg <= tagged Valid nextNewOutputCpltTlpInfo;
        end
    endrule

    rule getFinalReadRespAndConvertToDataStream;
        let beatMeta = outputDataStreamGenPipelineQueue.first;
        outputDataStreamGenPipelineQueue.deq;
        
        let readOutBeat = dataStreamStorageVec[beatMeta.srcSegIdx].readRespPipeOut.first;
        dataStreamStorageVec[beatMeta.srcSegIdx].readRespPipeOut.deq;

        let byteNum;
        let isFirst = isOutputFirstBeatReg;
        let isLast = beatMeta.isLast;

        if (isFirst && isLast) begin
            byteNum = beatMeta.byteCountLeftInThisTlp;
        end
        else if (isFirst) begin
            byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - beatMeta.byteCountLeftInThisTlp;
        end
        else if (isLast) begin
            byteNum = beatMeta.byteCountLeftInThisTlp;
        end
        else begin
            byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        end

        let ds = DataStream {
            data: readOutBeat,
            byteNum: truncate(byteNum),
            startByteIdx: zeroExtend(fromInteger(valueOf(BYTE_CNT_PER_DWOED))-beatMeta.firstBeCnt),
            isFirst: isFirst,
            isLast: isLast
        };
        dataStreamPipeOutQueue.enq(ds);

        isOutputFirstBeatReg <= beatMeta.isLast;
    endrule

    interface tagAllocPipeIn                                    = toPipeIn(tagAllocPipeInQueue);
    interface tagAllocPipeOut                                   = toPipeOut(tagAllocPipeOutQueue);
    interface tlpRawBeatDataStorageWriteReqPipeIn               = toPipeIn(tlpRawBeatDataStorageWriteReqPipeInQueue);
    interface cpltTlpVecPipeIn                                  = toPipeIn(cpltTlpVecPipeInQueue);
    interface sharedHwCpltBufferSlotDeAllocReqPipeOut           = toPipeOut(sharedHwCpltBufferSlotDeAllocReqPipeOutQueue);
    interface dataStreamPipeOut                                 = toPipeOut(dataStreamPipeOutQueue);
    method setChannelIdx = channelIdxWire._write;
endmodule



typedef DtldStreamMemAccessMeta#(ADDR, Length) PcieStreamMeta;
typedef DtldStreamData#(PcieDataStreamDataLsbRight) PcieStreamData;


typedef struct {
    PcieHeaderFieldLength       length;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieLengthAndByteEn deriving(FShow, Bits);


interface PcieRequestTlpHeaderGen;
    interface DtldStreamSlavePipes#(PcieDataStreamDataLsbRight, ADDR, Length) dtldStreamSlavePipes;
    interface PipeIn#(PcieTlpHeaderCompletion)          cpltTlpHeaderPipeIn;
    interface PipeIn#(DtldStreamData#(PcieDataStreamDataLsbRight))           cpltTlpDataStreamPipeIn;
    

    interface PipeIn#(RTilePcieUserChannelIdx)                                  writeSourceChannelIdPipeIn;
    interface PipeIn#(RTilePcieUserChannelIdx)                                  readSourceChannelIdPipeIn;

    interface Vector#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PipeOut#(PcieChannelPrivateCompletionBufferSlotAllocReq))   tagAllocPipeOutVec;
    interface Vector#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PipeIn#(PcieHeaderFieldExtendedTag))          tagAllocPipeInVec;

    interface PipeOut#(PcieTlpHeaderBuffer)                                     tlpHeaderBufferPipeOut;
    interface PipeOut#(DtldStreamData#(PcieDataStreamDataLsbRight))                                          tlpDataStreamPipeOut;
endinterface

module mkPcieRequestTlpHeaderGen(PcieRequestTlpHeaderGen);


    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  slaveSideQueueWm         <- mkFIFOF;
    FIFOF#(DtldStreamData#(PcieDataStreamDataLsbRight))                 slaveSideQueueWd         <- mkFIFOF;
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  slaveSideQueueRm         <- mkFIFOF;
    FIFOF#(DtldStreamData#(PcieDataStreamDataLsbRight))                 slaveSideQueueRd         <- mkFIFOF;

    FIFOF#(DtldStreamData#(PcieDataStreamDataLsbRight)) cpltTlpDataStreamPipeInQueue    <- mkFIFOF;

    FIFOF#(RTilePcieUserChannelIdx)    writeSourceChannelIdPipeInQueue  <- mkFIFOF;
    FIFOF#(RTilePcieUserChannelIdx)    readSourceChannelIdPipeInQueue   <- mkFIFOF;

    FIFOF#(RTilePcieUserChannelIdx)    readTagAllocKeepOrderQueue       <- mkFIFOF;

    Vector#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, FIFOF#(PcieChannelPrivateCompletionBufferSlotAllocReq))       tagAllocPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, FIFOF#(PcieHeaderFieldExtendedTag))             tagAllocPipeInQueueVec  <- replicateM(mkFIFOF);

    Vector#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PipeOut#(PcieChannelPrivateCompletionBufferSlotAllocReq))     tagAllocPipeOutVecInst  = newVector;
    Vector#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PipeIn#(PcieHeaderFieldExtendedTag))            tagAllocPipeInVecInst   = newVector;

    FIFOF#(PcieTlpHeaderMemoryRead4Dw)  readTlpQueue                <- mkFIFOF;
    FIFOF#(PcieTlpHeaderMemoryWrite4Dw) writeTlpQueue               <- mkFIFOF;
    FIFOF#(PcieTlpHeaderCompletion)     cpltTlpQueue                <- mkFIFOF;

    FIFOF#(PcieTlpHeaderBuffer)         arbittedTlpBufferQueue      <- mkFIFOF;
    FIFOF#(DtldStreamData#(PcieDataStreamDataLsbRight))      arbittedTlpDataStreamQueue  <- mkFIFOF;
    Reg#(Bool)                          isOutputingPayloadStreamReg <- mkReg(False);

    
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  tagAllocToReadTlpGenPipelineQ         <- mkFIFOF;

    for (Integer channelIdx = 0; channelIdx < valueOf(CHANNEL_PER_TLP_HEADER_TX_ARBITTER); channelIdx = channelIdx + 1) begin
        tagAllocPipeOutVecInst[channelIdx] = toPipeOut(tagAllocPipeOutQueueVec[channelIdx]);
        tagAllocPipeInVecInst[channelIdx]  = toPipeIn(tagAllocPipeInQueueVec[channelIdx]);
    end

    rule genTlpMwr;
        
        let wm = slaveSideQueueWm.first;
        slaveSideQueueWm.deq;

        // TODO: can reduce the bit width of the add operation.
        ADDR endAddr = wm.addr + unpack(zeroExtend(pack(wm.totalLen))) - 1;
        let startDwordAddr = wm.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        let lengthInDw = endDwordAddr - startDwordAddr + 1;


        PcieHeaderFieldFirstDwBe    firstDwBe = case (pack(wm.addr)[1:0])
                                                    2'b00: 4'b1111;
                                                    2'b01: 4'b1110;
                                                    2'b10: 4'b1100;
                                                    2'b11: 4'b1000;
                                                endcase;
        PcieHeaderFieldLastDwBe     lastDwBe = case (pack(endAddr)[1:0])
                                                    2'b00: 4'b0001;
                                                    2'b01: 4'b0011;
                                                    2'b10: 4'b0111;
                                                    2'b11: 4'b1111;
                                                endcase;

        let isOnlyDword = startDwordAddr == endDwordAddr;
        if (isOnlyDword) begin
            lastDwBe = 0;
        end
        
        
        let commonHeader = PcieTlpHeaderCommon {
            fmt     : `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA,
            typ     : `PCIE_TLP_HEADER_TYPE_MEM_WRITE,
            t9      : False,
            tc      : 0,
            t8      : False,
            attrh   : False,
            ln      : False,
            th      : False,
            td      : False,
            ep      : False,
            attrl   : 0,
            at      : 0,
            length  : unpack(truncate(pack(lengthInDw)))
        };
        
        let memoryWriteHeader = PcieTlpHeaderMemoryWrite {
            commonHeader    : commonHeader,
            requesterId     : 0,  // will filled by IP core
            st              : 0,
            lastDwBe        : lastDwBe,
            firstDwBe       : firstDwBe
        };

        let tlp = PcieTlpHeaderMemoryWrite4Dw {
            memoryWriteHeader   : memoryWriteHeader,
            addr                : unpack(truncateLSB(pack(wm.addr))),
            ph                  : 0
        };

        writeTlpQueue.enq(tlp);
    endrule
    

    rule sendGenPcieTagReq;
        let rm = slaveSideQueueRm.first;
        slaveSideQueueRm.deq;

        let channelIdx = readSourceChannelIdPipeInQueue.first;
        readSourceChannelIdPipeInQueue.deq;

        ADDR endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1; 

        let hwClptBufDataSlotCntNeeded = pack(rm.totalLen) >> valueOf(TLog#(PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT));
        let maxCpltTlpCntNeeded        = 1 + (pack(rm.totalLen) >> valueOf(TLog#(PCIE_RCB)));

        let req = PcieChannelPrivateCompletionBufferSlotAllocReq {
            firstDwInvalidByteNum       : truncate(pack(rm.addr)),
            lastDwInvalidByteNum        : maxBound - truncate(pack(endAddr)),
            hwClptBufDataSlotCntNeeded  : truncate(hwClptBufDataSlotCntNeeded),
            maxCpltTlpCntNeeded         : truncate(maxCpltTlpCntNeeded)
        };

        tagAllocPipeOutQueueVec[channelIdx].enq(req);
        readTagAllocKeepOrderQueue.enq(channelIdx);
        tagAllocToReadTlpGenPipelineQ.enq(rm);
    endrule

    rule genTlpMrd;
        
        let rm = tagAllocToReadTlpGenPipelineQ.first;
        tagAllocToReadTlpGenPipelineQ.deq;

        let channelIdx = readTagAllocKeepOrderQueue.first;
        readTagAllocKeepOrderQueue.deq;

        let tag = tagAllocPipeInQueueVec[channelIdx].first;
        tagAllocPipeInQueueVec[channelIdx].deq;

        // TODO: can reduce the bit width of the add operation.
        ADDR endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1;
        let startDwordAddr = rm.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        let lengthInDw = endDwordAddr - startDwordAddr + 1;   
        
        let commonHeader = PcieTlpHeaderCommon {
            fmt     : `PCIE_TLP_HEADER_FMT_4DW_NO_DATA,
            typ     : `PCIE_TLP_HEADER_TYPE_MEM_READ,
            t9      : unpack(tag[9]),
            tc      : 0,
            t8      : unpack(tag[8]),
            attrh   : False,
            ln      : False,
            th      : False,
            td      : False,
            ep      : False,
            attrl   : 0,
            at      : 0,
            length  : unpack(truncate(pack(lengthInDw)))
        };
        
        let memoryReadHeader = PcieTlpHeaderMemoryRead {
            commonHeader    : commonHeader,
            requesterId     : 0,  // will filled by IP core
            tag             : truncate(tag),
            st              : 0
        };

        let tlp = PcieTlpHeaderMemoryRead4Dw {
            memoryReadHeader    : memoryReadHeader,
            addr                : unpack(truncateLSB(pack(rm.addr))),
            ph                  : 0
        };

        readTlpQueue.enq(tlp);
    endrule


    // rule genTlpCplt;
        

    //     // TODO: can reduce the bit width of the add operation.
    //     ADDR endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1;
    //     let startDwordAddr = rm.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
    //     let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
    //     let lengthInDw = endDwordAddr - startDwordAddr + 1;   


    //     let commonHeader = PcieTlpHeaderCommon {
    //         fmt     : `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA,
    //         typ     : `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA,
    //         t9      : unpack(tag[9]),
    //         tc      : 0,
    //         t8      : unpack(tag[8]),
    //         attrh   : False,
    //         ln      : False,
    //         th      : False,
    //         td      : False,
    //         ep      : False,
    //         attrl   : 0,
    //         at      : 0,
    //         length  : unpack(truncate(pack(lengthInDw)))
    //     };

    //     let tlp = PcieTlpHeaderCompletion {
    //         PcieTlpHeaderCommon         commonHeader;
    //         PcieHeaderFieldCompleterId  completerId;
    //         PcieHeaderFieldCpltStatus   cpltStatus;
    //         Bool                        bcm;
    //         PcieHeaderFieldByteCount    byteCount;
    //         PcieHeaderFieldRequesterId  requesterId;
    //         PcieHeaderFieldTag          tag;
    //         ReservedZero#(1)            rsv1;
    //         PcieHeaderFieldLowerAddress lowerAddress;
    //     };
    // endrule


    rule arbitOutputTlp if (!isOutputingPayloadStreamReg);
        // we use a fixed priority here. The MWr is for network packet receive, can't be blocked. so it should have the highest priority.
        // for cplt, it will affect the waiting time of the software, and there is few cplt packet, so it has the middle priority.
        if (writeTlpQueue.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(writeTlpQueue.first)));
            writeTlpQueue.deq;
            let ds = slaveSideQueueWd.first;
            slaveSideQueueWd.deq;


            arbittedTlpDataStreamQueue.enq(ds);
            if (!ds.isLast) begin
                isOutputingPayloadStreamReg <= True;
            end
        end
        else if (cpltTlpQueue.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(cpltTlpQueue.first)));
            cpltTlpQueue.deq;

            let ds = cpltTlpDataStreamPipeInQueue.first;
            cpltTlpDataStreamPipeInQueue.deq;
            arbittedTlpDataStreamQueue.enq(ds);
            immAssert(
                ds.isFirst && ds.isLast && ds.byteNum <= 8 && ds.startByteIdx <= 3,
                "for read cplt, only support ONLY cplt TLP with max payload not exceed 64-bits",
                $format("ds=", fshow(ds))
            );
        end
        else if (readTlpQueue.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(readTlpQueue.first)));
            readTlpQueue.deq;
        end
    endrule

    rule arbitOutputDataStream if (isOutputingPayloadStreamReg);
        let ds = slaveSideQueueWd.first;
        slaveSideQueueWd.deq;
        arbittedTlpDataStreamQueue.enq(ds);
        if (ds.isLast) begin
            isOutputingPayloadStreamReg <= False;
        end
    endrule

    rule discardWriteSourceChannelId;
        writeSourceChannelIdPipeInQueue.deq;
    endrule

    interface DtldStreamSlavePipes dtldStreamSlavePipes;
        interface DtldStreamSlaveWritePipes writePipeIfc;
            interface  writeMetaPipeIn  = toPipeIn(slaveSideQueueWm);
            interface  writeDataPipeIn  = toPipeIn(slaveSideQueueWd);
        endinterface

        interface DtldStreamSlaveReadPipes readPipeIfc;
            interface  readMetaPipeIn  = toPipeIn(slaveSideQueueRm);
            interface  readDataPipeOut = toPipeOut(slaveSideQueueRd);
        endinterface
    endinterface

    interface cpltTlpDataStreamPipeIn = toPipeIn(cpltTlpDataStreamPipeInQueue);

    interface tagAllocPipeOutVec            = tagAllocPipeOutVecInst;
    interface tagAllocPipeInVec             = tagAllocPipeInVecInst;

    interface writeSourceChannelIdPipeIn    = toPipeIn(writeSourceChannelIdPipeInQueue);
    interface readSourceChannelIdPipeIn     = toPipeIn(readSourceChannelIdPipeInQueue);

    interface cpltTlpHeaderPipeIn           = toPipeIn(cpltTlpQueue);
    interface tlpHeaderBufferPipeOut        = toPipeOut(arbittedTlpBufferQueue);
    interface tlpDataStreamPipeOut          = toPipeOut(arbittedTlpDataStreamQueue);
endmodule



typedef enum {
    TlpHeaderAndDataCombinatorStateIdle  = 0,
    TlpHeaderAndDataCombinatorStateSendA = 1,
    TlpHeaderAndDataCombinatorStateSendB = 2
} TlpHeaderAndDataCombinatorState deriving(FShow, Eq, Bits);

/*
    ND = NO Data
    HN = Has Next beat
    LL = Last beat Less than half of beat used
    LM = Last beat More than half of beat used
*/
typedef enum {
    TlpHeaderAndDataCombinatorChannelDataStateND = 0,
    TlpHeaderAndDataCombinatorChannelDataStateHN = 1,
    TlpHeaderAndDataCombinatorChannelDataStateLL = 2,
    TlpHeaderAndDataCombinatorChannelDataStateLM = 3
} TlpHeaderAndDataCombinatorChannelDataState deriving(FShow, Eq, Bits);

typedef 2 CHANNEL_PER_TLP_HEADER_TX_ARBITTER;
typedef TDiv#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, CHANNEL_PER_TLP_HEADER_TX_ARBITTER) TLP_HEADER_TX_ARBITTER_COUNT;

interface TlpHeaderAndDataCombinator;
    interface Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(PcieTlpHeaderBuffer))                           tlpHeaderBufferPipeInVec;
    interface Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(PcieStreamData))                                tlpDataStreamPipeInVec;
    interface PipeIn#(PcieStreamData)                                                                       tlpCpltDataPipeIn;
    interface PipeOut#(PcieTxBeat)                                                                          pcieTxPipeOut;
endinterface

(* synthesize *)
module mkTlpHeaderAndDataCombinator(TlpHeaderAndDataCombinator);
    Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(PcieTlpHeaderBuffer))                          tlpHeaderBufferPipeInVecInst   = newVector;
    Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PipeIn#(PcieStreamData))                               tlpDataStreamPipeInVecInst     = newVector;

    Vector#(TLP_HEADER_TX_ARBITTER_COUNT, FIFOF#(PcieTlpHeaderBuffer))                           tlpHeaderBufferPipeInQueueVec  <- replicateM(mkFIFOF);
    Vector#(TLP_HEADER_TX_ARBITTER_COUNT, FIFOF#(PcieStreamData))                                tlpDataStreamPipeInQueueVec    <- replicateM(mkFIFOF);

    for (Integer arbiterChannelIdx = 0; arbiterChannelIdx < valueOf(TLP_HEADER_TX_ARBITTER_COUNT); arbiterChannelIdx = arbiterChannelIdx + 1) begin
        tlpHeaderBufferPipeInVecInst[arbiterChannelIdx] = toPipeIn(tlpHeaderBufferPipeInQueueVec[arbiterChannelIdx]);
        tlpDataStreamPipeInVecInst[arbiterChannelIdx]   = toPipeIn(tlpDataStreamPipeInQueueVec[arbiterChannelIdx]);
    end

    FIFOF#(PcieStreamData)                              tlpCpltDataPipeInQueue  <- mkFIFOF;
    FIFOF#(PcieTxBeat)                                  pcieTxPipeOutQueue      <- mkFIFOF;

    Reg#(Bool) arbiterNextChannelIsChannelZero <- mkReg(True);
    Reg#(Bool) currentChannelIsChannelZero <- mkReg(True);

    Reg#(TlpHeaderAndDataCombinatorState) stateReg <- mkReg(TlpHeaderAndDataCombinatorStateIdle);

    Reg#(Maybe#(PcieStreamData)) previousBeatMaybeReg <- mkReg(tagged Invalid);


    function Bool isDataStreamBeatUseLessThanHalf(PcieStreamData ds);
        let zeroBasedByteNum = ds.byteNum - 1;
        return msb(pack(zeroBasedByteNum) << 1) == 0;
    endfunction

    function Bool isDataStreamSegment1Or3Used(PcieStreamData ds);
        let zeroBasedByteNum = ds.byteNum - 1;
        return msb(pack(zeroBasedByteNum) << 2) == 0;
    endfunction


    rule mixOutputIdle if (stateReg == TlpHeaderAndDataCombinatorStateIdle);
        let  headerA = unpack(0);
        let  headerB = unpack(0);

        Bool hasHeaderA = False;
        Bool hasHeaderB = False;
        let  payloadDsA = unpack(0);
        let  payloadDsB = unpack(0);
        Bool hasPayloadA = False;
        Bool hasPayloadB = False;

        if (tlpHeaderBufferPipeInQueueVec[0].notEmpty) begin
            hasHeaderA = True;
            headerA = tlpHeaderBufferPipeInQueueVec[0].first;
            let isChannelZeroHasPayload = isPcieTlpHasPayload(headerA);
            if (isChannelZeroHasPayload) begin
                payloadDsA = tlpDataStreamPipeInQueueVec[0].first;
                hasPayloadA = True;
            end
        end

        if (tlpHeaderBufferPipeInQueueVec[1].notEmpty) begin
            hasHeaderB = True;
            headerB = tlpHeaderBufferPipeInQueueVec[1].first;
            let isChannelZeroHasPayload = isPcieTlpHasPayload(headerB);
            if (isChannelZeroHasPayload) begin
                payloadDsB = tlpDataStreamPipeInQueueVec[1].first;
                hasPayloadB = True;
            end
        end
        
        Bool payloadExceedHalfA = !isDataStreamBeatUseLessThanHalf(payloadDsA);
        Bool payloadExceedHalfB = !isDataStreamBeatUseLessThanHalf(payloadDsB);

        // Bool isPayloadOnlyBeatA = payloadDsA.isFirst && payloadDsA.isLast;
        // Bool isPayloadOnlyBeatB = payloadDsB.isFirst && payloadDsB.isLast;

        Bool hasMoreDataA = !payloadDsA.isLast;
        Bool hasMoreDataB = !payloadDsB.isLast;

        Bool isSegment1Or3UsedA = isDataStreamSegment1Or3Used(payloadDsA);
        Bool isSegment1Or3UsedB = isDataStreamSegment1Or3Used(payloadDsB);

        TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateA = ?;
        TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateB = ?;

        if (!hasPayloadA) begin
            channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateND;
        end
        else if (hasMoreDataA) begin
            channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateHN;
        end
        else begin
            channelDataLogicStateA = payloadExceedHalfA ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
        end

        if (!hasPayloadB) begin
            channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateND;
        end
        else if (hasMoreDataB) begin
            channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateHN;
        end
        else begin
            channelDataLogicStateB = payloadExceedHalfB ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
        end



        PcieTlpDataBusSegBundle         dataOut    = unpack(0);
        PcieTlpHeaderBusSegBundle       headerOut  = unpack(0);
        SopSignalBundle                 sopOut     = unpack(0);
        EopSignalBundle                 eopOut     = unpack(0);
        HvalidSignalBundle              hvalidOut  = unpack(0);
        DvalidSignalBundle              dvalidOut  = unpack(0);


        PcieTlpDataBusSegBundle payloadAsPcieDataBundleA = unpack(payloadDsA.data);
        PcieTlpDataBusSegBundle payloadAsPcieDataBundleB = unpack(payloadDsB.data);

        

        if (hasHeaderA) begin
            headerOut[0] = headerA;
            tlpHeaderBufferPipeInQueueVec[0].deq;
            hvalidOut[0] = 1;
            sopOut[0] = 1;
            if (hasPayloadA) begin
                tlpDataStreamPipeInQueueVec[0].deq;
            end

            dataOut[0] = payloadAsPcieDataBundleA[0];
            dataOut[1] = payloadAsPcieDataBundleA[1];
            dvalidOut[0] = pack(hasPayloadA);
            dvalidOut[1] = pack(hasPayloadA && (payloadExceedHalfA || (!payloadExceedHalfA && isSegment1Or3UsedA)));


            $display(
                "time=%0t:", $time, toGreen(" mkTlpHeaderAndDataCombinator mixOutputIdle"),
                toBlue(", channelDataLogicStateA="), fshow(channelDataLogicStateA),
                toBlue(", payloadAsPcieDataBundleA="), fshow(payloadAsPcieDataBundleA) 
            );

            case (channelDataLogicStateA) 
                TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                    dataOut[2] = payloadAsPcieDataBundleA[2];
                    dataOut[3] = payloadAsPcieDataBundleA[3];
                    dvalidOut[2] = 1; dvalidOut[3] = 1;
                    stateReg <= TlpHeaderAndDataCombinatorStateSendA;
                end
                TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                    dataOut[2] = payloadAsPcieDataBundleA[2];
                    dataOut[3] = payloadAsPcieDataBundleA[3];
                    dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedA);
                    eopOut[2] = pack(!isSegment1Or3UsedA); eopOut[3] = pack(isSegment1Or3UsedA);
                end
                TlpHeaderAndDataCombinatorChannelDataStateLL, TlpHeaderAndDataCombinatorChannelDataStateND: begin
                    if (channelDataLogicStateA == TlpHeaderAndDataCombinatorChannelDataStateLL) begin
                        eopOut[0] = pack(!isSegment1Or3UsedA); eopOut[1] = pack(isSegment1Or3UsedA);
                    end
                    else begin
                        eopOut[0] = 1;
                    end

                    if (hasHeaderB) begin
                        headerOut[2] = headerB;
                        tlpHeaderBufferPipeInQueueVec[1].deq;
                        hvalidOut[2] = 1;
                        sopOut[2] = 1;
                    end
                    if (hasPayloadB) begin
                        tlpDataStreamPipeInQueueVec[1].deq;
                    end

                    $display(
                        "time=%0t:", $time, toGreen(" mkTlpHeaderAndDataCombinator mixOutputIdle"),
                        toBlue(", channelDataLogicStateB="), fshow(channelDataLogicStateB),
                        toBlue(", payloadAsPcieDataBundleB="), fshow(payloadAsPcieDataBundleB) 
                    );

                    case (channelDataLogicStateB)
                        TlpHeaderAndDataCombinatorChannelDataStateLL: begin
                            dataOut[2] = payloadAsPcieDataBundleB[0];
                            dataOut[3] = payloadAsPcieDataBundleB[1];
                            dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
                            eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
                        end
                        TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                            dataOut[2] = payloadAsPcieDataBundleB[0];
                            dataOut[3] = payloadAsPcieDataBundleB[1];
                            dvalidOut[2] = 1; dvalidOut[3] = 1;
                            previousBeatMaybeReg <= tagged Valid payloadDsB;
                            stateReg <= TlpHeaderAndDataCombinatorStateSendB;
                        end
                        TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                            dataOut[2] = payloadAsPcieDataBundleB[0];
                            dataOut[3] = payloadAsPcieDataBundleB[1];
                            dvalidOut[2] = 1; dvalidOut[3] = 1;
                            previousBeatMaybeReg <= tagged Valid payloadDsB;
                            stateReg <= TlpHeaderAndDataCombinatorStateSendB;
                        end
                        TlpHeaderAndDataCombinatorChannelDataStateND: begin
                            eopOut[2] = 1;
                        end
                    endcase
                end
            endcase

            let outBeat = PcieTxBeat {
                data    : dataOut,
                header  : headerOut,
                sop     : sopOut,
                eop     : eopOut,
                hvalid  : hvalidOut,
                dvalid  : dvalidOut
            };
            pcieTxPipeOutQueue.enq(outBeat);
        end
        else if (hasHeaderB) begin
            headerOut[0] = headerB;
            tlpHeaderBufferPipeInQueueVec[1].deq;
            hvalidOut[0] = 1;
            sopOut[0] = 1;
            if (hasPayloadB) begin
                tlpDataStreamPipeInQueueVec[1].deq;
            end

            dataOut[0] = payloadAsPcieDataBundleB[0];
            dataOut[1] = payloadAsPcieDataBundleB[1];
            dvalidOut[0] = pack(hasPayloadB);
            dvalidOut[1] = pack(hasPayloadB && (payloadExceedHalfB || (!payloadExceedHalfB && isSegment1Or3UsedB)));

            case (channelDataLogicStateB) 
                TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                    dataOut[2] = payloadAsPcieDataBundleB[2];
                    dataOut[3] = payloadAsPcieDataBundleB[3];
                    dvalidOut[2] = 1; dvalidOut[3] = 1;
                    stateReg <= TlpHeaderAndDataCombinatorStateSendB;
                end
                TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                    dataOut[2] = payloadAsPcieDataBundleB[2];
                    dataOut[3] = payloadAsPcieDataBundleB[3];
                    dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
                    eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
                end
                TlpHeaderAndDataCombinatorChannelDataStateLL: begin
                    eopOut[0] = pack(!isSegment1Or3UsedB); eopOut[1] = pack(isSegment1Or3UsedB);
                end
                TlpHeaderAndDataCombinatorChannelDataStateND: begin
                    eopOut[0] = 1;
                end
            endcase

            let outBeat = PcieTxBeat {
                data    : dataOut,
                header  : headerOut,
                sop     : sopOut,
                eop     : eopOut,
                hvalid  : hvalidOut,
                dvalid  : dvalidOut
            };
            pcieTxPipeOutQueue.enq(outBeat);
        end


    endrule


    rule mixOutputSendA if (stateReg == TlpHeaderAndDataCombinatorStateSendA);

        PcieTlpDataBusSegBundle payloadAsPcieDataBundleA    = ?;
        Bool                    payloadExceedHalfA          = ?;
        Bool                    isSegment1Or3UsedA          = ?;
        Bool                    hasMoreDataA                = ?;

        let                     prevPayloadDsA                  = fromMaybe(?, previousBeatMaybeReg);
        PcieTlpDataBusSegBundle previousPayloadAsPcieDataBundle = unpack(prevPayloadDsA.data);
        Bool                    isPreviousBeatSegment1Or3Used   = isDataStreamSegment1Or3Used(prevPayloadDsA);
        Bool                    isPreviousPayloadExceedHalf     = !isDataStreamBeatUseLessThanHalf(prevPayloadDsA);

        let newPayloadDsA = unpack(0);
        if (tlpDataStreamPipeInQueueVec[0].notEmpty) begin
            newPayloadDsA = tlpDataStreamPipeInQueueVec[0].first;
            tlpDataStreamPipeInQueueVec[0].deq;
        end
        PcieTlpDataBusSegBundle newPayloadAsPcieDataBundle  = unpack(newPayloadDsA.data);
        Bool                    isNewBeatSegment1Or3Used    = isDataStreamSegment1Or3Used(newPayloadDsA);
        Bool                    isNewPayloadExceedHalf      = !isDataStreamBeatUseLessThanHalf(newPayloadDsA);

        if (isValid(previousBeatMaybeReg)) begin
            
            payloadAsPcieDataBundleA[0] = previousPayloadAsPcieDataBundle[2];
            payloadAsPcieDataBundleA[1] = previousPayloadAsPcieDataBundle[3];

            if (prevPayloadDsA.isLast) begin
                payloadExceedHalfA = False;
                isSegment1Or3UsedA = isPreviousBeatSegment1Or3Used;
                hasMoreDataA = False;
            end
            else begin
                payloadAsPcieDataBundleA[2] = newPayloadAsPcieDataBundle[0];
                payloadAsPcieDataBundleA[3] = newPayloadAsPcieDataBundle[1];
                payloadExceedHalfA = True;
                hasMoreDataA = isNewPayloadExceedHalf;
                if (isNewPayloadExceedHalf) begin
                    isSegment1Or3UsedA = True;  // seg 3 must be used.
                end
                else begin
                    isSegment1Or3UsedA = isNewBeatSegment1Or3Used;
                end
            end
        end
        else begin
            payloadAsPcieDataBundleA    = newPayloadAsPcieDataBundle;
            payloadExceedHalfA          = isNewPayloadExceedHalf;
            isSegment1Or3UsedA          = isNewBeatSegment1Or3Used;
            hasMoreDataA                = !newPayloadDsA.isLast;
        end
        
        let  headerB = unpack(0);
        Bool hasHeaderB     = False;
        let  payloadDsB     = unpack(0);
        Bool hasPayloadB    = False;

        if (tlpHeaderBufferPipeInQueueVec[1].notEmpty) begin
            hasHeaderB = True;
            headerB = tlpHeaderBufferPipeInQueueVec[1].first;
            let isChannelZeroHasPayload = isPcieTlpHasPayload(headerB);
            if (isChannelZeroHasPayload) begin
                payloadDsB = tlpDataStreamPipeInQueueVec[1].first;
                hasPayloadB = True;
            end
        end        
        PcieTlpDataBusSegBundle payloadAsPcieDataBundleB = unpack(payloadDsB.data);
        Bool payloadExceedHalfB = !isDataStreamBeatUseLessThanHalf(payloadDsB);
        Bool hasMoreDataB = !payloadDsB.isLast;
        Bool isSegment1Or3UsedB = isDataStreamSegment1Or3Used(payloadDsB);


        TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateA = ?;
        TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateB = ?;

        if (hasMoreDataA) begin
            channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateHN;
        end
        else begin
            channelDataLogicStateA = payloadExceedHalfA ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
        end

        if (!hasPayloadB) begin
            channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateND;
        end
        else if (hasMoreDataB) begin
            channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateHN;
        end
        else begin
            channelDataLogicStateB = payloadExceedHalfB ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
        end



        PcieTlpDataBusSegBundle         dataOut    = unpack(0);
        PcieTlpHeaderBusSegBundle       headerOut  = unpack(0);
        SopSignalBundle                 sopOut     = unpack(0);
        EopSignalBundle                 eopOut     = unpack(0);
        HvalidSignalBundle              hvalidOut  = unpack(0);
        DvalidSignalBundle              dvalidOut  = unpack(0);


        dataOut[0] = payloadAsPcieDataBundleA[0];
        dataOut[1] = payloadAsPcieDataBundleA[1];
        dvalidOut[0] = 1;
        dvalidOut[1] = pack(payloadExceedHalfA || (!payloadExceedHalfA && isSegment1Or3UsedA));

        case (channelDataLogicStateA) 
            TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                dataOut[2] = payloadAsPcieDataBundleA[2];
                dataOut[3] = payloadAsPcieDataBundleA[3];
                dvalidOut[2] = 1; dvalidOut[3] = 1;
                if (isValid(previousBeatMaybeReg)) begin
                    // is the first beat is started at 0, then all the following beat also aligned, no previousBeatReg is needed
                    // but if the first beat is shared with another channel (not atarted at 0, but started at half of the beat),
                    // then all the following beat need previousBeatReg to concat the data.
                    previousBeatMaybeReg <= tagged Valid newPayloadDsA;
                end
            end
            TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                dataOut[2] = payloadAsPcieDataBundleA[2];
                dataOut[3] = payloadAsPcieDataBundleA[3];
                dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedA);
                eopOut[2] = pack(!isSegment1Or3UsedA); eopOut[3] = pack(isSegment1Or3UsedA);
                previousBeatMaybeReg <= tagged Invalid;
                stateReg <= TlpHeaderAndDataCombinatorStateIdle;
            end
            TlpHeaderAndDataCombinatorChannelDataStateLL: begin
                eopOut[0] = pack(!isSegment1Or3UsedA); eopOut[1] = pack(isSegment1Or3UsedA);

                if (hasHeaderB) begin
                    headerOut[2] = headerB;
                    tlpHeaderBufferPipeInQueueVec[1].deq;
                    hvalidOut[2] = 1;
                    sopOut[2] = 1;
                end
                if (hasPayloadB) begin
                    tlpDataStreamPipeInQueueVec[1].deq;
                end

                case (channelDataLogicStateB)
                    TlpHeaderAndDataCombinatorChannelDataStateND: begin
                        previousBeatMaybeReg <= tagged Invalid;
                        stateReg <= TlpHeaderAndDataCombinatorStateIdle;
                        eopOut[2] = 1;
                    end
                    TlpHeaderAndDataCombinatorChannelDataStateLL: begin
                        dataOut[2] = payloadAsPcieDataBundleB[0];
                        dataOut[3] = payloadAsPcieDataBundleB[1];
                        dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
                        eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
                        previousBeatMaybeReg <= tagged Invalid;
                        stateReg <= TlpHeaderAndDataCombinatorStateIdle;
                    end
                    TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                        dataOut[2] = payloadAsPcieDataBundleB[0];
                        dataOut[3] = payloadAsPcieDataBundleB[1];
                        dvalidOut[2] = 1; dvalidOut[3] = 1;
                        previousBeatMaybeReg <= tagged Valid payloadDsB;
                        stateReg <= TlpHeaderAndDataCombinatorStateSendB;
                    end
                    TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                        dataOut[2] = payloadAsPcieDataBundleB[0];
                        dataOut[3] = payloadAsPcieDataBundleB[1];
                        dvalidOut[2] = 1; dvalidOut[3] = 1;
                        previousBeatMaybeReg <= tagged Valid payloadDsB;
                        stateReg <= TlpHeaderAndDataCombinatorStateSendB;
                    end
                endcase
            end
            TlpHeaderAndDataCombinatorChannelDataStateND: begin
                immFail("should not reach here. In this state, channel A must have data", $format(""));
            end
        endcase

        let outBeat = PcieTxBeat {
            data    : dataOut,
            header  : headerOut,
            sop     : sopOut,
            eop     : eopOut,
            hvalid  : hvalidOut,
            dvalid  : dvalidOut
        };
        pcieTxPipeOutQueue.enq(outBeat);
    endrule

    


    rule mixOutputSendB if (stateReg == TlpHeaderAndDataCombinatorStateSendB);

        PcieTlpDataBusSegBundle payloadAsPcieDataBundleB    = ?;
        Bool                    payloadExceedHalfB          = ?;
        Bool                    isSegment1Or3UsedB          = ?;
        Bool                    hasMoreDataB                = ?;

        let                     prevPayloadDsB                  = fromMaybe(?, previousBeatMaybeReg);
        PcieTlpDataBusSegBundle previousPayloadAsPcieDataBundle = unpack(prevPayloadDsB.data);
        Bool                    isPreviousBeatSegment1Or3Used   = isDataStreamSegment1Or3Used(prevPayloadDsB);
        Bool                    isPreviousPayloadExceedHalf     = !isDataStreamBeatUseLessThanHalf(prevPayloadDsB);

        let newPayloadDsB = unpack(0);
        if (tlpDataStreamPipeInQueueVec[1].notEmpty) begin
            newPayloadDsB = tlpDataStreamPipeInQueueVec[1].first;
            tlpDataStreamPipeInQueueVec[1].deq;
        end
        PcieTlpDataBusSegBundle newPayloadAsPcieDataBundle  = unpack(newPayloadDsB.data);
        Bool                    isNewBeatSegment1Or3Used    = isDataStreamSegment1Or3Used(newPayloadDsB);
        Bool                    isNewPayloadExceedHalf      = !isDataStreamBeatUseLessThanHalf(newPayloadDsB);

        if (isValid(previousBeatMaybeReg)) begin
            
            payloadAsPcieDataBundleB[0] = previousPayloadAsPcieDataBundle[2];
            payloadAsPcieDataBundleB[1] = previousPayloadAsPcieDataBundle[3];

            if (prevPayloadDsB.isLast) begin
                payloadExceedHalfB = False;
                isSegment1Or3UsedB = isPreviousBeatSegment1Or3Used;
                hasMoreDataB = False;
            end
            else begin
                payloadAsPcieDataBundleB[2] = newPayloadAsPcieDataBundle[0];
                payloadAsPcieDataBundleB[3] = newPayloadAsPcieDataBundle[1];
                payloadExceedHalfB = True;
                hasMoreDataB = isNewPayloadExceedHalf;
                if (isNewPayloadExceedHalf) begin
                    isSegment1Or3UsedB = True;  // seg 3 must be used.
                end
                else begin
                    isSegment1Or3UsedB = isNewBeatSegment1Or3Used;
                end
            end
        end
        else begin
            payloadAsPcieDataBundleB    = newPayloadAsPcieDataBundle;
            payloadExceedHalfB          = isNewPayloadExceedHalf;
            isSegment1Or3UsedB          = isNewBeatSegment1Or3Used;
            hasMoreDataB                = !newPayloadDsB.isLast;
        end
        
        let  headerA = unpack(0);
        Bool hasHeaderA     = False;
        let  payloadDsA     = unpack(0);
        Bool hasPayloadA    = False;

        if (tlpHeaderBufferPipeInQueueVec[0].notEmpty) begin
            hasHeaderA = True;
            headerA = tlpHeaderBufferPipeInQueueVec[0].first;
            let isChannelZeroHasPayload = isPcieTlpHasPayload(headerA);
            if (isChannelZeroHasPayload) begin
                payloadDsA = tlpDataStreamPipeInQueueVec[0].first;
                hasPayloadA = True;
            end
        end        
        PcieTlpDataBusSegBundle payloadAsPcieDataBundleA = unpack(payloadDsA.data);
        Bool payloadExceedHalfA = !isDataStreamBeatUseLessThanHalf(payloadDsA);
        Bool hasMoreDataA = !payloadDsA.isLast;
        Bool isSegment1Or3UsedA = isDataStreamSegment1Or3Used(payloadDsA);


        TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateA = ?;
        TlpHeaderAndDataCombinatorChannelDataState channelDataLogicStateB = ?;

        if (hasMoreDataB) begin
            channelDataLogicStateB = TlpHeaderAndDataCombinatorChannelDataStateHN;
        end
        else begin
            channelDataLogicStateB = payloadExceedHalfB ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
        end

        if (!hasPayloadA) begin
            channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateND;
        end
        else if (hasMoreDataA) begin
            channelDataLogicStateA = TlpHeaderAndDataCombinatorChannelDataStateHN;
        end
        else begin
            channelDataLogicStateA = payloadExceedHalfA ? TlpHeaderAndDataCombinatorChannelDataStateLM : TlpHeaderAndDataCombinatorChannelDataStateLL;
        end



        PcieTlpDataBusSegBundle         dataOut    = unpack(0);
        PcieTlpHeaderBusSegBundle       headerOut  = unpack(0);
        SopSignalBundle                 sopOut     = unpack(0);
        EopSignalBundle                 eopOut     = unpack(0);
        HvalidSignalBundle              hvalidOut  = unpack(0);
        DvalidSignalBundle              dvalidOut  = unpack(0);


        dataOut[0] = payloadAsPcieDataBundleB[0];
        dataOut[1] = payloadAsPcieDataBundleB[1];
        dvalidOut[0] = 1;
        dvalidOut[1] = pack(payloadExceedHalfB || (!payloadExceedHalfB && isSegment1Or3UsedB));

        case (channelDataLogicStateB) 
            TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                dataOut[2] = payloadAsPcieDataBundleB[2];
                dataOut[3] = payloadAsPcieDataBundleB[3];
                dvalidOut[2] = 1; dvalidOut[3] = 1;
                if (isValid(previousBeatMaybeReg)) begin
                    // is the first beat is started at 0, then all the following beat also aligned, no previousBeatReg is needed
                    // but if the first beat is shared with another channel (not atarted at 0, but started at half of the beat),
                    // then all the following beat need previousBeatReg to concat the data.
                    previousBeatMaybeReg <= tagged Valid newPayloadDsB;
                end
            end
            TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                dataOut[2] = payloadAsPcieDataBundleB[2];
                dataOut[3] = payloadAsPcieDataBundleB[3];
                dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedB);
                eopOut[2] = pack(!isSegment1Or3UsedB); eopOut[3] = pack(isSegment1Or3UsedB);
                previousBeatMaybeReg <= tagged Invalid;
                stateReg <= TlpHeaderAndDataCombinatorStateIdle;
            end
            TlpHeaderAndDataCombinatorChannelDataStateLL: begin
                eopOut[0] = pack(!isSegment1Or3UsedB); eopOut[1] = pack(isSegment1Or3UsedB);

                if (hasHeaderA) begin
                    headerOut[2] = headerA;
                    tlpHeaderBufferPipeInQueueVec[0].deq;
                    hvalidOut[2] = 1;
                    sopOut[2] = 1;
                end
                if (hasPayloadA) begin
                    tlpDataStreamPipeInQueueVec[0].deq;
                end

                case (channelDataLogicStateA)
                    TlpHeaderAndDataCombinatorChannelDataStateND: begin
                        previousBeatMaybeReg <= tagged Invalid;
                        stateReg <= TlpHeaderAndDataCombinatorStateIdle;
                        eopOut[2] = 1;
                    end
                    TlpHeaderAndDataCombinatorChannelDataStateLL: begin
                        dataOut[2] = payloadAsPcieDataBundleA[0];
                        dataOut[3] = payloadAsPcieDataBundleA[1];
                        dvalidOut[2] = 1; dvalidOut[3] = pack(isSegment1Or3UsedA);
                        eopOut[2] = pack(!isSegment1Or3UsedA); eopOut[3] = pack(isSegment1Or3UsedA);
                        previousBeatMaybeReg <= tagged Invalid;
                        stateReg <= TlpHeaderAndDataCombinatorStateIdle;
                    end
                    TlpHeaderAndDataCombinatorChannelDataStateLM: begin
                        dataOut[2] = payloadAsPcieDataBundleA[0];
                        dataOut[3] = payloadAsPcieDataBundleA[1];
                        dvalidOut[2] = 1; dvalidOut[3] = 1;
                        previousBeatMaybeReg <= tagged Valid payloadDsA;
                        stateReg <= TlpHeaderAndDataCombinatorStateSendA;
                    end
                    TlpHeaderAndDataCombinatorChannelDataStateHN: begin
                        dataOut[2] = payloadAsPcieDataBundleA[0];
                        dataOut[3] = payloadAsPcieDataBundleA[1];
                        dvalidOut[2] = 1; dvalidOut[3] = 1;
                        previousBeatMaybeReg <= tagged Valid payloadDsA;
                        stateReg <= TlpHeaderAndDataCombinatorStateSendA;
                    end
                endcase
            end
            TlpHeaderAndDataCombinatorChannelDataStateND: begin
                immFail("should not reach here. In this state, channel A must have data", $format(""));
            end
        endcase

        let outBeat = PcieTxBeat {
            data    : dataOut,
            header  : headerOut,
            sop     : sopOut,
            eop     : eopOut,
            hvalid  : hvalidOut,
            dvalid  : dvalidOut
        };
        pcieTxPipeOutQueue.enq(outBeat);
    endrule

    interface tlpHeaderBufferPipeInVec = tlpHeaderBufferPipeInVecInst;
    interface tlpDataStreamPipeInVec = tlpDataStreamPipeInVecInst;

    interface tlpCpltDataPipeIn = toPipeIn(tlpCpltDataPipeInQueue);
    interface pcieTxPipeOut     = toPipeOut(pcieTxPipeOutQueue);
endmodule






typedef DtldStreamSlavePipes#(PcieDataStreamDataLsbRight, ADDR, Length) DtldStreamSlavePipesWide;


// interface RTilePcie;
//     interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
//     interface PipeOut#(PcieTxBeat) pcieTxPipeOut;
//     interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVec;
// endinterface


// (* synthesize *)
// module mkRTilePcie(RTilePcie);
//     let pcieRxStreamSegmentFork <- mkPcieRxStreamSegmentFork;

//     // Vector#(PCIE_MAX_TLP_CNT, TlpDemuxAndConvertToMemMapStream) rxTlpHandlerVec <- replicateM(mkTlpDemuxAndConvertToMemMapStream);

//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PcieCompletionBuffer) cpltBufferVec = newVector;

//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DataStreamArbiterForCompletionBuffer) cpltBufferArbiterVec <- replicateM(mkDataStreamArbiterForCompletionBuffer);

//     for (Integer channelIdx = 0; channelIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
//         cpltBufferVec[channelIdx] <- mkPcieCompletionBuffer(fromInteger(channelIdx));
//         mkConnection(cpltBufferArbiterVec[channelIdx].dataStreamPipeOut, cpltBufferVec[channelIdx].dataStreamPipeIn);
//     end

//     Vector#(TLP_HEADER_TX_ARBITTER_COUNT, DtldStreamArbiterSlave#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PcieDataStreamDataLsbRight, ADDR, Length)) arbiterVec <- replicateM(mkDtldStreamArbiterSlave(valueOf(PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT), False));
//     Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVecInst = newVector;

//     streamSlaveIfcVecInst[0] = arbiterVec[0].slaveIfcVec[0];
//     streamSlaveIfcVecInst[1] = arbiterVec[0].slaveIfcVec[1];
//     streamSlaveIfcVecInst[2] = arbiterVec[1].slaveIfcVec[0];
//     streamSlaveIfcVecInst[3] = arbiterVec[1].slaveIfcVec[1];
//     // Since the read data pipeout doesn't come from arbiter, but from the cplt buffer, so only overwrite this interface
//     streamSlaveIfcVecInst[0].readPipeIfc.readDataPipeOut = cpltBufferVec[0].dataStreamPipeOut;
//     streamSlaveIfcVecInst[1].readPipeIfc.readDataPipeOut = cpltBufferVec[1].dataStreamPipeOut;
//     streamSlaveIfcVecInst[2].readPipeIfc.readDataPipeOut = cpltBufferVec[2].dataStreamPipeOut;
//     streamSlaveIfcVecInst[3].readPipeIfc.readDataPipeOut = cpltBufferVec[3].dataStreamPipeOut;

//     Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PcieRequestTlpHeaderGen) tlpHeaderGenVec <- replicateM(mkPcieRequestTlpHeaderGen);
//     let tlpHeaderAndDataCombinator <- mkTlpHeaderAndDataCombinator;

//     for (Integer idx = 0; idx < valueOf(TLP_HEADER_TX_ARBITTER_COUNT); idx = idx + 1) begin
//         mkConnection(arbiterVec[idx].masterIfc.writePipeIfc.writeMetaPipeOut, tlpHeaderGenVec[idx].dtldStreamSlavePipes.writePipeIfc.writeMetaPipeIn);
//         mkConnection(arbiterVec[idx].masterIfc.writePipeIfc.writeDataPipeOut, tlpHeaderGenVec[idx].dtldStreamSlavePipes.writePipeIfc.writeDataPipeIn);
//         mkConnection(arbiterVec[idx].masterIfc.readPipeIfc.readMetaPipeOut, tlpHeaderGenVec[idx].dtldStreamSlavePipes.readPipeIfc.readMetaPipeIn);
//         // read resp comes back out of order and handled by cplt buffer, so doesn't need go back through this arbiter.
//         // mkConnection(arbiterVec[idx].masterIfc.readPipeIfc.readDataPipeIn, tlpHeaderGenVec[idx].dtldStreamSlavePipes.readPipeIfc.readDataPipeOut);

//         mkConnection(arbiterVec[idx].writeSourceChannelIdPipeOut, tlpHeaderGenVec[idx].writeSourceChannelIdPipeIn);
//         mkConnection(arbiterVec[idx].readSourceChannelIdPipeOut, tlpHeaderGenVec[idx].readSourceChannelIdPipeIn);

//         mkConnection(tlpHeaderGenVec[idx].tagAllocPipeOutVec[0], cpltBufferVec[idx * 2 + 0].tagAllocPipeIn);
//         mkConnection(tlpHeaderGenVec[idx].tagAllocPipeOutVec[1], cpltBufferVec[idx * 2 + 1].tagAllocPipeIn);

//         mkConnection(cpltBufferVec[idx * 2 + 0].tagAllocPipeOut, tlpHeaderGenVec[idx].tagAllocPipeInVec[0]);
//         mkConnection(cpltBufferVec[idx * 2 + 1].tagAllocPipeOut, tlpHeaderGenVec[idx].tagAllocPipeInVec[1]);

//         mkConnection(tlpHeaderGenVec[idx].tlpHeaderBufferPipeOut, tlpHeaderAndDataCombinator.tlpHeaderBufferPipeInVec[idx]);
//         mkConnection(tlpHeaderGenVec[idx].tlpDataStreamPipeOut, tlpHeaderAndDataCombinator.tlpDataStreamPipeInVec[idx]);
//     end


//     for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_MAX_TLP_CNT); handlerIdx = handlerIdx + 1) begin
//         // mkConnection(pcieRxStreamSegmentFork.tlpDataStreamPipeOutVec[handlerIdx], rxTlpHandlerVec[handlerIdx].tlpDataStreamPipeIn);
//         // mkConnection(pcieRxStreamSegmentFork.tlpHeaderPipeOutVec[handlerIdx], rxTlpHandlerVec[handlerIdx].tlpHeaderPipeIn);

//         for (Integer channelIdx = 0; channelIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); channelIdx = channelIdx + 1) begin

//             // mkConnection(rxTlpHandlerVec[handlerIdx].tlpCpltDataStreamPipeOutVec[channelIdx], cpltBufferArbiterVec[channelIdx].dataStreamPipeInVec[handlerIdx]);
        
//             rule discardTlpHeader;
                
//                 rxTlpHandlerVec[handlerIdx].tlpCpltHeaderPipeOutVec[channelIdx].deq;
                
//             endrule
//         end
//     end


//     interface pcieRxPipeIn      = pcieRxStreamSegmentFork.pcieRxPipeIn;
//     interface streamSlaveIfcVec = streamSlaveIfcVecInst;
//     interface pcieTxPipeOut     = tlpHeaderAndDataCombinator.pcieTxPipeOut;
// endmodule



// interface RTilePcieWithRawIfc;
//     (* always_ready, always_enabled *)
//     interface RTilePcieAdaptorRx rxRawIfc;

//     (* always_ready, always_enabled *)
//     interface RTilePcieAdaptorTx txRawIfc;

//     interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVec;
// endinterface

// module mkRTilePcieWithRawIfc(RTilePcieWithRawIfc);
//     let inner <- mkRTilePcie;
//     let rawInterfaceAdaptor <- mkRTilePcieAdaptor;

//     mkConnection(rawInterfaceAdaptor.pcieRxPipeOut, inner.pcieRxPipeIn);
//     mkConnection(rawInterfaceAdaptor.pcieTxPipeIn, inner.pcieTxPipeOut);

//     interface rxRawIfc = rawInterfaceAdaptor.rx;
//     interface txRawIfc = rawInterfaceAdaptor.tx;
//     interface streamSlaveIfcVec = inner.streamSlaveIfcVec;
// endmodule