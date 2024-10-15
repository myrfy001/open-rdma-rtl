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

typedef 13 PCIE_TLP_DATA_BYTE_LENGTH_WIDTH;
typedef Bit#(PCIE_TLP_DATA_BYTE_LENGTH_WIDTH) PcieTlpDataByteLen;

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


typedef 3 PCIE_MAX_SEGMENT_CNT;
typedef PCIE_MAX_SEGMENT_CNT PCIE_RX_HANDLER_CNT;
typedef TLog#(PCIE_RX_HANDLER_CNT) PCIE_RX_HANDLER_IDX_WIDTH;
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


interface PcieRxStreamSegmentFork;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
    interface Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(PcieDataStreamLsbRight)) tlpDataStreamPipeOutVec;
    interface Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(RawPcieRxTlpWithMeta)) tlpHeaderPipeOutVec;
endinterface

(* synthesize *)
module mkPcieRxStreamSegmentFork(PcieRxStreamSegmentFork);
    FIFOF#(PcieRxBeat) pcieRxPipeInQueue <- mkFIFOF;

    Reg#(PcieRxHandlerIdx) curPrimHandlerIdxReg <- mkReg(0);

    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(PcieDataStreamLsbRight)) tlpDataStreamPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(RawPcieRxTlpWithMeta)) tlpHeaderPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(PcieDataStreamLsbRight)) tlpDataStreamPipeOutInstVec = newVector;
    Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(RawPcieRxTlpWithMeta)) tlpHeaderPipeOutInstVec = newVector;

    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        tlpDataStreamPipeOutInstVec[handlerIdx] = toPipeOut(tlpDataStreamPipeOutQueueVec[handlerIdx]);
        tlpHeaderPipeOutInstVec[handlerIdx] = toPipeOut(tlpHeaderPipeOutQueueVec[handlerIdx]);
    end

    Reg#(Bool) prevTlpSpanNextBeatReg <- mkReg(False);

    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(RawPcieRxStreamWithMeta)) handlerInputQueueVec <- replicateM(mkFIFOF);

    Vector#(PCIE_RX_HANDLER_CNT, Reg#(PcieTlpDataByteLen)) streamByteRemainingRegVec <- replicateM(mkRegU);

    RWire#(Vector#(PCIE_RX_HANDLER_CNT, Maybe#(PcieSegmentIdx))) tlpFirstSegmentIdxVecWire <- mkRWire;
    Wire#(PcieRxBeat) beatPassthroughWire <- mkWire;
    Wire#(PcieRxHandlerIdx) curPrimHandlerIdxPassthroughWire <- mkWire;


    // need this gurad condition since the tlpFirstSegmentIdxVecWire's signal must be consumed in current beat, so we must ensure the consumer not blocked.
    let preCalcRxBeatMetaRule = (rules
    rule preCalcRxBeatMeta if (handlerInputQueueVec[0].notFull && handlerInputQueueVec[1].notFull && handlerInputQueueVec[2].notFull);

        let beat = pcieRxPipeInQueue.first;
        pcieRxPipeInQueue.deq;

        beatPassthroughWire <= beat;

        Bool isTlpSpanNextBeat = case (pack(beat.eop)) matches
            'b1???: False;
            'b01??: (beat.sop[3] == 1);
            'b001?: (beat.sop[3] == 1 || beat.sop[2] == 1);
            'b0001: (beat.sop[3] == 1 || beat.sop[2] == 1 || beat.sop[1] == 1);
            'b0000: ((pack(beat.dvalid) != 0) ? True : False);  // for example, all tlp in this beat are read req, which has no data.
        endcase;

        prevTlpSpanNextBeatReg <= isTlpSpanNextBeat;

        PcieSegmentIdx tlpCnt = case (pack(beat.hvalid)) matches
            'b0000: (prevTlpSpanNextBeatReg ? 1 : 0);
            'b0001: (prevTlpSpanNextBeatReg ? 0 : 1);
            'b0010: (prevTlpSpanNextBeatReg ? 2 : 1);
            'b0011: (prevTlpSpanNextBeatReg ? 0 : 2);
            'b0100: (prevTlpSpanNextBeatReg ? 2 : 0);
            'b0101: (prevTlpSpanNextBeatReg ? 0 : 2);
            'b0110: (prevTlpSpanNextBeatReg ? 3 : 2);
            'b0111: (prevTlpSpanNextBeatReg ? 0 : 3);
            'b1000: (prevTlpSpanNextBeatReg ? 2 : 0);
            'b1001: (prevTlpSpanNextBeatReg ? 0 : 2);
            'b1010: (prevTlpSpanNextBeatReg ? 3 : 2);
            'b1011: (prevTlpSpanNextBeatReg ? 0 : 3);
            'b1100: (prevTlpSpanNextBeatReg ? 3 : 0);
            'b1101: (prevTlpSpanNextBeatReg ? 0 : 3);
            'b1110: (prevTlpSpanNextBeatReg ? 0 : 3);
            'b1111: (prevTlpSpanNextBeatReg ? 0 : 0);
        endcase;
        immAssert(
            tlpCnt != 0,
            "one of the following 3 assumption not hold: \n \
               1.The R-Tile PCIe IP does not use segment 2 and segment 3 if segment 0 AND segment 1 are unused \n\
               2.At most 3 TLPs in a beat\n\
               3.When Sop occur at seg0, then the prevTlpSpanNextBeatReg must be False",
            $format("prevTlpSpanNextBeatReg=", fshow(prevTlpSpanNextBeatReg), "beat=", fshow(beat))
        );


        Vector#(PCIE_RX_HANDLER_CNT, Maybe#(PcieSegmentIdx)) tlpFirstSegmentIdxVec = case (pack(beat.hvalid)) matches
            'b0000: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Invalid, tagged Invalid) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b0001: vec(tagged Valid 0, tagged Invalid, tagged Invalid);
            'b0010: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 1, tagged Invalid) : vec(tagged Valid 1, tagged Invalid, tagged Invalid));
            'b0011: vec(tagged Valid 0, tagged Valid 1, tagged Invalid);
            'b0100: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 2, tagged Invalid) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b0101: vec(tagged Valid 0, tagged Valid 2, tagged Invalid);
            'b0110: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 1, tagged Valid 2) : vec(tagged Valid 1, tagged Valid 2, tagged Invalid));
            'b0111: vec(tagged Valid 0, tagged Valid 1, tagged Valid 2);
            'b1000: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 3, tagged Invalid) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b1001: vec(tagged Valid 0, tagged Valid 3, tagged Invalid);
            'b1010: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 1, tagged Valid 3) : vec(tagged Valid 1, tagged Valid 3, tagged Invalid));
            'b1011: vec(tagged Valid 0, tagged Valid 1, tagged Valid 3);
            'b1100: (prevTlpSpanNextBeatReg ? vec(tagged Valid 0, tagged Valid 2, tagged Valid 3) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b1101: vec(tagged Valid 0, tagged Valid 2, tagged Valid 3);
            'b1110: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Invalid, tagged Invalid) : vec(tagged Valid 1, tagged Valid 2, tagged Valid 3));
            'b1111: vec(tagged Invalid, tagged Invalid, tagged Invalid);
        endcase;

        tlpFirstSegmentIdxVecWire.wset(tlpFirstSegmentIdxVec);
        curPrimHandlerIdxPassthroughWire <= curPrimHandlerIdxReg;

        // $display(
        //     "time=%0t:", $time,
        //     "isTlpSpanNextBeat=", fshow(isTlpSpanNextBeat),
        //     ", tlpCnt=", fshow(tlpCnt),
        //     ", tlpFirstSegmentIdxVec=", fshow(tlpFirstSegmentIdxVec)
        // );

        let nextPrimHandlerIdxWide = {1'b0, pack(curPrimHandlerIdxReg)};
        nextPrimHandlerIdxWide = nextPrimHandlerIdxWide + zeroExtend(tlpCnt);
        if (prevTlpSpanNextBeatReg) begin
            nextPrimHandlerIdxWide = nextPrimHandlerIdxWide - 1;
        end

        if (nextPrimHandlerIdxWide > 3) begin
            nextPrimHandlerIdxWide = nextPrimHandlerIdxWide - 3;
        end
        curPrimHandlerIdxReg <= truncate(nextPrimHandlerIdxWide);

    endrule
    endrules);

    Vector#(PCIE_RX_HANDLER_CNT, Rules) outputRulesVec = newVector;
    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        outputRulesVec[handlerIdx] = (rules 
            rule dispatchSegmentToHandlers;
                
                let beat = beatPassthroughWire;
                // $display(
                //     "time=%0t:", $time,
                //     "dispatchSegmentToHandlers idx=%d", handlerIdx,
                //     "tlpFirstSegmentIdxVecWire.wget = ", fshow(tlpFirstSegmentIdxVecWire.wget)
                // );

                if (tlpFirstSegmentIdxVecWire.wget matches tagged Valid .tlpFirstSegmentIdxVec) begin
                    // $display("dispatchSegmentToHandlers first level idx=%d", handlerIdx, ", tlpFirstSegmentIdxVec=", fshow(tlpFirstSegmentIdxVec));

                    if (tlpFirstSegmentIdxVec[handlerIdx] matches tagged Valid .startSegIdx) begin
                        let ent = RawPcieRxStreamWithMeta {
                            rxBeat: beat,
                            startSegIdx: startSegIdx
                        };

                        let curPrimHandlerIdxWide = {1'b0, pack(curPrimHandlerIdxPassthroughWire)};
                        curPrimHandlerIdxWide = curPrimHandlerIdxWide + fromInteger(handlerIdx);
                        if (curPrimHandlerIdxWide > fromInteger(valueOf(PCIE_RX_HANDLER_CNT) - 1)) begin
                            curPrimHandlerIdxWide = curPrimHandlerIdxWide - fromInteger(valueOf(PCIE_RX_HANDLER_CNT) - 1);
                        end

                        PcieRxHandlerIdx curPrimHandlerIdx = truncate(curPrimHandlerIdxWide);

                        handlerInputQueueVec[curPrimHandlerIdx].enq(ent);

                        // $display(
                        //     "time=%0t:", $time, toGreen(" mkPcieRxStreamSegmentFork dispatchSegmentToHandlers"),
                        //     toBlue(", handlerIdx="), "%d", handlerIdx,
                        //     toBlue(", ent="), fshow(ent)
                        // );
                    end
                end
            endrule
        endrules);
    end

    addRules(rJoinConflictFree(preCalcRxBeatMetaRule, rJoinConflictFree(outputRulesVec[0], rJoinConflictFree(outputRulesVec[1], outputRulesVec[2]))));


    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        rule rawPcieRxInputToInternalDataType;
            let beat = handlerInputQueueVec[handlerIdx].first;
            handlerInputQueueVec[handlerIdx].deq;

            let sopBundle = beat.rxBeat.sop;
            let eopBundle = beat.rxBeat.eop;
            let hvalidBundle = beat.rxBeat.hvalid;
            let dvalidBundle = beat.rxBeat.dvalid;


            // TODO: must check the relationship between sop and hvalid. for TLP without data, will sop be assert?
            //       can hvalid be used as signal for the start of a new TLP?
            let isFirst = hvalidBundle[beat.startSegIdx] == 1;

            // for non-first beat, if there is at least one eop, then this beat must be eop.
            Bool notFirstBeatIsEop = pack(eopBundle) != 0;

            Bool firstBeatIsEop = case (beat.startSegIdx)
                0: (eopBundle[3:0] != 0);
                1: (eopBundle[3:1] != 0);
                2: (eopBundle[3:2] != 0);
                3: (eopBundle[3:3] != 0);
            endcase;

            Bool isLast = isFirst ? firstBeatIsEop : notFirstBeatIsEop;

            let tlpDataLenMaybe = getDataLenFromTlpHeader(beat.rxBeat.header[beat.startSegIdx]);
            immAssert(
                isValid(tlpDataLenMaybe),
                "unsupported TLP",
                $format("beat=", fshow(beat))
            );
            let tlpDataLen = fromMaybe(0, tlpDataLenMaybe);

            let tlpDataLenInDw = getPayloadLengthInDW(beat.rxBeat.header[beat.startSegIdx]);
            let tlpDataLenInByteAlignToDW = tlpDataLenInDw << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);

            PcieDataStreamByteCnt byteNum = truncate(streamByteRemainingRegVec[handlerIdx]);
            PcieDataStreamByteIdx startByteIdx = 0;
            if (isFirst) begin
                case (beat.startSegIdx) matches
                    0: begin
                        startByteIdx = fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 0);
                        byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 4);
                    end
                    1: begin
                        startByteIdx = fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 1);
                        byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 3);
                    end
                    2: begin
                        startByteIdx = fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 2);
                        byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 2);
                    end
                    3: begin
                        startByteIdx = fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 3);
                        byteNum = isLast ? truncate(tlpDataLenInByteAlignToDW) : fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) * 1);
                    end
                endcase
                streamByteRemainingRegVec[handlerIdx] <= tlpDataLenInByteAlignToDW - zeroExtend(byteNum);
            end

            let ds = PcieDataStreamLsbRight {
                data: pack(beat.rxBeat.data),
                byteNum: byteNum,
                startByteIdx: startByteIdx,
                isFirst: isFirst,
                isLast: isLast
            };
            
            if (isFirst) begin
                let tlpWithMeta = RawPcieRxTlpWithMeta {
                    rawTlpHeader: beat.rxBeat.header[beat.startSegIdx],
                    startSegIdx: beat.startSegIdx
                };
                tlpHeaderPipeOutQueueVec[handlerIdx].enq(tlpWithMeta);
            end

            if (dvalidBundle[beat.startSegIdx] == 1) begin
                tlpDataStreamPipeOutQueueVec[handlerIdx].enq(ds);
            end
        endrule
    end


    interface pcieRxPipeIn = toPipeIn(pcieRxPipeInQueue);
    interface tlpDataStreamPipeOutVec = tlpDataStreamPipeOutInstVec;
    interface tlpHeaderPipeOutVec = tlpHeaderPipeOutInstVec;
