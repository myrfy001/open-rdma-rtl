import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import PcieTypes :: *;
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

typedef Bit#(TLog#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT)) DispatchChannelIdx;

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


typedef DtldStreamData#(DATA) RtilePcieUserStream;


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
typedef Bit#(TLog#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT)) RtilePcieUserChannelIdx;

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

(* synthesize *)
module mkPcieRxStreamSegmentFork(PcieRxStreamSegmentFork);
    FIFOF#(PcieRxBeat) pcieRxPipeInQueue <- mkFIFOF;
    FIFOF#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) memReadWriteReqTlpVecPipeOutQueue <- mkFIFOF;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpVecPipeOutVecInst = newVector;


    for (Integer handlerIdx = 0; handlerIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); handlerIdx = handlerIdx + 1) begin
        tlpRawBeatDataStorageWriteReqPipeOutVecInst[handlerIdx] = toPipeOut(tlpRawBeatDataStorageWriteReqPipeOutQueueVec[handlerIdx]);
        cpltTlpVecPipeOutVecInst[handlerIdx] = toPipeOut(cpltTlpPipeOutQueueVec[handlerIdx]);
    end

    Reg#(RtilePcieRxPayloadStorageAddr) storageWriteAddrReg <- mkReg(0);

    // Pipeline FIFOs
    FIFOF#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) dispatchTlpInfoPipelineQueue <- mkFIFOF;

    rule calcRxBeatMetaAndForkPayloadStorage;

        let beat = pcieRxPipeInQueue.first;
        pcieRxPipeInQueue.deq;

        for (Integer idx = 0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            tlpRawBeatDataStorageWriteReqPipeOutQueueVec[idx].enq(RtilePcieRxPayloadStorageWriteReq {
                addr: storageWriteAddrReg,
                dataBundles: beat.data
            });
        end
        storageWriteAddrReg <= storageWriteAddrReg + 1;


        Bool isSopFlagLegal = case (pack(beat.sop))
            'b0100, 'b1000, 'b1100, 'b1111: False;
            default: True;
        endcase;
        immAssert(
            isSopFlagLegal,
            "one of the following 2 assumption not hold: \n \
               1.The R-Tile PCIe IP does not use segment 2 and segment 3 if segment 0 AND segment 1 are unused \n\
               2.At most 3 TLPs in a beat\n",
            $format("beat=", fshow(beat))
        );


        Vector#(PCIE_MAX_TLP_CNT, Maybe#(PcieSegmentIdx)) tlpFirstSegmentIdxVec = case (pack(beat.sop)) matches
            'b0000: vec(tagged Invalid, tagged Invalid, tagged Invalid);
            'b0001: vec(tagged Valid 0, tagged Invalid, tagged Invalid);
            'b0010: vec(tagged Valid 1, tagged Invalid, tagged Invalid);
            'b0011: vec(tagged Valid 0, tagged Valid 1, tagged Invalid);
            'b0100: vec(tagged Valid 2, tagged Invalid, tagged Invalid);
            'b0101: vec(tagged Valid 0, tagged Valid 2, tagged Invalid);
            'b0110: vec(tagged Valid 1, tagged Valid 2, tagged Invalid);
            'b0111: vec(tagged Valid 0, tagged Valid 1, tagged Valid 2);
            'b1000: vec(tagged Valid 3, tagged Invalid, tagged Invalid);
            'b1001: vec(tagged Valid 0, tagged Valid 3, tagged Invalid);
            'b1010: vec(tagged Valid 1, tagged Valid 3, tagged Invalid);
            'b1011: vec(tagged Valid 0, tagged Valid 1, tagged Valid 3);
            'b1100: vec(tagged Valid 2, tagged Valid 3, tagged Invalid);
            'b1101: vec(tagged Valid 0, tagged Valid 2, tagged Valid 3);
            'b1110: vec(tagged Valid 1, tagged Valid 2, tagged Valid 3);
            'b1111: vec(tagged Invalid, tagged Invalid, tagged Invalid);
        endcase;
        
        Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) simpleTlpInfoVec = newVector;
        for (Integer idx = 0; idx < valueOf(PCIE_MAX_TLP_CNT); idx = idx + 1) begin
            if (tlpFirstSegmentIdxVec[idx] matches tagged Valid .segIdx) begin
                simpleTlpInfoVec[idx] = convertTlpToInternalDataType(beat.header[segIdx], storageWriteAddrReg, segIdx);
            end
            else begin
                simpleTlpInfoVec[idx] = tagged TlpTypeInvalid;
            end
        end

        dispatchTlpInfoPipelineQueue.enq(simpleTlpInfoVec);
        // $display(
        //     "time=%0t:", $time,
        //     ", tlpCnt=", fshow(tlpCnt),
        //     ", simpleTlpInfoVec=", fshow(simpleTlpInfoVec)
        // );

    endrule

    rule dispatchTlpHeader;
        let simpleTlpInfoVec = dispatchTlpInfoPipelineQueue.first;
        dispatchTlpInfoPipelineQueue.deq;

        Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) memRdWrTlpInfoVec = replicate(tagged TlpTypeInvalid);
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt))) cpltTlpInfoVec = replicate(replicate(tagged Invalid));

        Bool memRdWrHasTlp = False;
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) channelHasClptTlpVec = replicate(False);

        for (Integer tlpIdx = 0; tlpIdx < valueOf(PCIE_MAX_TLP_CNT); tlpIdx = tlpIdx + 1) begin
            case (simpleTlpInfoVec[tlpIdx]) matches
                tagged TlpTypeMrRead .tlp: begin
                    memRdWrTlpInfoVec[tlpIdx] = simpleTlpInfoVec[tlpIdx];
                    memRdWrHasTlp = True;
                end
                tagged TlpTypeMrWrite .tlp: begin
                    memRdWrTlpInfoVec[tlpIdx] = simpleTlpInfoVec[tlpIdx];
                    memRdWrHasTlp = True;
                end
                tagged TlpTypeCplt .tlp: begin
                    DispatchChannelIdx dispatchIdx = truncate(tlp.tag);
                    cpltTlpInfoVec[dispatchIdx][tlpIdx] = tagged Valid tlp;
                    channelHasClptTlpVec[dispatchIdx] = True;
                end
                default: begin
                    // Nothing to do
                end
            endcase
        end

        for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
            case ({pack(isValid(cpltTlpInfoVec[channelIdx][2])), pack(isValid(cpltTlpInfoVec[channelIdx][1])), pack(isValid(cpltTlpInfoVec[channelIdx][0]))})
                'b010: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][1], tagged Invalid, tagged Invalid);
                end
                'b100: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][2], tagged Invalid, tagged Invalid);
                end
                'b101: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][0], cpltTlpInfoVec[channelIdx][2], tagged Invalid);
                end
                'b110: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][1], cpltTlpInfoVec[channelIdx][2], tagged Invalid);
                end
                default: begin
                    // Nothing to do, since no order need to change.
                end
            endcase
        end


        case ({memRdWrTlpInfoVec[2] matches TlpTypeInvalid ? 1'b0 : 1'b1, memRdWrTlpInfoVec[1] matches TlpTypeInvalid ? 1'b0 : 1'b1, memRdWrTlpInfoVec[0] matches TlpTypeInvalid ? 1'b0 : 1'b1})
            'b010: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[1], tagged TlpTypeInvalid, tagged TlpTypeInvalid);
            end
            'b100: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[2], tagged TlpTypeInvalid, tagged TlpTypeInvalid);
            end
            'b101: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[0], memRdWrTlpInfoVec[2], tagged TlpTypeInvalid);
            end
            'b110: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[1], memRdWrTlpInfoVec[2], tagged TlpTypeInvalid);
            end
            default: begin
                // Nothing to do, since no order need to change.
            end
        endcase


    for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
        if (channelHasClptTlpVec[channelIdx]) begin
            cpltTlpPipeOutQueueVec[channelIdx].enq(cpltTlpInfoVec[channelIdx]);
        end
    end

    if (memRdWrHasTlp) begin
        memReadWriteReqTlpVecPipeOutQueue.enq(memRdWrTlpInfoVec);
    end

    endrule
    

    interface pcieRxPipeIn = toPipeIn(pcieRxPipeInQueue);
    interface tlpRawBeatDataStorageWriteReqPipeOutVec = tlpRawBeatDataStorageWriteReqPipeOutVecInst;
    interface cpltTlpVecPipeOutVec = cpltTlpVecPipeOutVecInst;
    interface memReadWriteReqTlpVecPipeOut = toPipeOut(memReadWriteReqTlpVecPipeOutQueue);