endmodule


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

function Bool isPcieTlpLastReadCplt(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
    let tlpDataLenMaybe = getDataLenFromTlpHeader(tlpBuffer);

    PcieTlpDataByteLen extendedByteCount = zeroExtend(tlpHeader.byteCount);
    extendedByteCount[valueOf(PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

    let tlpDataLen = fromMaybe(0, tlpDataLenMaybe);
    return extendedByteCount == tlpDataLen;
endfunction




function PcieTlpDataByteLen getPayloadLengthInDW(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteLen length = zeroExtend(headerFirstDW.length);
    length[valueOf(SizeOf#(PcieHeaderFieldLength))] = pack(headerFirstDW.length == 0);  // length == 0 means 4096 bytes
    return length;
endfunction

function Maybe#(PcieTlpDataByteLen) getDataLenFromTlpHeader(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);

    PcieTlpDataByteLen length = getPayloadLengthInDW(tlpBuffer);
    length = length << 2; // convert from DW to Byte

    if (!isPcieTlpHasPayload(tlpBuffer)) begin
        return tagged Invalid;
    end
    else begin
        if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_MEM_WRITE) begin
            PcieTlpHeaderMemoryAccess tlpHeader = unpack(truncateLSB(tlpBuffer));
            Bit#(3) subValFirstBe = case (pack(tlpHeader.firstDwBe)) matches
                4'b???1: 0;
                4'b??10: 1;
                4'b?100: 2;
                4'b1000: 3;
                4'b0000: 4;
                default: 0;
            endcase;

            Bit#(2) subValLastBe = case (pack(tlpHeader.lastDwBe)) matches
                4'b1???: 0;
                4'b01??: 1;
                4'b001?: 2;
                4'b0001: 3;
                default: 0;
            endcase;

            length = length - zeroExtend(subValFirstBe) - zeroExtend(subValLastBe);
            return tagged Valid length;
        end
        else if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA) begin
            PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

            // for the first cplt, lowerAddr's 2-lsb means the address offset, which is the count of invalid bytes in the first payload DW
            // for other cplt, lowerAddr's 2-lsb must be zero, so the length won't be modified.
            let adjustedLength = length - zeroExtend(tlpHeader.lowerAddress[1:0]);

            PcieTlpDataByteLen extendedByteCount = zeroExtend(tlpHeader.byteCount);
            extendedByteCount[valueOf(PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

            Bool isLastCplt = adjustedLength >= extendedByteCount;
            return tagged Valid (isLastCplt ? extendedByteCount : adjustedLength);
        end
        else begin
            return tagged Invalid;
        end
    end
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

interface TlpDemuxAndConvertToMemMapStream;
    interface PipeIn#(PcieDataStreamLsbRight) tlpDataStreamPipeIn;
    interface PipeIn#(RawPcieRxTlpWithMeta) tlpHeaderPipeIn;

    interface PipeOut#(PcieDataStreamLsbRight) tlpMemReqDataStreamPipeOut;
    interface PipeOut#(PcieTlpHeaderBuffer) tlpMemReqHeaderPipeOut;

    interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(MemoeyMapAlignedDataStreamWithMetadata)) tlpCpltDataStreamPipeOutVec;
    interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(PcieTlpHeaderBuffer)) tlpCpltHeaderPipeOutVec;
endinterface


(* synthesize *)
module mkTlpDemuxAndConvertToMemMapStream(TlpDemuxAndConvertToMemMapStream);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(MemoeyMapAlignedDataStreamWithMetadata)) tlpCpltDataStreamPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, FIFOF#(PcieTlpHeaderBuffer)) tlpCpltHeaderPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(MemoeyMapAlignedDataStreamWithMetadata)) tlpCpltDataStreamPipeOutInstVec = newVector;
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PipeOut#(PcieTlpHeaderBuffer)) tlpCpltHeaderPipeOutInstVec = newVector;

    FIFOF#(PcieDataStreamLsbRight) tlpDataStreamPipeInQueue <- mkFIFOF;
    FIFOF#(RawPcieRxTlpWithMeta) tlpHeaderPipeInQueue <- mkFIFOF;

    FIFOF#(PcieDataStreamLsbRight) tlpMemReqDataStreamPipeOutQueue <- mkFIFOF;
    FIFOF#(PcieTlpHeaderBuffer) tlpMemReqHeaderPipeOutQueue <- mkFIFOF;

    for (Integer handlerIdx = 0; handlerIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); handlerIdx = handlerIdx + 1) begin
        tlpCpltDataStreamPipeOutInstVec[handlerIdx] = toPipeOut(tlpCpltDataStreamPipeOutQueueVec[handlerIdx]);
        tlpCpltHeaderPipeOutInstVec[handlerIdx] = toPipeOut(tlpCpltHeaderPipeOutQueueVec[handlerIdx]);
    end

    PcieStreamShifter streamShifter <- mkBiDirectionStreamShifterLsbRightG;

    FIFOF#(MetaForReceivedTlpDispatch) tlpHeaderDispatchMetaQueue <- mkFIFOF;
    FIFOF#(MetaForReceivedTlpDispatch) tlpDataDispatchMetaQueue <- mkFIFOF;

    FIFOF#(RawPcieRxTlpWithMeta) tlpHeaderForDispatchPipeQueue <- mkFIFOF;

    rule forwardDataStreamToShifter;
        PcieDataStreamLsbRight dsInput = tlpDataStreamPipeInQueue.first;
        tlpDataStreamPipeInQueue.deq;
        streamShifter.streamPipeIn.enq(dsInput);
        $display(
            "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream forwardDataStreamToShifter"),
            toBlue(", dsInput="), fshow(dsInput)
        );
    endrule

    rule calcMetaData;
        let tlpHeaderWithMeta = tlpHeaderPipeInQueue.first;
        tlpHeaderPipeInQueue.deq;
        let signedShiftOffsetMaybe = getSignedBiDirByteShiftOffsetFromTlpHeader(tlpHeaderWithMeta.rawTlpHeader, tlpHeaderWithMeta.startSegIdx);
        let isCplt = isPcieTlpReadCplt(tlpHeaderWithMeta.rawTlpHeader);
        let hasData = isPcieTlpHasPayload(tlpHeaderWithMeta.rawTlpHeader);

        

        immAssert(
            isValid(signedShiftOffsetMaybe),
            "get shift offset from TLP error, TLP type not supported",
            $format("TLP Info = ", fshow(getPcieTlpHeaderCommon(tlpHeaderWithMeta.rawTlpHeader)))
        );
        let signedShiftOffset = fromMaybe(?, signedShiftOffsetMaybe);

        let dispatchMeta = MetaForReceivedTlpDispatch {
            isCplt      : isCplt,
            extTag      : getExtendedTagFromTlpCpltHeader(tlpHeaderWithMeta.rawTlpHeader),
            isLastCplt  : isPcieTlpLastReadCplt(tlpHeaderWithMeta.rawTlpHeader)
        };

        tlpHeaderDispatchMetaQueue.enq(dispatchMeta);
        if (hasData) begin
            streamShifter.offsetPipeIn.enq(signedShiftOffset);
            tlpDataDispatchMetaQueue.enq(dispatchMeta);
        end
        tlpHeaderForDispatchPipeQueue.enq(tlpHeaderWithMeta);

        $display(
            "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream calcMetaData"),
            toBlue(", dispatchMeta="), fshow(dispatchMeta),
            toBlue(", signedShiftOffset="), fshow(signedShiftOffset)
        );
    endrule

    rule dispatchOutputDataStream;
        let shiftedRightAlignedStream = streamShifter.streamPipeOut.first;
        streamShifter.streamPipeOut.deq;

        let dispatchMeta = tlpDataDispatchMetaQueue.first;
        if (shiftedRightAlignedStream.isLast) begin
            tlpDataDispatchMetaQueue.deq;
        end

        let outputDataStreamWithMeta = MemoeyMapAlignedDataStreamWithMetadata {
            ds              : shiftedRightAlignedStream,
            tagHigherPart   : truncateLSB(dispatchMeta.extTag),
            isLastCplt      : dispatchMeta.isLastCplt
        };

        DispatchChannelIdx dispatchIdx = truncate(dispatchMeta.extTag);
        if (dispatchMeta.isCplt) begin
            tlpCpltDataStreamPipeOutQueueVec[dispatchIdx].enq(outputDataStreamWithMeta);
            $display(
                "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream dispatchOutputDataStream Cplt"),
                toBlue(", dispatchIdx="), fshow(dispatchIdx),
                toBlue(", tag="), fshow(dispatchMeta.extTag),
                toBlue(", outputDataStreamWithMeta="), fshow(outputDataStreamWithMeta)
            );
        end
        else begin
            tlpMemReqDataStreamPipeOutQueue.enq(shiftedRightAlignedStream);
            $display(
                "time=%0t:", $time, toGreen(" mkTlpDemuxAndConvertToMemMapStream dispatchOutputDataStream MemRW"),
                toBlue(", dispatchIdx="), fshow(dispatchIdx),
                toBlue(", tag="), fshow(dispatchMeta.extTag),
                toBlue(", outputDataStreamWithMeta="), fshow(outputDataStreamWithMeta)
            );
        end
    endrule

    rule dispatchOutputTlpHeader;
        let dispatchMeta = tlpHeaderDispatchMetaQueue.first;
        tlpHeaderDispatchMetaQueue.deq;

        let tlpHeaderWithMeta = tlpHeaderForDispatchPipeQueue.first;
        tlpHeaderForDispatchPipeQueue.deq;

        DispatchChannelIdx dispatchIdx = truncate(dispatchMeta.extTag);
        if (dispatchMeta.isCplt) begin
            tlpCpltHeaderPipeOutQueueVec[dispatchIdx].enq(tlpHeaderWithMeta.rawTlpHeader);
        end
        else begin
            tlpMemReqHeaderPipeOutQueue.enq(tlpHeaderWithMeta.rawTlpHeader);
        end
    endrule


    interface tlpDataStreamPipeIn = toPipeIn(tlpDataStreamPipeInQueue);
    interface tlpHeaderPipeIn = toPipeIn(tlpHeaderPipeInQueue);

    interface tlpMemReqDataStreamPipeOut = toPipeOut(tlpMemReqDataStreamPipeOutQueue);
    interface tlpMemReqHeaderPipeOut = toPipeOut(tlpMemReqHeaderPipeOutQueue);

    interface tlpCpltDataStreamPipeOutVec = tlpCpltDataStreamPipeOutInstVec;
    interface tlpCpltHeaderPipeOutVec = tlpCpltHeaderPipeOutInstVec;
endmodule


interface PcieCompletionBuffer;
    interface PipeIn#(PcieCompletionBufferSlotAllocReq) tagAllocPipeIn;
    interface PipeOut#(PcieHeaderFieldExtendedTag) tagAllocPipeOut;
    interface PipeIn#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeIn;
    interface PipeOut#(PcieDataStreamLsbRight) dataStreamPipeOut;
endinterface

typedef 32 PCIE_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH;
typedef Bit#(PCIE_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH) PcieCompletionBufferSlotUserData;

// according to UG21036, Total tag allowed is from 256 to 1023. We use the lower 2 bits of the 10 bits tag as channel index,
// so the higher 8 bits should range between 64~255.
typedef 64 PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE;
typedef 255 PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE;

typedef 8 PCIE_EXTENDED_TAG_HIGH_PART_WIDTH;
typedef Bit#(PCIE_EXTENDED_TAG_HIGH_PART_WIDTH) PcieExtendTagHighPart;

typedef 512 PCIE_MIN_RCB_BIT_WIDTH;
typedef TDiv#(PCIE_MIN_RCB_BIT_WIDTH, BYTE_WIDTH) PCIE_MIN_RCB_BYTE_WIDTH;
typedef Bit#(PCIE_MIN_RCB_BIT_WIDTH) PcieRcbDataBlock;