endmodule


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

typedef 4096                                                            PCIE_MRRS;
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
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotAllocReq)) slotAllocReqPipeInVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(void)) slotAllocRespPipeOutVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotDeAllocReq)) slotDeAllocPipeInVec;
endinterface

(* synthesize *)
module mkPcieHwCpltBufferAllocator(PcieHwCpltBufferAllocator);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotAllocReq))     slotAllocReqPipeInVecInst    = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(void))                                      slotAllocRespPipeOutVecInst  = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieSharedCompletionBufferSlotDeAllocReq))   slotDeAllocPipeInVecInst     = newVector;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(PcieSharedCompletionBufferSlotAllocReq))     tagAllocReqPipeInQueueVec    <- replicateM(mkFIFOF);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(void))                                       tagAllocRespPipeOutQueueVec  <- replicateM(mkFIFOF);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(PcieSharedCompletionBufferSlotDeAllocReq))   tagDeAllocPipeInQueueVec     <- replicateM(mkFIFOF);


    for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        slotAllocReqPipeInVecInst[idx]   = toPipeIn(tagAllocReqPipeInQueueVec[idx]);
        slotAllocRespPipeOutVecInst[idx] = toPipeOut(tagAllocRespPipeOutQueueVec[idx]);
        slotDeAllocPipeInVecInst[idx]    = toPipeIn(tagDeAllocPipeInQueueVec[idx]);
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

    interface slotAllocReqPipeInVec      = slotAllocReqPipeInVecInst;
    interface slotAllocRespPipeOutVec    = slotAllocRespPipeOutVecInst;
    interface slotDeAllocPipeInVec       = slotDeAllocPipeInVecInst;
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

    // InvalidByteNumInDw                  firstDwInvalidByteNum;
    // InvalidByteNumInDw                  lastDwInvalidByteNum;
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
    interface PipeIn#(PcieChannelPrivateCompletionBufferSlotAllocReq) tagAllocReqPipeIn;
    interface PipeOut#(PcieHeaderFieldExtendedTag) tagAllocRespPipeOut;
    interface PipeIn#(RtilePcieRxPayloadStorageWriteReq) tlpRawBeatDataStorageWriteReqPipeIn;
    interface PipeIn#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt))) cpltTlpVecPipeIn;
    interface PipeOut#(PcieSharedCompletionBufferSlotDeAllocReq) sharedHwCpltBufferSlotDeAllocReqPipeOut;
    interface PipeOut#(RtilePcieUserStream) dataStreamPipeOut;
    (* always_enabled, always_ready *)
    method Action setChannelIdx(RtilePcieUserChannelIdx idx);
endinterface

(* synthesize *)
module mkPcieCompletionBuffer(PcieCompletionBuffer);

    FIFOF#(PcieChannelPrivateCompletionBufferSlotAllocReq)              tagAllocReqPipeInQueue                          <- mkFIFOF;
    FIFOF#(PcieHeaderFieldExtendedTag)                                  tagAllocRespPipeOutQueue                        <- mkFIFOF;
    FIFOF#(RtilePcieRxPayloadStorageWriteReq)                           tlpRawBeatDataStorageWriteReqPipeInQueue        <- mkFIFOF;
    FIFOF#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))   cpltTlpVecPipeInQueue                           <- mkFIFOF;
    FIFOF#(PcieSharedCompletionBufferSlotDeAllocReq)                    sharedHwCpltBufferSlotDeAllocReqPipeOutQueue    <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)                                         dataStreamPipeOutQueue                          <- mkFIFOF;

    Wire#(RtilePcieUserChannelIdx) channelIdxWire <- mkBypassWire;
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
            let req = tagAllocReqPipeInQueue.first;
            tagAllocReqPipeInQueue.deq;

            let newSlot = PcieCompletionBufferTagSlotMeta {
                cpltTlpListStartAddr        : curCpltTlpBufferAddrToAllocReg,
                cpltTlpListCurWriteOffset   : 0,
                isCompleted                 : False,
                maxCpltTlpCntNeeded         : req.maxCpltTlpCntNeeded,
                hwClptBufDataSlotCntNeeded  : req.hwClptBufDataSlotCntNeeded
            };
            
            PcieHeaderFieldExtendedTag tag = unpack({pack(tagAllocHeadReg), pack(channelIdxWire)});
            slotMetaUpdateReqQueueForTagAlloc.enq(tuple2(tagAllocHeadReg, newSlot));

            tagAllocRespPipeOutQueue.enq(tag);

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

        let ds = RtilePcieUserStream {
            data: readOutBeat,
            byteNum: truncate(byteNum),
            startByteIdx: zeroExtend(fromInteger(valueOf(BYTE_CNT_PER_DWOED))-beatMeta.firstBeCnt),
            isFirst: isFirst,
            isLast: isLast
        };
        dataStreamPipeOutQueue.enq(ds);

        isOutputFirstBeatReg <= beatMeta.isLast;
    endrule

    interface tagAllocReqPipeIn                                 = toPipeIn(tagAllocReqPipeInQueue);
    interface tagAllocRespPipeOut                               = toPipeOut(tagAllocRespPipeOutQueue);
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

typedef DtldStreamBiDirSlavePipes#(DATA, ADDR, Length) PcieBiDirUserDataStreamPipes;

interface PcieRequestTlpHeaderGen;
    interface PcieBiDirUserDataStreamPipes                                      dtldStreamSlavePipes;
    interface PipeIn#(PcieTlpHeaderCompletion)                                  cpltTlpHeaderPipeIn;
    interface PipeIn#(RtilePcieUserStream)                                      cpltTlpDataStreamPipeIn;
    
    interface PipeOut#(PcieChannelPrivateCompletionBufferSlotAllocReq)          tagAllocReqPipeOut;
    interface PipeIn#(PcieHeaderFieldExtendedTag)                               tagAllocRespPipeIn;

    interface PipeOut#(PcieSharedCompletionBufferSlotAllocReq)                  slotAllocReqPipeOut;
    interface PipeIn#(void)                                                     slotAllocRespPipeIn;

    interface PipeOut#(PcieTlpHeaderBuffer)                                     tlpHeaderBufferPipeOut;
    interface PipeOut#(RtilePcieUserStream)                                     tlpDataStreamPipeOut;
endinterface