typedef TAdd#(1, TSub#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE, PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)) PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT;
typedef 8 PCIE_COMPLETION_BUFFER_INTERNAL_BUFFER_ROW_PER_SLOT;

typedef PCIE_EXTENDED_TAG_HIGH_PART_WIDTH PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH;   // 8
typedef TLog#(PCIE_COMPLETION_BUFFER_INTERNAL_BUFFER_ROW_PER_SLOT) PCIE_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH;  // 3

typedef TAdd#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH, PCIE_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH) PCIE_COMPLETION_BUFFER_INNER_STORAGE_ROW_INDEX_WIDTH;  // 11

typedef Bit#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH)           PcieCompletionBufferSlotIdx;
typedef Bit#(TLog#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE)) PcieCompletionBufferSlotCnt;

typedef Bit#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH) PcieCompletionBufferSlotInnerRowIdx;
typedef Bit#(PCIE_COMPLETION_BUFFER_INNER_STORAGE_ROW_INDEX_WIDTH)  PcieCompletionBufferInnerStorageRowIdx;

typedef Bit#(TLog#(PCIE_HEADER_FIELD_FIRST_DW_BE_WIDTH))            InvalidByteNumInDw;

typedef struct {
    PcieCompletionBufferSlotUserData    userdata;
    InvalidByteNumInDw                  firstDwInvalidByteNum;
    InvalidByteNumInDw                  lastDwInvalidByteNum;
} PcieCompletionBufferSlotAllocReq deriving(Bits, FShow);

typedef struct {
    PcieCompletionBufferSlotUserData                    userdata;                   // 32
    PcieCompletionBufferSlotInnerRowIdx                 writePtr;                   // 3
    PcieCompletionBufferSlotIdx                         slotIdx;                    // 8
    Bool                                                isCompleted; 
    Bool                                                isFirstBeat;
    Bool                                                isFirstRow;
    PcieDataStreamByteIdx                               startByteIdx;               // 7
    PcieDataStreamByteCnt                               firstBeatByteNum;           // 8
    PcieDataStreamByteCnt                               lastBeatByteNum;            // 8
    InvalidByteNumInDw                                  firstDwInvalidByteNum;      // 2
    InvalidByteNumInDw                                  lastDwInvalidByteNum;       // 2
} PcieCompletionBufferSlotMeta deriving(Bits, FShow);

// typedef struct {
//     DataStreamMeta#(PcieDataStreamByteCnt, PcieDataStreamByteIdx) dataStreamMeta;
// } PcieCompletionBufferRowMeta deriving(Bits, FShow);

typedef enum {
    PcieCompletionBufferOutputStateSendStateQueryReq = 0,
    PcieCompletionBufferOutputStateWaitStateQueryResp = 1
} PcieCompletionBufferOutputState deriving(Bits, Eq, FShow);

module mkPcieCompletionBuffer#(DispatchChannelIdx channelIdx)(PcieCompletionBuffer);

    FIFOF#(PcieCompletionBufferSlotAllocReq)        tagAllocPipeInQueue         <- mkFIFOF;
    FIFOF#(PcieHeaderFieldExtendedTag)              tagAllocPipeOutQueue        <- mkFIFOF;
    FIFOF#(MemoeyMapAlignedDataStreamWithMetadata)  dataStreamPipeInQueue       <- mkFIFOF;
    FIFOF#(PcieDataStreamLsbRight)                  dataStreamPipeOutQueue      <- mkFIFOF;


    Reg#(PcieExtendTagHighPart) headReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Reg#(PcieExtendTagHighPart) tailReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Count#(PcieCompletionBufferSlotCnt) busySlotCounter <- mkCount(0);

    Vector#(NUMERIC_TYPE_TWO, AutoInferBramQueuedOutput#(PcieCompletionBufferInnerStorageRowIdx, PcieRcbDataBlock))             dataStreamStorageVec            <- replicateM(mkAutoInferBramQueuedOutput(False, ""));
    AutoInferBramQueuedOutput#(PcieCompletionBufferSlotIdx, PcieCompletionBufferSlotMeta)                                       slotMetaStorage                 <- mkAutoInferBramQueuedOutput(False, "");
    // Vector#(NUMERIC_TYPE_TWO, AutoInferBramQueuedOutput#(PcieCompletionBufferInnerStorageRowIdx, PcieCompletionBufferRowMeta))  rowMetaStorageDoubleWriteVec    <- replicateM(mkAutoInferBramQueuedOutput(False, ""));

    FIFOF#(Tuple2#(PcieCompletionBufferSlotIdx, PcieCompletionBufferSlotMeta)) slotMetaUpdateReqQueueForTagAlloc <- mkFIFOF;
    FIFOF#(Tuple2#(PcieCompletionBufferSlotIdx, PcieCompletionBufferSlotMeta)) slotMetaUpdateReqQueueForWritePtrUpdate <- mkFIFOF;

    FIFOF#(PcieCompletionBufferSlotIdx) slotMetaReadReqQueueForPtrUpdate <- mkFIFOF;
    FIFOF#(PcieCompletionBufferSlotIdx) slotMetaReadReqQueueForOutputData <- mkFIFOF;

    FIFOF#(PcieCompletionBufferSlotMeta) slotMetaReadRespQueueForPtrUpdate <- mkFIFOF;
    FIFOF#(PcieCompletionBufferSlotMeta) slotMetaReadRespQueueForOutputData <- mkFIFOF;

    FIFOF#(Bool) slotMetaReadReqKeepOrderQueue <- mkFIFOF;

    // Pipeline FIFOs
    FIFOF#(Tuple3#(MemoeyMapAlignedDataStreamWithMetadata, Bool, Bool))     inputStreamStorageMetaCalcPipelineQueue             <- mkFIFOF;
    FIFOF#(PcieCompletionBufferSlotMeta)                                    outputSlotMetaForSendReadReqPipelineQueue           <- mkFIFOF;
    FIFOF#(DataStreamMeta#(PcieDataStreamDataLsbRight))                     outputStreamMetaPipelineQueue                       <- mkFIFOF;

    Reg#(PcieCompletionBufferSlotInnerRowIdx)   curReadOutReqPtrReg           <- mkReg(0);
    Reg#(PcieCompletionBufferSlotInnerRowIdx)   curReadOutReqPtrTargetReg     <- mkReg(0);
    Reg#(PcieCompletionBufferSlotIdx)           curReadOutReqSlotIdx          <- mkReg(0);
                            

    PrioritySearchBuffer#(NUMERIC_TYPE_FOUR, PcieCompletionBufferSlotIdx, PcieCompletionBufferSlotMeta) slotMetaUpdateForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_FOUR));
    // PrioritySearchBuffer#(NUMERIC_TYPE_FOUR, PcieCompletionBufferInnerStorageRowIdx, PcieCompletionBufferRowMeta) slotMetaUpdateForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_FOUR));
    
    Reg#(Bool) newCompleteSlotSignal[3] <- mkCReg(3, False);

    Reg#(PcieCompletionBufferOutputState) outputStateReg <- mkReg(PcieCompletionBufferOutputStateSendStateQueryReq);

    Reg#(Bool) isOutputFirstBeatReg <- mkReg(True);

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

            let newSlot = PcieCompletionBufferSlotMeta {
                userdata:               req.userdata,
                writePtr:               0,
                slotIdx:                headReg,
                isCompleted:            False,
                isFirstBeat:            True,
                isFirstRow:             True,
                startByteIdx:           0,
                firstBeatByteNum:       0,
                lastBeatByteNum:        0,
                firstDwInvalidByteNum:  req.firstDwInvalidByteNum,
                lastDwInvalidByteNum:   req.lastDwInvalidByteNum
            };
            
            PcieHeaderFieldExtendedTag tag = unpack({pack(headReg), pack(channelIdx)});
            slotMetaUpdateReqQueueForTagAlloc.enq(tuple2(headReg, newSlot));

            tagAllocPipeOutQueue.enq(tag);

            if (headReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                headReg <= fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
            end
            else begin
                headReg <= headReg + 1;
            end
            busySlotCounter.incr(1);

            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleTagAlloc"),
                toBlue(", channelIdx="), fshow(channelIdx),
                toBlue(", tag="), fshow(tag)
            );
        end

    endrule

    rule handleStreamInput;
        let inputStreamWithMeta = dataStreamPipeInQueue.first;
        dataStreamPipeInQueue.deq;

        let ds = inputStreamWithMeta.ds;
        let isLastCplt = inputStreamWithMeta.isLastCplt;

        let slotIdx = unpack(inputStreamWithMeta.tagHigherPart);

        Bool isLowerHalfUsed = True;
        Bool isHigherHalfUsed = True;

        if (ds.isFirst) begin
            if (ds.startByteIdx >= fromInteger(valueOf(PCIE_TLP_DATA_BUNDLE_BYTE_CNT) / 2)) begin
                isLowerHalfUsed = False;
            end
        end

        if (ds.isLast) begin
            if (zeroExtend(ds.startByteIdx) + ds.byteNum < fromInteger(valueOf(PCIE_TLP_DATA_BUNDLE_BYTE_CNT) / 2)) begin
                isHigherHalfUsed = False;
            end
        end

        immAssert(
            (isLowerHalfUsed || isHigherHalfUsed),
            "isLowerHalfUsed and isHigherHalfUsed can't both be False",
            $format("")
        );

        slotMetaReadReqQueueForPtrUpdate.enq(slotIdx);

        inputStreamStorageMetaCalcPipelineQueue.enq(tuple3(inputStreamWithMeta, isLowerHalfUsed, isHigherHalfUsed));

        $display(
            "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleStreamInput"),
            toBlue(", inputStreamWithMeta="), fshow(inputStreamWithMeta),
            toBlue(", isLowerHalfUsed="), fshow(isLowerHalfUsed),
            toBlue(", isHigherHalfUsed="), fshow(isHigherHalfUsed)
        );
    endrule

    rule storeInputStream;
        let {inputStreamWithMeta, isLowerHalfUsed, isHigherHalfUsed} = inputStreamStorageMetaCalcPipelineQueue.first;
        inputStreamStorageMetaCalcPipelineQueue.deq;

        let slotMetaReadFromBram = slotMetaReadRespQueueForPtrUpdate.first;
        slotMetaReadRespQueueForPtrUpdate.deq;

        let ds                                  = inputStreamWithMeta.ds;
        let isLastCplt                          = inputStreamWithMeta.isLastCplt;
        let needUpdateWritePtr                  = isHigherHalfUsed;
        PcieCompletionBufferSlotIdx slotIdx     = unpack(inputStreamWithMeta.tagHigherPart);
        let slotMetaFromForwardBufferMaybe      <- slotMetaUpdateForwardBuffer.search(slotIdx);
        PcieCompletionBufferSlotMeta slotMeta   = isValid(slotMetaFromForwardBufferMaybe) ? fromMaybe(?, slotMetaFromForwardBufferMaybe) : slotMetaReadFromBram;

        PcieCompletionBufferInnerStorageRowIdx streamWriteAddr = unpack({pack(slotIdx), pack(slotMeta.writePtr)});
        if (isLowerHalfUsed) begin
            dataStreamStorageVec[0].write(streamWriteAddr, truncate(ds.data));
        end
        if (isHigherHalfUsed) begin
            dataStreamStorageVec[1].write(streamWriteAddr, truncateLSB(ds.data));
        end

        Bool isCompleted = isLastCplt && ds.isLast;
        slotMeta.isCompleted = isCompleted;

        if (slotMeta.isFirstBeat) begin
            slotMeta.isFirstBeat = False;
            slotMeta.startByteIdx = ds.startByteIdx;
            slotMeta.firstBeatByteNum = ds.byteNum;
        end
        else if (slotMeta.isFirstRow) begin
            // if the first row is consist of two seperate cplt, this is the second cplt
            slotMeta.firstBeatByteNum = slotMeta.firstBeatByteNum + ds.byteNum;
        end
        
        if (isCompleted) begin
            if (isLowerHalfUsed && isHigherHalfUsed) begin
                slotMeta.lastBeatByteNum = ds.byteNum;
            end
            else if (isLowerHalfUsed && !isHigherHalfUsed) begin
                slotMeta.lastBeatByteNum = ds.byteNum;
            end
            else if (!isLowerHalfUsed && isHigherHalfUsed) begin
                // the last row is consist of two cplt.
                // there are two case:
                // 1. the whole response only have one row. In this case, the `slotMeta.firstBeatByteNum` already record the row's valid byte count,
                //    so `slotMeta.lastBeatByteNum` should not be used. we will give it a meaningless value, but it doesn't matter.
                // 2. the whole response has more than one row, so the first cplt TLP of the last row must have all higher half data valid.    
                slotMeta.lastBeatByteNum  = ds.byteNum + fromInteger(valueOf(PCIE_MIN_RCB_BYTE_WIDTH));
            end
        end

        if (needUpdateWritePtr && !isCompleted) begin
            slotMeta.writePtr = slotMeta.writePtr + 1;
            slotMeta.isFirstRow = False;
        end

        slotMetaUpdateForwardBuffer.enq(slotIdx, slotMeta);
        slotMetaUpdateReqQueueForWritePtrUpdate.enq(tuple2(slotIdx, slotMeta));

        if (isCompleted) begin
            newCompleteSlotSignal[1] <= True;
        end
    endrule

    rule outputSendStateQuery if (outputStateReg == PcieCompletionBufferOutputStateSendStateQueryReq);
        if (newCompleteSlotSignal[0] == True) begin
            newCompleteSlotSignal[0] <= False;
            slotMetaReadReqQueueForOutputData.enq(tailReg);
            outputStateReg <= PcieCompletionBufferOutputStateWaitStateQueryResp;
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer outputSendStateQuery"),
                toBlue(", tailReg="), fshow(tailReg)
            );
        end
    endrule

    rule outputWaitStateQueryResp if (outputStateReg == PcieCompletionBufferOutputStateWaitStateQueryResp);
        if (slotMetaReadRespQueueForOutputData.notEmpty) begin
            let slotMeta = slotMetaReadRespQueueForOutputData.first;
            slotMetaReadRespQueueForOutputData.deq;
            if (slotMeta.isCompleted) begin
                outputSlotMetaForSendReadReqPipelineQueue.enq(slotMeta);
            end
            outputStateReg <= PcieCompletionBufferOutputStateSendStateQueryReq;
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer outputWaitStateQueryResp"),
                toBlue(", slotMeta="), fshow(slotMeta)
            );
        end
    endrule

    rule sendSlotRowDataReadReq;
        let curSlotMeta = outputSlotMetaForSendReadReqPipelineQueue.first;
        Bool needIncrTailPtr = False;
        if (curReadOutReqPtrReg == curReadOutReqPtrTargetReg) begin
            // This beat is the start of a new output Stream;
            
            curReadOutReqPtrReg <= 0;
            curReadOutReqPtrTargetReg <= curSlotMeta.writePtr;
            curReadOutReqSlotIdx <= curSlotMeta.slotIdx;


            dataStreamStorageVec[0].putReadReq(unpack({pack(curSlotMeta.slotIdx), 0}));
            dataStreamStorageVec[1].putReadReq(unpack({pack(curSlotMeta.slotIdx), 0}));


            let isOnly = curSlotMeta.writePtr == 0;
            let dataStreamMeta = DataStreamMeta {
                byteNum:        isOnly ? curSlotMeta.firstBeatByteNum - zeroExtend(curSlotMeta.firstDwInvalidByteNum) - zeroExtend(curSlotMeta.lastDwInvalidByteNum) : curSlotMeta.firstBeatByteNum - zeroExtend(curSlotMeta.firstDwInvalidByteNum),
                startByteIdx:   curSlotMeta.startByteIdx + zeroExtend(curSlotMeta.firstDwInvalidByteNum),
                isFirst:        True,
                isLast:         isOnly
            };
            outputStreamMetaPipelineQueue.enq(dataStreamMeta);

            if (isOnly) begin
                outputSlotMetaForSendReadReqPipelineQueue.deq;
                newCompleteSlotSignal[2] <= True;
                needIncrTailPtr = True;

            end
        end
        else begin
            let newPtr = curReadOutReqPtrReg + 1;
            curReadOutReqPtrReg <= newPtr;
            dataStreamStorageVec[0].putReadReq(unpack({pack(curReadOutReqSlotIdx), pack(newPtr)}));
            dataStreamStorageVec[1].putReadReq(unpack({pack(curReadOutReqSlotIdx), pack(newPtr)}));

            let isLast = newPtr == curReadOutReqPtrTargetReg;
            let dataStreamMeta = DataStreamMeta {
                byteNum: isLast ? curSlotMeta.lastBeatByteNum - zeroExtend(curSlotMeta.lastDwInvalidByteNum) : fromInteger(valueOf(PCIE_TLP_DATA_BUNDLE_BYTE_CNT)),
                startByteIdx: 0,
                isFirst: False,
                isLast: isLast
            };
            outputStreamMetaPipelineQueue.enq(dataStreamMeta);

            if (isLast) begin
                outputSlotMetaForSendReadReqPipelineQueue.deq;
                newCompleteSlotSignal[2] <= True;
                needIncrTailPtr = True;
            end
        end

        if (needIncrTailPtr) begin
            if (tailReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                tailReg <=fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
            end 
            else begin
                tailReg <= tailReg + 1;
            end
        end

        $display(
            "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer sendSlotRowDataReadReq"),
            toBlue(", curSlotMeta="), fshow(curSlotMeta)
        );
    endrule

    rule receiveDataStreamRowDataAndOutput;
        let streamLowerPart = dataStreamStorageVec[0].readRespPipeOut.first;
        let streamHigherPart = dataStreamStorageVec[1].readRespPipeOut.first;
        let streamMeta = outputStreamMetaPipelineQueue.first;

        dataStreamStorageVec[0].readRespPipeOut.deq;
        dataStreamStorageVec[1].readRespPipeOut.deq;
        outputStreamMetaPipelineQueue.deq;

        PcieDataStreamLsbRight ds = DtldStreamData {
            data: unpack({streamHigherPart, streamLowerPart}),
            byteNum: streamMeta.byteNum,
            startByteIdx: streamMeta.startByteIdx,
            isFirst: streamMeta.isFirst,
            isLast: streamMeta.isLast
        };
        dataStreamPipeOutQueue.enq(ds);

        if (ds.isLast) begin
            busySlotCounter.decr(1);
        end

        $display(
            "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer receiveDataStreamRowDataAndOutput"),
            toBlue(", ds="), fshow(ds)
        );
    endrule

    interface tagAllocPipeIn    =   toPipeIn(tagAllocPipeInQueue);
    interface tagAllocPipeOut   =   toPipeOut(tagAllocPipeOutQueue);
    interface dataStreamPipeIn  =   toPipeIn(dataStreamPipeInQueue);
    interface dataStreamPipeOut =   toPipeOut(dataStreamPipeOutQueue);