module mkPcieRequestTlpHeaderGen(PcieRequestTlpHeaderGen);


    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  slaveSideQueueWm         <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)                     slaveSideQueueWd         <- mkFIFOF;
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  slaveSideQueueRm         <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)                     slaveSideQueueRd         <- mkFIFOF;

    FIFOF#(RtilePcieUserStream)                     cpltTlpDataStreamPipeInQueue    <- mkFIFOF;

    FIFOF#(PcieHeaderFieldExtendedTag)                              tagAllocRespPipeInQueue  <- mkFIFOF;
    FIFOF#(PcieChannelPrivateCompletionBufferSlotAllocReq)          tagAllocReqPipeOutQueue <- mkFIFOF;

    FIFOF#(void)                                                    slotAllocRespPipeInQueue <- mkFIFOF;
    FIFOF#(PcieSharedCompletionBufferSlotAllocReq)                  slotAllocReqPipeOutQueue <- mkFIFOF;

    FIFOF#(PcieTlpHeaderMemoryRead4Dw)  readTlpQueue                <- mkFIFOF;
    FIFOF#(PcieTlpHeaderMemoryWrite4Dw) writeTlpQueue               <- mkFIFOF;
    FIFOF#(PcieTlpHeaderCompletion)     cpltTlpQueue                <- mkFIFOF;

    FIFOF#(PcieTlpHeaderBuffer)         arbittedTlpBufferQueue      <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)         arbittedTlpDataStreamQueue  <- mkFIFOF;
    Reg#(Bool)                          isOutputingPayloadStreamReg <- mkReg(False);

    
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  tagAllocToReadTlpGenPipelineQ         <- mkFIFOF;

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

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen genTlpMwr"),
        //     toBlue(", wm="), fshow(wm),
        //     toBlue(", startDwordAddr="), fshow(startDwordAddr),
        //     toBlue(", endDwordAddr="), fshow(endDwordAddr),
        //     toBlue(", lengthInDw="), fshow(lengthInDw),
        //     toBlue(", firstDwBe="), fshow(firstDwBe),
        //     toBlue(", lastDwBe="), fshow(lastDwBe),
        //     toBlue(", tlp="), fshow(tlp)
        // );


    endrule
    

    rule sendGenPcieTagReq;
        let rm = slaveSideQueueRm.first;
        slaveSideQueueRm.deq;

        ADDR endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1; 

        let hwClptBufDataSlotCntNeeded = pack(rm.totalLen) >> valueOf(TLog#(PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT));
        let maxCpltTlpCntNeeded        = 1 + (pack(rm.totalLen) >> valueOf(TLog#(PCIE_RCB)));

        let tagAllocReq = PcieChannelPrivateCompletionBufferSlotAllocReq {
            // firstDwInvalidByteNum       : truncate(pack(rm.addr)),
            // lastDwInvalidByteNum        : maxBound - truncate(pack(endAddr)),
            hwClptBufDataSlotCntNeeded  : truncate(hwClptBufDataSlotCntNeeded),
            maxCpltTlpCntNeeded         : truncate(maxCpltTlpCntNeeded)
        };

        let slotAllocReq = PcieSharedCompletionBufferSlotAllocReq {
            headerSlotCnt   : truncate(hwClptBufDataSlotCntNeeded),
            dataSlotCnt     : truncate(maxCpltTlpCntNeeded)
        };

        tagAllocReqPipeOutQueue.enq(tagAllocReq);
        slotAllocReqPipeOutQueue.enq(slotAllocReq);
        tagAllocToReadTlpGenPipelineQ.enq(rm);
    endrule

    rule genTlpMrd;
        
        let rm = tagAllocToReadTlpGenPipelineQ.first;
        tagAllocToReadTlpGenPipelineQ.deq;

        let tag = tagAllocRespPipeInQueue.first;
        tagAllocRespPipeInQueue.deq;

        slotAllocRespPipeInQueue.deq;

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
        // for cplt, it will affect the waiting time of the software, and there is few cplt packet, so it has the lowest priority.
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
        else if (readTlpQueue.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(readTlpQueue.first)));
            readTlpQueue.deq;

            // generate a fake only stream for the payload and header merge.
            let ds = DtldStreamData {
                data        : unpack(0),
                byteNum     : unpack(0),
                startByteIdx: unpack(0),
                isFirst     : True,
                isLast      : True
            };
            arbittedTlpDataStreamQueue.enq(ds);
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
        
    endrule

    rule arbitOutputDataStream if (isOutputingPayloadStreamReg);
        let ds = slaveSideQueueWd.first;
        slaveSideQueueWd.deq;
        arbittedTlpDataStreamQueue.enq(ds);
        if (ds.isLast) begin
            isOutputingPayloadStreamReg <= False;
        end
    endrule


    interface DtldStreamBiDirSlavePipes dtldStreamSlavePipes;
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

    interface tagAllocReqPipeOut            = toPipeOut(tagAllocReqPipeOutQueue);
    interface tagAllocRespPipeIn            = toPipeIn(tagAllocRespPipeInQueue);

    interface slotAllocReqPipeOut           = toPipeOut(slotAllocReqPipeOutQueue);
    interface slotAllocRespPipeIn           = toPipeIn(slotAllocRespPipeInQueue);
    
    interface cpltTlpHeaderPipeIn           = toPipeIn(cpltTlpQueue);
    interface tlpHeaderBufferPipeOut        = toPipeOut(arbittedTlpBufferQueue);
    interface tlpDataStreamPipeOut          = toPipeOut(arbittedTlpDataStreamQueue);
endmodule






typedef 2                                                   RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT))    RtilePcieTxPingPongChannelIdx;
typedef TLog#(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) RTILE_PCIE_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM;

typedef 256 RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH;  // each row of the buffer stores a double-width-seg
typedef TLog#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH) RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH;
typedef Bit#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH) RtilePcieTxChannelBufferAddr;


// Since the Tx interface only allow new TLP start on it's first and third segment, we can think for the TX path, there are two virtual 
// DOUBLE-WIDTH-SEGMENT in one beat, each double-width-segment is 512 bit in width. so we will mainly focus on handling the double-width-segment
typedef 2 PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG;
typedef Bit#(TLog#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG))                               RtilePcieTxSegIdxInDoubleWidthSeg;
typedef Bit#(TAdd#(1, TLog#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)))                     RtilePcieTxSegCntInDoubleWidthSeg;

typedef TMul#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, PCIE_TLP_DATA_SEGMENT_WIDTH)            RTILE_PCIE_TX_DATA_DOUBLE_WIDTH_SEGMENT_WIDTH;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, RTILE_PCIE_TX_DATA_DOUBLE_WIDTH_SEGMENT_WIDTH)    RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_CNT_PER_USER_INPUT_BEAT; // ?
typedef TLog#(RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_CNT_PER_USER_INPUT_BEAT)                       RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH;
typedef Bit#(RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH)                      RtilePcieTxChannelBufferRowDoubleWidthSegIdx;
typedef RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH                            RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET;

typedef TAdd#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH, RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH)    RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DOUBLE_WIDTH_SEG_ADDR_WIDTH;
// The higher part of RtilePcieTxChannelBufferSegAddr is the row address in storage, and the lower part is the seg index in the double-width-seg.
typedef Bit#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DOUBLE_WIDTH_SEG_ADDR_WIDTH)                                              RtilePcieTxChannelBufferSegAddr;
typedef RtilePcieTxChannelBufferSegAddr                                                                                         RtilePcieTxChannelBufferSegCnt;  // infact, we can redefine it to a shorter type to just hold a 4kB packte and addtional header part.

// input DATA is buffered in a BRAM, each BRAM row has an address, and we further divide one row into segemnts, and give each segment and index.
// in this way, the higher part of the address is BRAM row address, and the lower part of the address is the segment index inside a row;
typedef TDiv#(SizeOf#(DATA), PCIE_TLP_DATA_SEGMENT_WIDTH)               RTILE_PCIE_TX_SEG_CNT_PER_USER_INPUT_BEAT;
typedef TMax#(1, TLog#(RTILE_PCIE_TX_SEG_CNT_PER_USER_INPUT_BEAT))      RTILE_PCIE_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH;
typedef Bit#(RTILE_PCIE_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH)               RtilePcieTxChannelBufferRowSegIdx;
typedef TLog#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)                     RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET;

typedef struct {
    RtilePcieTxChannelBufferSegAddr             startSegAddr;
    RtilePcieTxChannelBufferSegCnt              segCnt;
    Bool                                        isStorageRowCountSmall;  // To improve timing
} RtilePcieTxBufferRange deriving(Bits, FShow);