endmodule


interface DataStreamArbiterForCompletionBuffer;
    interface Vector#(PCIE_RX_HANDLER_CNT, PipeIn#(MemoeyMapAlignedDataStreamWithMetadata)) dataStreamPipeInVec;
    interface PipeOut#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeOut;
endinterface

module mkDataStreamArbiterForCompletionBuffer(DataStreamArbiterForCompletionBuffer);
    Vector#(PCIE_RX_HANDLER_CNT, PipeIn#(MemoeyMapAlignedDataStreamWithMetadata)) dataStreamPipeInVecInst = newVector;
    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(MemoeyMapAlignedDataStreamWithMetadata)) dataStreamPipeInQueueVec <- replicateM(mkFIFOF);
    FIFOF#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeOutQueue <- mkFIFOF;

    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        dataStreamPipeInVecInst[handlerIdx] = toPipeIn(dataStreamPipeInQueueVec[handlerIdx]);
    end

    Arbiter_IFC#(PCIE_RX_HANDLER_CNT) arbiter <- mkArbiter(False);

    Reg#(PcieRxHandlerIdx) curInputChannleIdxReg <- mkReg(0);
    
    Reg#(Bool) isForwardFirstBeatReg <- mkReg(True); 

    rule sendArbitReq if (isForwardFirstBeatReg);
        for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
            if (dataStreamPipeInQueueVec[handlerIdx].notEmpty) begin 
                arbiter.clients[handlerIdx].request;
            end
        end
    endrule

    rule getArbitResult if (isForwardFirstBeatReg);
        Bool isOnly = False;
        Maybe#(MemoeyMapAlignedDataStreamWithMetadata) dsWithMetaMaybe = tagged Invalid;
        PcieRxHandlerIdx selectedChannel = 0;
        for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
            if (arbiter.clients[handlerIdx].grant) begin
                let dsWithMeta = dataStreamPipeInQueueVec[handlerIdx].first;
                dataStreamPipeInQueueVec[handlerIdx].deq;
                immAssert(
                    dsWithMeta.ds.isFirst,
                    "datastream should be First",
                    $format("dsWithMeta=", fshow(dsWithMeta))
                );
                if (dsWithMeta.ds.isLast) begin
                    isOnly = True;
                end
                dsWithMetaMaybe = tagged Valid dsWithMeta;
                selectedChannel = fromInteger(handlerIdx);
            end
        end

        if (dsWithMetaMaybe matches tagged Valid .dsWithMeta) begin
            isForwardFirstBeatReg <= isOnly;
            dataStreamPipeOutQueue.enq(dsWithMeta);
            curInputChannleIdxReg <= selectedChannel;
        end
    endrule

    rule forwardMoreBeat if (!isForwardFirstBeatReg);
        let dsWithMeta = dataStreamPipeInQueueVec[curInputChannleIdxReg].first;
        dataStreamPipeInQueueVec[curInputChannleIdxReg].deq;
        dataStreamPipeOutQueue.enq(dsWithMeta);
        
        if (dsWithMeta.ds.isLast) begin
            isForwardFirstBeatReg <= True;
        end
    endrule

    interface dataStreamPipeInVec = dataStreamPipeInVecInst;
    interface dataStreamPipeOut = toPipeOut(dataStreamPipeOutQueue);
endmodule

typedef DtldStreamMemAccessMeta#(ADDR, Length) PcieStreamMeta;
typedef DtldStreamData#(PcieDataStreamDataLsbRight) PcieStreamData;


typedef struct {
    PcieHeaderFieldLength       length;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieLengthAndByteEn deriving(FShow, Bits);


interface PcieRequestTlpHeaderGen#(numeric type channelCnt, type tData, type tAddr, type tLen);
    interface DtldStreamSlavePipes#(tData, tAddr, tLen) dtldStreamSlavePipes;
    interface PipeIn#(PcieTlpHeaderCompletion)          cpltTlpHeaderPipeIn;
    interface PipeIn#(DtldStreamData#(tData))           cpltTlpDataStreamPipeIn;
    

    interface PipeIn#(Bit#(TLog#(channelCnt)))                                  writeSourceChannelIdPipeIn;
    interface PipeIn#(Bit#(TLog#(channelCnt)))                                  readSourceChannelIdPipeIn;

    interface Vector#(channelCnt, PipeOut#(PcieCompletionBufferSlotAllocReq))   tagAllocPipeOutVec;
    interface Vector#(channelCnt, PipeIn#(PcieHeaderFieldExtendedTag))          tagAllocPipeInVec;

    interface PipeOut#(PcieTlpHeaderBuffer)                                     tlpHeaderBufferPipeOut;
    interface PipeOut#(DtldStreamData#(tData))                                          tlpDataStreamPipeOut;
endinterface

module mkPcieRequestTlpHeaderGen(PcieRequestTlpHeaderGen#(channelCnt, tData, tAddr, tLen)) provisos (
        Bits#(tData, szData),
        Bits#(tAddr, szAddr),
        Bits#(tLen,  szLen),
        Add#(a__, szLen, szAddr),
        Add#(d__, 2, szAddr),
        Arith#(tAddr),
        Bitwise#(tAddr),
        Eq#(tAddr),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        Add#(b__, PCIE_HEADER_FIELD_64_BIT_ADDR_WIDTH, szAddr),
        Add#(c__, PCIE_HEADER_FIELD_LENGTH_WIDTH, szAddr),
        FShow#(DtldStreamData#(tData))
    );


    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))  slaveSideQueueWm         <- mkFIFOF;
    FIFOF#(DtldStreamData#(tData))                 slaveSideQueueWd         <- mkFIFOF;
    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))  slaveSideQueueRm         <- mkFIFOF;
    FIFOF#(DtldStreamData#(tData))                 slaveSideQueueRd         <- mkFIFOF;

    FIFOF#(DtldStreamData#(tData)) cpltTlpDataStreamPipeInQueue    <- mkFIFOF;

    FIFOF#(tChannelIdx)    writeSourceChannelIdPipeInQueue  <- mkFIFOF;
    FIFOF#(tChannelIdx)    readSourceChannelIdPipeInQueue   <- mkFIFOF;

    FIFOF#(tChannelIdx)    readTagAllocKeepOrderQueue       <- mkFIFOF;

    Vector#(channelCnt, FIFOF#(PcieCompletionBufferSlotAllocReq))       tagAllocPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(channelCnt, FIFOF#(PcieHeaderFieldExtendedTag))             tagAllocPipeInQueueVec  <- replicateM(mkFIFOF);

    Vector#(channelCnt, PipeOut#(PcieCompletionBufferSlotAllocReq))     tagAllocPipeOutVecInst  = newVector;
    Vector#(channelCnt, PipeIn#(PcieHeaderFieldExtendedTag))            tagAllocPipeInVecInst   = newVector;

    FIFOF#(PcieTlpHeaderMemoryRead4Dw)  readTlpQueue                <- mkFIFOF;
    FIFOF#(PcieTlpHeaderMemoryWrite4Dw) writeTlpQueue               <- mkFIFOF;
    FIFOF#(PcieTlpHeaderCompletion)     cpltTlpQueue                <- mkFIFOF;

    FIFOF#(PcieTlpHeaderBuffer)         arbittedTlpBufferQueue      <- mkFIFOF;
    FIFOF#(DtldStreamData#(tData))      arbittedTlpDataStreamQueue  <- mkFIFOF;
    Reg#(Bool)                          isOutputingPayloadStreamReg <- mkReg(False);

    
    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))  tagAllocToReadTlpGenPipelineQ         <- mkFIFOF;

    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        tagAllocPipeOutVecInst[channelIdx] = toPipeOut(tagAllocPipeOutQueueVec[channelIdx]);
        tagAllocPipeInVecInst[channelIdx]  = toPipeIn(tagAllocPipeInQueueVec[channelIdx]);
    end

    rule genTlpMwr;
        
        let wm = slaveSideQueueWm.first;
        slaveSideQueueWm.deq;

        // TODO: can reduce the bit width of the add operation.
        tAddr endAddr = wm.addr + unpack(zeroExtend(pack(wm.totalLen))) - 1;
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

        tAddr endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1; 

        let req = PcieCompletionBufferSlotAllocReq {
            userdata: ?,
            firstDwInvalidByteNum: truncate(pack(rm.addr)),
            lastDwInvalidByteNum: maxBound - truncate(pack(endAddr))
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
        tAddr endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1;
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
    //     tAddr endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1;
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


interface RTilePcie;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
    interface PipeOut#(PcieTxBeat) pcieTxPipeOut;
    interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVec;
endinterface

module mkRTilePcie(RTilePcie);
    let pcieRxStreamSegmentFork <- mkPcieRxStreamSegmentFork;

    Vector#(PCIE_RX_HANDLER_CNT, TlpDemuxAndConvertToMemMapStream) rxTlpHandlerVec <- replicateM(mkTlpDemuxAndConvertToMemMapStream);

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, PcieCompletionBuffer) cpltBufferVec = newVector;

    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DataStreamArbiterForCompletionBuffer) cpltBufferArbiterVec <- replicateM(mkDataStreamArbiterForCompletionBuffer);

    for (Integer channelIdx = 0; channelIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
        cpltBufferVec[channelIdx] <- mkPcieCompletionBuffer(fromInteger(channelIdx));

        mkConnection(cpltBufferArbiterVec[channelIdx].dataStreamPipeOut, cpltBufferVec[channelIdx].dataStreamPipeIn);
        
    end

    Vector#(TLP_HEADER_TX_ARBITTER_COUNT, DtldStreamArbiterSlave#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PcieDataStreamDataLsbRight, ADDR, Length)) arbiterVec <- replicateM(mkDtldStreamArbiterSlave(valueOf(PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT), False));
    Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVecInst = newVector;

    streamSlaveIfcVecInst[0] = arbiterVec[0].slaveIfcVec[0];
    streamSlaveIfcVecInst[1] = arbiterVec[0].slaveIfcVec[1];
    streamSlaveIfcVecInst[2] = arbiterVec[1].slaveIfcVec[0];
    streamSlaveIfcVecInst[3] = arbiterVec[1].slaveIfcVec[1];
    // Since the read data pipeout doesn't come from arbiter, but from the cplt buffer, so only overwrite this interface
    streamSlaveIfcVecInst[0].readPipeIfc.readDataPipeOut = cpltBufferVec[0].dataStreamPipeOut;
    streamSlaveIfcVecInst[1].readPipeIfc.readDataPipeOut = cpltBufferVec[1].dataStreamPipeOut;
    streamSlaveIfcVecInst[2].readPipeIfc.readDataPipeOut = cpltBufferVec[2].dataStreamPipeOut;
    streamSlaveIfcVecInst[3].readPipeIfc.readDataPipeOut = cpltBufferVec[3].dataStreamPipeOut;

    Vector#(TLP_HEADER_TX_ARBITTER_COUNT, PcieRequestTlpHeaderGen#(CHANNEL_PER_TLP_HEADER_TX_ARBITTER, PcieDataStreamDataLsbRight, ADDR, Length)) tlpHeaderGenVec <- replicateM(mkPcieRequestTlpHeaderGen);
    let tlpHeaderAndDataCombinator <- mkTlpHeaderAndDataCombinator;

    for (Integer idx = 0; idx < valueOf(TLP_HEADER_TX_ARBITTER_COUNT); idx = idx + 1) begin
        mkConnection(arbiterVec[idx].masterIfc.writePipeIfc.writeMetaPipeOut, tlpHeaderGenVec[idx].dtldStreamSlavePipes.writePipeIfc.writeMetaPipeIn);
        mkConnection(arbiterVec[idx].masterIfc.writePipeIfc.writeDataPipeOut, tlpHeaderGenVec[idx].dtldStreamSlavePipes.writePipeIfc.writeDataPipeIn);
        mkConnection(arbiterVec[idx].masterIfc.readPipeIfc.readMetaPipeOut, tlpHeaderGenVec[idx].dtldStreamSlavePipes.readPipeIfc.readMetaPipeIn);
        // read resp comes back out of order and handled by cplt buffer, so doesn't need go back through this arbiter.
        // mkConnection(arbiterVec[idx].masterIfc.readPipeIfc.readDataPipeIn, tlpHeaderGenVec[idx].dtldStreamSlavePipes.readPipeIfc.readDataPipeOut);

        mkConnection(arbiterVec[idx].writeSourceChannelIdPipeOut, tlpHeaderGenVec[idx].writeSourceChannelIdPipeIn);
        mkConnection(arbiterVec[idx].readSourceChannelIdPipeOut, tlpHeaderGenVec[idx].readSourceChannelIdPipeIn);

        mkConnection(tlpHeaderGenVec[idx].tagAllocPipeOutVec[0], cpltBufferVec[idx * 2 + 0].tagAllocPipeIn);
        mkConnection(tlpHeaderGenVec[idx].tagAllocPipeOutVec[1], cpltBufferVec[idx * 2 + 1].tagAllocPipeIn);

        mkConnection(cpltBufferVec[idx * 2 + 0].tagAllocPipeOut, tlpHeaderGenVec[idx].tagAllocPipeInVec[0]);
        mkConnection(cpltBufferVec[idx * 2 + 1].tagAllocPipeOut, tlpHeaderGenVec[idx].tagAllocPipeInVec[1]);

        mkConnection(tlpHeaderGenVec[idx].tlpHeaderBufferPipeOut, tlpHeaderAndDataCombinator.tlpHeaderBufferPipeInVec[idx]);
        mkConnection(tlpHeaderGenVec[idx].tlpDataStreamPipeOut, tlpHeaderAndDataCombinator.tlpDataStreamPipeInVec[idx]);
    end


    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        mkConnection(pcieRxStreamSegmentFork.tlpDataStreamPipeOutVec[handlerIdx], rxTlpHandlerVec[handlerIdx].tlpDataStreamPipeIn);
        mkConnection(pcieRxStreamSegmentFork.tlpHeaderPipeOutVec[handlerIdx], rxTlpHandlerVec[handlerIdx].tlpHeaderPipeIn);

        for (Integer channelIdx = 0; channelIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); channelIdx = channelIdx + 1) begin

            mkConnection(rxTlpHandlerVec[handlerIdx].tlpCpltDataStreamPipeOutVec[channelIdx], cpltBufferArbiterVec[channelIdx].dataStreamPipeInVec[handlerIdx]);
        
            rule discardTlpHeader;
                
                rxTlpHandlerVec[handlerIdx].tlpCpltHeaderPipeOutVec[channelIdx].deq;
                
            endrule
        end
    end


    interface pcieRxPipeIn      = pcieRxStreamSegmentFork.pcieRxPipeIn;
    interface streamSlaveIfcVec = streamSlaveIfcVecInst;
    interface pcieTxPipeOut     = tlpHeaderAndDataCombinator.pcieTxPipeOut;
endmodule



interface RTilePcieWithRawIfc;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rxRawIfc;

    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx txRawIfc;

    interface Vector#(GEARBOX_LOGIC_SIDE_CHANNEL_CNT, DtldStreamSlavePipesWide)     streamSlaveIfcVec;
endinterface

module mkRTilePcieWithRawIfc(RTilePcieWithRawIfc);
    let inner <- mkRTilePcie;
    let rawInterfaceAdaptor <- mkRTilePcieAdaptor;

    mkConnection(rawInterfaceAdaptor.pcieRxPipeOut, inner.pcieRxPipeIn);
    mkConnection(rawInterfaceAdaptor.pcieTxPipeIn, inner.pcieTxPipeOut);

    interface rxRawIfc = rawInterfaceAdaptor.rx;
    interface txRawIfc = rawInterfaceAdaptor.tx;
    interface streamSlaveIfcVec = inner.streamSlaveIfcVec;
endmodule