typedef struct {
    RtilePcieUserChannelIdx                         srcChannelIdx;                  // 2
    RtilePcieTxChannelBufferSegAddr                 startSegAddr;                   // 9
    RtilePcieTxChannelBufferSegCnt                  segCnt;                         // 9
    Bool                                            isStorageRowCountSmall;         // 1
    ReservedZero#(11)                               reserved;                       // make this struct's size is power of two, or the MIMO FIFO will use dsp block to implement multiply operation. cause very bad timing.
} RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset deriving(Bits, FShow);

typedef struct {
    RtilePcieUserChannelIdx             srcChannelIdx;
    RtilePcieTxChannelBufferAddr        startRowAddr;
    PcieSegmentIdx                      zeroBasedSegCnt;
    Bool                                isFirst;
    Bool                                isLast;
    // Bool                                isOutputBeatLast;
} RtilePcieTxPingPongChannelMetaEntry deriving(Bits, FShow);


interface RtilePcieTxUserInputGearboxStorageAndMetaExtractor;
    interface PipeIn#(RtilePcieUserStream)                          streamPipeIn;
    interface PipeIn#(PcieTlpHeaderBuffer)                          txTlpHeaderBufferPipeIn;
    interface PipeOut#(RtilePcieTxBufferRange)                      packetMetaPipeOut;

    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeIn#(RtilePcieTxBramBufferReadReq))  bramReadReqPipeInVec;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA)))  bramReadRespPipeOutVec;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(PcieTlpHeaderBuffer))  bramTlpHeaderReadRespPipeOutVec;
endinterface

// (* synthesize *)
module mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor(RtilePcieTxUserInputGearboxStorageAndMetaExtractor);
    FIFOF#(RtilePcieUserStream)                     streamPipeInQueue               <- mkFIFOF;
    FIFOF#(PcieTlpHeaderBuffer)                     txTlpHeaderBufferPipeInQueue    <- mkFIFOF;
    FIFOF#(RtilePcieTxBufferRange)                  packetMetaPipeOutQueue          <- mkFIFOF;

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeIn#(RtilePcieTxBramBufferReadReq)) bramReadReqPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(RtilePcieTxBramBufferReadReq)) bramReadReqPipeInQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA))) bramReadRespPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA))) bramReadRespPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(PcieTlpHeaderBuffer)) bramTlpHeaderReadRespPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(PcieTlpHeaderBuffer)) bramTlpHeaderReadRespPipeOutQueueVec <- replicateM(mkFIFOF);
    
    for (Integer idx=0; idx < valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG); idx = idx + 1) begin
        bramReadReqPipeInVecInst[idx]               = toPipeIn(bramReadReqPipeInQueueVec[idx]);
        bramReadRespPipeOutVecInst[idx]             = toPipeOut(bramReadRespPipeOutQueueVec[idx]);
        bramTlpHeaderReadRespPipeOutVecInst[idx]    = toPipeOut(bramTlpHeaderReadRespPipeOutQueueVec[idx]);
    end

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, 
            Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, 
                    AutoInferBramQueuedOutput#(RtilePcieTxChannelBufferAddr, DATA)))  dataStreamStorageVec  <- replicateM(replicateM(mkAutoInferBramQueuedOutput(False, "")));

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, 
            AutoInferBramQueuedOutput#(RtilePcieTxChannelBufferAddr, PcieTlpHeaderBuffer))  tlpHeaderStorageVec  <- replicateM(mkAutoInferBramQueuedOutput(False, ""));

    Reg#(RtilePcieTxChannelBufferAddr)      curRowAddrReg               <- mkReg(0);
    Reg#(RtilePcieTxChannelBufferAddr)      startRowAddrReg             <- mkReg(0);
    Reg#(RtilePcieTxChannelBufferSegCnt)    curSegCntReg                <- mkReg(0);
    Reg#(Bool)                              isFirstReg                  <- mkReg(True);

    // rule debug;
    //     if (!streamPipeInQueue.notFull) begin
    //         $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug"),  toBlue(", streamPipeInQueue is Full"));
    //     end

    //     if (!packetMetaPipeOutQueue.notFull) begin
    //         $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug"),  toBlue(", packetMetaPipeOutQueue is Full"));
    //     end
    //     for (Integer idx=0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
    //         if (!bramReadReqPipeInQueueVec[idx].notFull) begin
    //             $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug [idx=%d]"), idx, toBlue(", bramReadReqPipeInQueueVec is Full"));
    //         end
    //         if (!bramReadRespPipeOutQueueVec[idx].notFull) begin
    //             $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug [idx=%d]"), idx, toBlue(", bramReadRespPipeOutQueueVec is Full"));
    //         end
    //     end
    // endrule


    for (Integer idx=0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        rule handleStorageReadReq;
            let req = bramReadReqPipeInQueueVec[idx].first;
            bramReadReqPipeInQueueVec[idx].deq;
            for (Integer segIdx = 0; segIdx < valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG); segIdx = segIdx + 1) begin
                dataStreamStorageVec[idx][segIdx].putReadReq(req.addr);
            end
            if (req.needReadTlpBuffer) begin
                tlpHeaderStorageVec[idx].putReadReq(req.addr);
            end
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handleStorageReadReq [idx=%d]"), idx,
            //     toBlue(", req="), fshow(req)
            // );
        endrule

        rule handlePayloadStorageReadResp;
            Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA) outputVec = newVector;
            for (Integer segIdx = 0; segIdx < valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG); segIdx = segIdx + 1) begin
                outputVec[segIdx] = dataStreamStorageVec[idx][segIdx].readRespPipeOut.first;
                dataStreamStorageVec[idx][segIdx].readRespPipeOut.deq;
            end

            bramReadRespPipeOutQueueVec[idx].enq(outputVec);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handlePayloadStorageReadResp [idx=%d]"), idx,
            //     toBlue(", outputVec="), fshow(outputVec)
            // );
        endrule

        rule handleTlpStorageReadResp;
            let resp = tlpHeaderStorageVec[idx].readRespPipeOut.first;
            tlpHeaderStorageVec[idx].readRespPipeOut.deq;
            bramTlpHeaderReadRespPipeOutQueueVec[idx].enq(resp);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handleTlpStorageReadResp [idx=%d]"), idx,
            //     toBlue(", resp="), fshow(resp)
            // );
        endrule
    end

    rule handleMetaCalc;
        let ds = streamPipeInQueue.first;
        streamPipeInQueue.deq;

        let                                 curSegCnt               = curSegCntReg;
        RtilePcieTxSegIdxInDoubleWidthSeg   curIdxInDoubleWidthSeg  = truncate(curSegCnt);

        let newSegCnt = curSegCnt + fromInteger(valueOf(RTILE_PCIE_TX_SEG_CNT_PER_USER_INPUT_BEAT));
        let nextBeatRowAddr = lsb(curSegCnt) == 1 ? curRowAddrReg + 1 : curRowAddrReg;

        if (ds.isLast) begin

            // let zeroBasedByteNum = ds.byteNum - 1;
            // RtilePcieEopEmpty byteNumLowerBits = truncate(zeroBasedByteNum);

            let outputEntry = RtilePcieTxBufferRange {
                startSegAddr: zeroExtend(startRowAddrReg) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET),
                segCnt: newSegCnt,
                isStorageRowCountSmall: (curSegCnt >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT))
                // eopEmpty: fromInteger(valueOf(RTILE_PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH)-1) - byteNumLowerBits
            };
            packetMetaPipeOutQueue.enq(outputEntry);
            newSegCnt = 0;

            startRowAddrReg <=  curRowAddrReg + 1;
            nextBeatRowAddr =   curRowAddrReg + 1;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handleMetaCalc"),
            //     toBlue(", outputEntry="), fshow(outputEntry)
            // );
        end

        for (Integer idx = 0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx][curIdxInDoubleWidthSeg].write(curRowAddrReg, ds.data);
        end

        if (isFirstReg) begin
            let tlpHeaderBuf = txTlpHeaderBufferPipeInQueue.first;
            txTlpHeaderBufferPipeInQueue.deq;
            for (Integer idx = 0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
                tlpHeaderStorageVec[idx].write(curRowAddrReg, tlpHeaderBuf);
            end
        end

        

        curSegCntReg  <= newSegCnt;
        curRowAddrReg <= nextBeatRowAddr;
        isFirstReg <= ds.isLast;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handleMetaCalc BRAMwrite"),
        //     toBlue(", curRowAddrReg="), fshow(curRowAddrReg),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface streamPipeIn                      = toPipeIn(streamPipeInQueue);
    interface txTlpHeaderBufferPipeIn           = toPipeIn(txTlpHeaderBufferPipeInQueue);
    interface packetMetaPipeOut                 = toPipeOut(packetMetaPipeOutQueue);
    interface bramReadReqPipeInVec              = bramReadReqPipeInVecInst;
    interface bramTlpHeaderReadRespPipeOutVec   = bramTlpHeaderReadRespPipeOutVecInst;
    interface bramReadRespPipeOutVec            = bramReadRespPipeOutVecInst;
endmodule


typedef 2 RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT;  // from user guide, new tlp can only start on seg 0 and 2, so max two new packet per beat.
typedef 2 RTILE_PCIE_TX_MAX_PACKET_PER_BEAT;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, RTILE_PCIE_TX_DATA_DOUBLE_WIDTH_SEGMENT_WIDTH) RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT;  // 2
typedef Bit#(TLog#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT)) RtilePcieTxOutputBeatNewPacketIndex;

typedef Bit#(TLog#(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) RtilePcieTxBramRowIndexInOutputBeat;
typedef TAdd#(1, TLog#(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_WIDTH;
typedef TAdd#(1, RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_WIDTH) RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_SUM_RESULT_WIDTH;
typedef Bit#(RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_WIDTH) RtilePcieTxSmallBramRowCnt;
typedef Bit#(RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_SUM_RESULT_WIDTH) RtilePcieTxSmallBramRowCntSumResult;


typedef Vector#(RTILE_PCIE_TX_MAX_PACKET_PER_BEAT, Maybe#(RtilePcieTxPingPongChannelMetaEntry)) RtilePcieTxPingPongChannelMetaBundle;

interface RtilePcieTxPingPongFork;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(RtilePcieTxBufferRange)) packetMetaPipeInVec;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(RtilePcieTxPingPongChannelMetaBundle))  pingpongChannelMetaPipeOutVec;

endinterface

(* synthesize *)
module mkRtilePcieTxPingPongFork(RtilePcieTxPingPongFork);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(RtilePcieTxBufferRange)) packetMetaPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(RtilePcieTxBufferRange)) packetMetaPipeInQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(RtilePcieTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(RtilePcieTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    

    for (Integer idx=0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        packetMetaPipeInVecInst[idx] = toPipeIn(packetMetaPipeInQueueVec[idx]);
    end

    for (Integer idx=0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongChannelMetaPipeOutVecInst[idx] = toPipeOut(pingpongChannelMetaPipeOutQueueVec[idx]);
    end


    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Reg#(Maybe#(RtilePcieTxBufferRange))) curDataRangeRegVec <- replicateM(mkReg(tagged Invalid));
    Reg#(RtilePcieUserChannelIdx)       curInputRoundRobinIdxReg <- mkReg(0);
    Reg#(RtilePcieTxPingPongChannelIdx) curOutputRoundRobinIdxReg <- mkReg(0);
    // Reg#(RtilePcieTxChannelBufferRowSegIdx) prevDestSegOffsetReg <- mkReg(0);

    let mimoCfg = MIMOConfiguration {
        unguarded: False,
        bram_based: False
    };
    MIMO#(
        RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT,
            RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT,
            TMul#(2, RTILE_PCIE_USER_LOGIC_CHANNEL_CNT),
            RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset
    ) selectedInputChannelMetaMIMO <- mkMIMO(mimoCfg);
    

    Reg#(Maybe#(RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) curMetaMaybeReg <- mkReg(tagged Invalid);
    Reg#(Bool) isFirstReg <- mkReg(True);

    // Pipeline Queues
    FIFOF#(Tuple2#(
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset),
        LUInt#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT)
    ))  mimoInputPipelineQueue <- mkLFIFOF;

    FIFOF#(Tuple2#(RtilePcieTxPingPongChannelIdx, RtilePcieTxPingPongChannelMetaBundle)) outputTimingFixPipelineQueue <- mkLFIFOF;

    rule guard;
        immAssert(
            valueOf(SizeOf#(RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) == valueOf(TExp#(TLog#(SizeOf#(RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset)))),
            "the size of RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset must be 2's power",
            $format("")
        );
    endrule

    rule prepareRoundRobinChannelOrder;
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset) vecToEnq = newVector;
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) needDeqFlagVec = replicate(False);
        let curInputRoundRobinIdx = curInputRoundRobinIdxReg;
        // let prevDestSegOffset = prevDestSegOffsetReg;
        let enqCnt = 0;
        case ({ pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].notEmpty)
            }) matches
            4'b0000: begin
            end
            4'b0001: begin
                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 1;
            end
            4'b0010: begin
                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty, 
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 1;
            end
            4'b0011: begin
                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    // eopEmpty        : inMeta1.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b0100: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall, 
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 1;
            end
            4'b0101: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    // eopEmpty        : inMeta1.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b011?: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    // eopEmpty        : inMeta1.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b1000: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty, 
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 1;
                enqCnt = 1;
            end
            4'b1001: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    // eopEmpty        : inMeta1.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b101?: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    // eopEmpty        : inMeta1.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b11??: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    // eopEmpty        : inMeta0.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    // eopEmpty        : inMeta1.eopEmpty,
                    // destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 2;
            end
        endcase

        
        // IMPORTANT!!!!
        // since MIMO's enq doesn't have guard (infact, it has guard, but the guard only check if it can enq at least one element), to make sure 
        // there are enough space for `enqCnt`, we can't relay on enq's guard to block the rule from being fired.
        // so, we need to move all the "Actions"(i.e., code that will change the state) into the following IF block. And only leave combinational logic
        // out of the IF block
        if (enqCnt != 0 && selectedInputChannelMetaMIMO.enqReadyN(enqCnt)) begin
            curInputRoundRobinIdxReg <= curInputRoundRobinIdx;
            // prevDestSegOffsetReg <= prevDestSegOffset;

            if (needDeqFlagVec[0] == True) begin
                packetMetaPipeInQueueVec[0].deq;
            end
            if (needDeqFlagVec[1] == True) begin
                packetMetaPipeInQueueVec[1].deq;
            end
            if (needDeqFlagVec[2] == True) begin
                packetMetaPipeInQueueVec[2].deq;
            end
            if (needDeqFlagVec[3] == True) begin
                packetMetaPipeInQueueVec[3].deq;
            end

            selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork prepareRoundRobinChannelOrder"),
            //     toBlue(", enqCnt="), fshow(enqCnt),
            //     toBlue(", vecToEnq="), fshow(vecToEnq)
            // );
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


    rule dispatch;
        RtilePcieTxPingPongChannelMetaBundle outputMetaBundle = replicate(tagged Invalid);

        if (curMetaMaybeReg matches tagged Valid .curMeta) begin

            let onePacketMetaAvailable      = True;
            let twoPacketMetaAvailable      = selectedInputChannelMetaMIMO.deqReadyN(1);

            let packetOneMeta   = curMeta;
            let packetTwoMeta   = twoPacketMetaAvailable ? selectedInputChannelMetaMIMO.first[0] : ?;

            RtilePcieTxSmallBramRowCnt packetOneSmallBramRowCnt   = truncate((packetOneMeta.segCnt - 1) >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;
            RtilePcieTxSmallBramRowCnt packetTwoSmallBramRowCnt   = truncate((packetTwoMeta.segCnt - 1)  >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;

            RtilePcieTxSmallBramRowCntSumResult onePacketSmallBramRowCntSum   =                               zeroExtend(packetOneSmallBramRowCnt);
            RtilePcieTxSmallBramRowCntSumResult twoPacketSmallBramRowCntSum   = onePacketSmallBramRowCntSum + zeroExtend(packetTwoSmallBramRowCnt);

            let packetOneWillEndInThisBeat   = packetOneMeta.isStorageRowCountSmall   && onePacketSmallBramRowCntSum   <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            let packetTwoWillEndInThisBeat   = packetTwoMeta.isStorageRowCountSmall   && twoPacketSmallBramRowCntSum   <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            
            let beatWillHoldOnePacket   = onePacketMetaAvailable;
            let beatWillHoldTwoPacket   = twoPacketMetaAvailable   && packetOneMeta.isStorageRowCountSmall && onePacketSmallBramRowCntSum < fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));

            RtilePcieTxSmallBramRowCnt smallStorgeRowCntLeftForPacketOne     = fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            RtilePcieTxSmallBramRowCnt smallStorgeRowCntLeftForPacketTwo     = fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) - truncate(onePacketSmallBramRowCntSum);

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch"),
            //     toBlue(", beatWillHoldPacket="), fshow(beatWillHoldTwoPacket ? 2 : 1),
            //     toBlue(", packetOneSmallBramRowCnt="), fshow(packetOneSmallBramRowCnt),
            //     toBlue(", packetTwoSmallBramRowCnt="), fshow(packetTwoSmallBramRowCnt),
            //     toBlue(", onePacketSmallBramRowCntSum="), fshow(onePacketSmallBramRowCntSum),
            //     toBlue(", twoPacketSmallBramRowCntSum="), fshow(twoPacketSmallBramRowCntSum),
            //     toBlue(", smallStorgeRowCntLeftForPacketOne="), fshow(smallStorgeRowCntLeftForPacketOne),
            //     toBlue(", smallStorgeRowCntLeftForPacketTwo="), fshow(smallStorgeRowCntLeftForPacketTwo)
            // );

            if (beatWillHoldTwoPacket) begin
                outputMetaBundle[0] = tagged Valid RtilePcieTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetOneMeta.segCnt-1),
                    isFirst         : isFirstReg,        
                    isLast          : True
                };
                outputMetaBundle[1] = tagged Valid RtilePcieTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetTwoMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetTwoMeta.startSegAddr),
                    zeroBasedSegCnt : packetTwoWillEndInThisBeat ? truncate(packetTwoMeta.segCnt-1) : ((zeroExtend(smallStorgeRowCntLeftForPacketTwo) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    // eopEmpty        : packetTwoMeta.eopEmpty,
                    // destSegOffset   : ?,
                    isFirst         : True,
                    isLast          : packetTwoWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                if (isFirstReg)

                immAssert(selectedInputChannelMetaMIMO.deqReadyN(1), "MIMO Queue doesn't have enough element", $format(""));
                selectedInputChannelMetaMIMO.deq(1);

                if (packetTwoWillEndInThisBeat) begin
                    curMetaMaybeReg <= tagged Invalid;
                    isFirstReg <= True;
                end
                else begin
                    let nextCurMeta                     = packetTwoMeta;
                    let segCntDelta                     = zeroExtend(smallStorgeRowCntLeftForPacketTwo) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET);
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg                     <= tagged Valid nextCurMeta;
                    isFirstReg                          <= False;
                end
            end
            else if (beatWillHoldOnePacket) begin
                outputMetaBundle[0] = tagged Valid RtilePcieTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : packetOneWillEndInThisBeat ? truncate(packetOneMeta.segCnt - 1) : ((zeroExtend(smallStorgeRowCntLeftForPacketOne) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    isFirst         : isFirstReg,
                    isLast          : packetOneWillEndInThisBeat
                };

                if (packetOneWillEndInThisBeat) begin
                    if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                        curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                        selectedInputChannelMetaMIMO.deq(1);
                    end
                    else begin
                        curMetaMaybeReg <= tagged Invalid;
                    end
                    isFirstReg <= True;
                end
                else begin
                    let nextCurMeta                     = packetOneMeta;
                    let segCntDelta                     = fromInteger(valueOf(PCIE_SEGMENT_CNT));
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg                     <= tagged Valid nextCurMeta;
                    isFirstReg                          <= False;
                end
            end
            else begin
                immFail("should not reach here", $format(""));
            end

            outputTimingFixPipelineQueue.enq(tuple2(curOutputRoundRobinIdxReg, outputMetaBundle));
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch final output"),
            //     toBlue(", curOutputRoundRobinIdxReg="), fshow(curOutputRoundRobinIdxReg),
            //     toBlue(", outputMetaBundle="), fshow(outputMetaBundle)
            // );

            curOutputRoundRobinIdxReg <= curOutputRoundRobinIdxReg + 1;
        end
        else begin
            if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                selectedInputChannelMetaMIMO.deq(1);
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch IDLE"),
                //     toBlue(", selectedInputChannelMetaMIMO.first[0]="), fshow(selectedInputChannelMetaMIMO.first[0])
                // );
            end
            else begin
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch IDLE and not new packet")
                // );
            end
        end
    endrule

    rule forwardOutput;
        let {curOutputRoundRobinIdx, outputMetaBundle} = outputTimingFixPipelineQueue.first;
        outputTimingFixPipelineQueue.deq;
        pingpongChannelMetaPipeOutQueueVec[curOutputRoundRobinIdx].enq(outputMetaBundle);
    endrule

    
    interface packetMetaPipeInVec = packetMetaPipeInVecInst;
    interface pingpongChannelMetaPipeOutVec = pingpongChannelMetaPipeOutVecInst;
endmodule



typedef struct {
    RtilePcieTxChannelBufferAddr    addr;
    Bool                            needReadTlpBuffer;
} RtilePcieTxBramBufferReadReq deriving (FShow, Bits);

typedef struct {
    RtilePcieUserChannelIdx             srcChannelIdx;
    RtilePcieTxChannelBufferRowSegIdx   zeroBasedValidSegCnt;
    Bool                                isFirst;
    Bool                                isLast;
    Bool                                isOutputBeatLast;
} RtilePcieTxPingPongChannelBramReadPipelineEntry deriving (FShow, Bits);


typedef struct {
    PcieTlpDataBusSegBundle             dataBuf;
    PcieTlpHeaderBusSegBundle           header;
    SopSignalBundle                     sop;
    EopSignalBundle                     eop;
    HvalidSignalBundle                  hvalid;
    DvalidSignalBundle                  dvalid;
} RtilePcieTxPingPongChannelOutputEntry deriving (FShow, Bits);

interface RtilePcieTxPingPongSingleChannel;
    interface PipeIn#(RtilePcieTxPingPongChannelMetaBundle)      metaPipeIn;
    interface PipeOut#(RtilePcieTxPingPongChannelOutputEntry)    beatPipeOut;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieTxBramBufferReadReq))  bramReadReqPipeOutVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieTlpHeaderBuffer))    bramTlpHeaderReadRespPipeInVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA)))    bramReadRespPipeInVec;
endinterface

(* synthesize *)
module mkRtilePcieTxPingPongSingleChannel(RtilePcieTxPingPongSingleChannel);
    FIFOF#(RtilePcieTxPingPongChannelMetaBundle)  metaPipeInQueue       <- mkFIFOF;
    FIFOF#(RtilePcieTxPingPongChannelOutputEntry) beatPipeOutQueue      <- mkFIFOF;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieTxBramBufferReadReq))  bramReadReqPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(RtilePcieTxBramBufferReadReq))    bramReadReqPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA)))   bramReadRespPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA)))    bramReadRespPipeInQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeIn#(PcieTlpHeaderBuffer))   bramTlpHeaderReadRespPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(PcieTlpHeaderBuffer))    bramTlpHeaderReadRespPipeInQueueVec <- replicateM(mkFIFOF);

    for (Integer idx=0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        bramReadReqPipeOutVecInst[idx]          = toPipeOut(bramReadReqPipeOutQueueVec[idx]);
        bramReadRespPipeInVecInst[idx]          = toPipeIn(bramReadRespPipeInQueueVec[idx]);
        bramTlpHeaderReadRespPipeInVecInst[idx] = toPipeIn(bramTlpHeaderReadRespPipeInQueueVec[idx]);
    end

    
    Reg#(Maybe#(RtilePcieTxPingPongChannelMetaEntry)) curMetaEntryMaybeReg <- mkReg(tagged Invalid);
    Reg#(RtilePcieTxPingPongChannelMetaBundle) curInputMetaBundleReg <- mkRegU;

    Reg#(RtilePcieTxBramRowIndexInOutputBeat) outputBeatEmptyStorageRowCntReg <- mkReg(fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)-1));


    Reg#(RtilePcieTxPingPongChannelOutputEntry) outputEntryReg <- mkReg(unpack(0));

    // Pipeline FIFOs
    FIFOF#(RtilePcieTxPingPongChannelBramReadPipelineEntry) bramReadPipelineQueue <- mkSizedFIFOF(8);
    FIFOF#(Tuple2#(RtilePcieTxBramRowIndexInOutputBeat, RtilePcieTxPingPongChannelOutputEntry))  finalShiftPipelineQueue <- mkLFIFOF;

    rule sendBramReadReq;
        let zeroBasedValidSegCnt = ?;

        if (curMetaEntryMaybeReg matches tagged Valid .curMetaEntry) begin
            let metaBundle = metaPipeInQueue.first;

            let isCurMetaEntryLast = (curMetaEntry.zeroBasedSegCnt <= fromInteger(valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)-1));
            let isPacketLast = isCurMetaEntryLast && curMetaEntry.isLast;
            let haveNextValidPacketMeta = isValid(curInputMetaBundleReg[0]);
            let isOutputBeatLast = isCurMetaEntryLast && !haveNextValidPacketMeta;

            if (!isPacketLast) begin
                zeroBasedValidSegCnt = fromInteger(valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)-1);
            end
            else begin
                zeroBasedValidSegCnt = truncate(curMetaEntry.zeroBasedSegCnt);
            end


            bramReadReqPipeOutQueueVec[curMetaEntry.srcChannelIdx].enq(RtilePcieTxBramBufferReadReq{
                addr                : curMetaEntry.startRowAddr,
                needReadTlpBuffer   : curMetaEntry.isFirst
            });

            bramReadPipelineQueue.enq(RtilePcieTxPingPongChannelBramReadPipelineEntry {
                srcChannelIdx       : curMetaEntry.srcChannelIdx,
                zeroBasedValidSegCnt: zeroBasedValidSegCnt,
                isFirst             : curMetaEntry.isFirst,
                isLast              : isPacketLast,
                isOutputBeatLast    : isOutputBeatLast
            });

            let nextCurMetaEntryMaybe;
            if (!isCurMetaEntryLast) begin
                let nextCurMetaEntry = curMetaEntry;
                nextCurMetaEntry.zeroBasedSegCnt = nextCurMetaEntry.zeroBasedSegCnt - fromInteger(valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG));
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
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel sendBramReadReq IDLE"),
            //     toBlue(", metaPipeInQueue.first="), fshow(metaPipeInQueue.first)
            // );
        end
    endrule


    rule handleBramReadRespAndMergeHeader;
        let bramReadBeatMeta = bramReadPipelineQueue.first;
        bramReadPipelineQueue.deq;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel handleBramReadRespAndMergeHeader"),
        //     toBlue(", bramReadBeatMeta="), fshow(bramReadBeatMeta)
        // );

        let readResp = bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].first;
        bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].deq;

        let outputEntry                     = outputEntryReg;
        let outputBeatEmptyStorageRowCnt    = outputBeatEmptyStorageRowCntReg;

        Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, PcieTlpDataSegment) readRespAsSegBundle = unpack(pack(readResp));
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[1]);


        let tlpHasPayload = True;
        if (bramReadBeatMeta.isFirst) begin
            outputEntry.hvalid = {2'b01, truncateLSB(outputEntry.dvalid)};
            outputEntry.sop = {2'b01, truncateLSB(outputEntry.sop)};

            let tlpHeaderBuf = bramTlpHeaderReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].first;
            bramTlpHeaderReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].deq;

            tlpHasPayload = isPcieTlpHasPayload(tlpHeaderBuf);

            outputEntry.header = shiftInAtN(outputEntry.header, tlpHeaderBuf);
            outputEntry.header = shiftInAtN(outputEntry.header, unpack(0));
        end
        else begin
            outputEntry.hvalid = {2'b00, truncateLSB(outputEntry.dvalid)};
            outputEntry.sop = {2'b00, truncateLSB(outputEntry.sop)};
        end

        case (bramReadBeatMeta.zeroBasedValidSegCnt)
            0: begin
                outputEntry.dvalid = {tlpHasPayload ? (bramReadBeatMeta.isLast ? 2'b01: 2'b11) : 2'b00, truncateLSB(outputEntry.dvalid)};
                outputEntry.eop = {bramReadBeatMeta.isLast ? 2'b01: 2'b00, truncateLSB(outputEntry.eop)};
            end
            1: begin
                outputEntry.dvalid = {tlpHasPayload ? (bramReadBeatMeta.isLast ? 2'b11: 2'b11) : 2'b00, truncateLSB(outputEntry.dvalid)};
                outputEntry.eop = {bramReadBeatMeta.isLast ? 2'b10: 2'b00, truncateLSB(outputEntry.eop)};
            end
        endcase
    

        if (bramReadBeatMeta.isOutputBeatLast) begin
            finalShiftPipelineQueue.enq(tuple2(outputBeatEmptyStorageRowCnt, outputEntry));
            outputBeatEmptyStorageRowCntReg <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)-1);
        end
        else begin
            outputBeatEmptyStorageRowCntReg <= outputBeatEmptyStorageRowCnt - 1;
        end
        outputEntryReg <= outputEntry;
    endrule

    rule finalShift;
        RtilePcieTxBramRowIndexInOutputBeat      outputBeatEmptyStorageRowCnt;
        RtilePcieTxPingPongChannelOutputEntry    outputEntry;

        {outputBeatEmptyStorageRowCnt, outputEntry} = finalShiftPipelineQueue.first;
        finalShiftPipelineQueue.deq;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel finalShift"),
        //     toBlue(", outputBeatEmptyStorageRowCnt="), fshow(outputBeatEmptyStorageRowCnt),
        //     toBlue(", outputEntry="), fshow(outputEntry)
        // );

        case (outputBeatEmptyStorageRowCnt)
            0: begin
                // nothing to do
            end
            1: begin
                for (Integer idx = 0; idx < 2; idx = idx + 1) begin
                    outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, unpack(0));
                    outputEntry.header = shiftInAtN(outputEntry.header, unpack(0));
                    outputEntry.sop = {1'b0, truncateLSB(outputEntry.sop)};
                    outputEntry.eop = {1'b0, truncateLSB(outputEntry.eop)};
                    outputEntry.hvalid = {1'b0, truncateLSB(outputEntry.hvalid)};
                    outputEntry.dvalid = {1'b0, truncateLSB(outputEntry.dvalid)};
                end 
            end
        endcase
        beatPipeOutQueue.enq(outputEntry);
    endrule

   

    interface metaPipeIn                        = toPipeIn(metaPipeInQueue);
    interface bramTlpHeaderReadRespPipeInVec    = bramTlpHeaderReadRespPipeInVecInst;
    interface beatPipeOut                       = toPipeOut(beatPipeOutQueue);
    interface bramReadReqPipeOutVec             = bramReadReqPipeOutVecInst;
    interface bramReadRespPipeInVec             = bramReadRespPipeInVecInst;
endmodule

interface RtilePcieTxPingPongJoin;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeIn#(RtilePcieTxPingPongChannelOutputEntry))    pingpongBeatPipeInVec;
    interface PipeOut#(PcieTxBeat)                                                                            rtilePcieTxPipeOut;
endinterface

(* synthesize *)
module mkRtilePcieTxPingPongJoin(RtilePcieTxPingPongJoin);
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(RtilePcieTxPingPongChannelOutputEntry))     pingpongBeatPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeIn#(RtilePcieTxPingPongChannelOutputEntry))    pingpongBeatPipeInVecInst  = newVector;
    FIFOF#(PcieTxBeat) rtilePcieTxPipeOutQueue <- mkFIFOF;

    for (Integer idx = 0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongBeatPipeInVecInst[idx] = toPipeIn(pingpongBeatPipeInQueueVec[idx]);
    end

    Reg#(RtilePcieTxPingPongChannelIdx) curChannelIdxReg <- mkReg(0);

    rule doJoin;
        let inputBeat = pingpongBeatPipeInQueueVec[curChannelIdxReg].first;
        pingpongBeatPipeInQueueVec[curChannelIdxReg].deq;
        curChannelIdxReg <= curChannelIdxReg + 1;

        rtilePcieTxPipeOutQueue.enq(PcieTxBeat{
            data        : inputBeat.dataBuf,
            header      : inputBeat.header,
            sop         : inputBeat.sop,
            eop         : inputBeat.eop,
            hvalid      : inputBeat.hvalid,
            dvalid      : inputBeat.dvalid
        });
    endrule

    interface pingpongBeatPipeInVec     = pingpongBeatPipeInVecInst;
    interface rtilePcieTxPipeOut        = toPipeOut(rtilePcieTxPipeOutQueue);
endmodule



interface RTilePcie;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
    interface PipeOut#(PcieTxBeat) pcieTxPipeOut;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieBiDirUserDataStreamPipes)     streamSlaveIfcVec;
endinterface


(* synthesize *)
module mkRTilePcie(RTilePcie);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieBiDirUserDataStreamPipes)     streamSlaveIfcVecInst = newVector;

    let pcieRxStreamSegmentFork <- mkPcieRxStreamSegmentFork;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieCompletionBuffer) cpltBufferVec <- replicateM(mkPcieCompletionBuffer);
    let pcieHwCpltBufferAllocator <- mkPcieHwCpltBufferAllocator;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieRequestTlpHeaderGen) tlpHeaderGenVec <- replicateM(mkPcieRequestTlpHeaderGen);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, RtilePcieTxUserInputGearboxStorageAndMetaExtractor) userInputGearboxStorageAndMetaExtractorVec <- replicateM(mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor);
    let rtilePcieTxPingPongFork <- mkRtilePcieTxPingPongFork;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, RtilePcieTxPingPongSingleChannel) rtilePcieTxPingPongSingleChannelVec <- replicateM(mkRtilePcieTxPingPongSingleChannel);
    let rtilePcieTxPingPongJoin <- mkRtilePcieTxPingPongJoin;


    for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
        mkConnection(pcieRxStreamSegmentFork.tlpRawBeatDataStorageWriteReqPipeOutVec[channelIdx], cpltBufferVec[channelIdx].tlpRawBeatDataStorageWriteReqPipeIn);
        mkConnection(pcieRxStreamSegmentFork.cpltTlpVecPipeOutVec[channelIdx], cpltBufferVec[channelIdx].cpltTlpVecPipeIn);
        mkConnection(cpltBufferVec[channelIdx].sharedHwCpltBufferSlotDeAllocReqPipeOut, pcieHwCpltBufferAllocator.slotDeAllocPipeInVec[channelIdx]);

        streamSlaveIfcVecInst[channelIdx].writePipeIfc.writeMetaPipeIn  = tlpHeaderGenVec[channelIdx].dtldStreamSlavePipes.writePipeIfc.writeMetaPipeIn;
        streamSlaveIfcVecInst[channelIdx].writePipeIfc.writeDataPipeIn  = tlpHeaderGenVec[channelIdx].dtldStreamSlavePipes.writePipeIfc.writeDataPipeIn;
        streamSlaveIfcVecInst[channelIdx].readPipeIfc.readMetaPipeIn    = tlpHeaderGenVec[channelIdx].dtldStreamSlavePipes.readPipeIfc.readMetaPipeIn;
        streamSlaveIfcVecInst[channelIdx].readPipeIfc.readDataPipeOut   = cpltBufferVec[channelIdx].dataStreamPipeOut;

        mkConnection(tlpHeaderGenVec[channelIdx].tagAllocReqPipeOut, cpltBufferVec[channelIdx].tagAllocReqPipeIn);
        mkConnection(cpltBufferVec[channelIdx].tagAllocRespPipeOut, tlpHeaderGenVec[channelIdx].tagAllocRespPipeIn);

        mkConnection(tlpHeaderGenVec[channelIdx].slotAllocReqPipeOut, pcieHwCpltBufferAllocator.slotAllocReqPipeInVec[channelIdx]);
        mkConnection(pcieHwCpltBufferAllocator.slotAllocRespPipeOutVec[channelIdx], tlpHeaderGenVec[channelIdx].slotAllocRespPipeIn);

        mkConnection(tlpHeaderGenVec[channelIdx].tlpDataStreamPipeOut, userInputGearboxStorageAndMetaExtractorVec[channelIdx].streamPipeIn);
        mkConnection(userInputGearboxStorageAndMetaExtractorVec[channelIdx].packetMetaPipeOut, rtilePcieTxPingPongFork.packetMetaPipeInVec[channelIdx]);
        mkConnection(tlpHeaderGenVec[channelIdx].tlpHeaderBufferPipeOut, userInputGearboxStorageAndMetaExtractorVec[channelIdx].txTlpHeaderBufferPipeIn);

        for (Integer pingPongChannelIdx = 0; pingPongChannelIdx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); pingPongChannelIdx = pingPongChannelIdx + 1) begin
            mkConnection(rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].bramReadReqPipeOutVec[channelIdx], userInputGearboxStorageAndMetaExtractorVec[channelIdx].bramReadReqPipeInVec[pingPongChannelIdx]);
            mkConnection(userInputGearboxStorageAndMetaExtractorVec[channelIdx].bramReadRespPipeOutVec[pingPongChannelIdx], rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].bramReadRespPipeInVec[channelIdx]);
            mkConnection(userInputGearboxStorageAndMetaExtractorVec[channelIdx].bramTlpHeaderReadRespPipeOutVec[pingPongChannelIdx], rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].bramTlpHeaderReadRespPipeInVec[channelIdx]);
        end
    end

    for (Integer pingPongChannelIdx = 0; pingPongChannelIdx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); pingPongChannelIdx = pingPongChannelIdx + 1) begin
        mkConnection(rtilePcieTxPingPongFork.pingpongChannelMetaPipeOutVec[pingPongChannelIdx], rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].metaPipeIn);
        mkConnection(rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].beatPipeOut,  rtilePcieTxPingPongJoin.pingpongBeatPipeInVec[pingPongChannelIdx]);
    end

    rule setCpltBufChannelIdx;
        for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
            cpltBufferVec[channelIdx].setChannelIdx(fromInteger(channelIdx));
        end
    endrule

    interface pcieRxPipeIn      = pcieRxStreamSegmentFork.pcieRxPipeIn;
    interface streamSlaveIfcVec = streamSlaveIfcVecInst;
    interface pcieTxPipeOut     = rtilePcieTxPingPongJoin.rtilePcieTxPipeOut;
endmodule
