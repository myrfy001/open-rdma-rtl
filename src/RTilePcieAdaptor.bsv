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
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, PCIE_SEGMENT_CNT) PCIE_TLP_DATA_SEGMENT_WIDTH;
typedef TDiv#(PCIE_TLP_DATA_SEGMENT_WIDTH, BYTE_WIDTH) PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH;
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
        PcieTlpHeaderBusSegBundle       header,
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
    
    method PcieTlpHeaderBusSegBundle    header;
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

    interface RTilePcieAdaptorRx rx;
        // input port
        method Action setRxInputData(
            PcieTlpDataBusSegBundle         data,
            PcieTlpHeaderBusSegBundle       header,
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
                    header: header,
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
        
        method PcieTlpHeaderBusSegBundle    header = txValid ? pcieTxPipeInQueue.first.header : unpack(0);
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

typedef StreamShifterStream#(PcieDataStreamDataLsbRight, PcieDataStreamByteCnt, PcieDataStreamByteIdx) PcieDataStreamLsbRight;
typedef StreamShifterStream#(PcieDataStreamDataLsbLeft, PcieDataStreamByteCnt, PcieDataStreamByteIdx) PcieDataStreamLsbLeft;


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

            return tagged Valid ((targetLowerDwAddr - sourceLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA) begin
            PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

            PcieDataStreamByteCnt targetLowerDwAddr = zeroExtend(tlpHeader.lowerAddress) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);

            return tagged Valid ((targetLowerDwAddr - sourceLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
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

typedef StreamShifterG#(PcieDataStreamDataLsbLeft, PcieDataStreamByteCnt, PcieDataStreamByteIdx) PcieStreamShifter;

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

    PcieStreamShifter streamShifter <- mkBiDirectionStreamShifterG;

    FIFOF#(MetaForReceivedTlpDispatch) tlpHeaderDispatchMetaQueue <- mkFIFOF;
    FIFOF#(MetaForReceivedTlpDispatch) tlpDataDispatchMetaQueue <- mkFIFOF;

    FIFOF#(RawPcieRxTlpWithMeta) tlpHeaderForDispatchPipeQueue <- mkFIFOF;

    rule reverseAndForwardDataStreamToShifter;
        PcieDataStreamLsbRight dsInput = tlpDataStreamPipeInQueue.first;
        tlpDataStreamPipeInQueue.deq;

        let startByteIdx = dsInput.isFirst ? (
            fromInteger(valueOf(PCIE_TLP_DATA_BUNDLE_BYTE_CNT)) - (dsInput.byteNum + zeroExtend(dsInput.startByteIdx))
        ) : (0);

        PcieDataStreamLsbLeft dsOutput = PcieDataStreamLsbLeft {
            data: unpack(swapEndianByte(pack(dsInput.data))),
            byteNum: dsInput.byteNum,
            startByteIdx: truncate(startByteIdx),
            isFirst: dsInput.isFirst,
            isLast: dsInput.isLast
        };

        streamShifter.streamPipeIn.enq(dsOutput);
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
    endrule

    rule dispatchOutputDataStream;
        let shiftedLeftAlignedStream = streamShifter.streamPipeOut.first;
        streamShifter.streamPipeOut.deq;

        let dispatchMeta = tlpDataDispatchMetaQueue.first;
        if (shiftedLeftAlignedStream.isLast) begin
            tlpDataDispatchMetaQueue.deq;
        end

        let startByteIdx = shiftedLeftAlignedStream.isFirst ? (
            fromInteger(valueOf(PCIE_TLP_DATA_BUNDLE_BYTE_CNT)) - (shiftedLeftAlignedStream.byteNum + zeroExtend(shiftedLeftAlignedStream.startByteIdx))
        ) : (0);

        // Since the AXI-MM use right aligned foramt, reverse it again.
        PcieDataStreamLsbRight shiftedRightAlignedStream = PcieDataStreamLsbRight {
            data        : unpack(swapEndianByte(pack(shiftedLeftAlignedStream.data))),
            byteNum     : shiftedLeftAlignedStream.byteNum,
            startByteIdx: truncate(startByteIdx),
            isFirst     : shiftedLeftAlignedStream.isFirst,
            isLast      : shiftedLeftAlignedStream.isLast
        };

        let outputDataStreamWithMeta = MemoeyMapAlignedDataStreamWithMetadata {
            ds              : shiftedRightAlignedStream,
            tagHigherPart   : truncateLSB(dispatchMeta.extTag),
            isLastCplt      : dispatchMeta.isLastCplt
        };

        DispatchChannelIdx dispatchIdx = truncate(dispatchMeta.extTag);
        if (dispatchMeta.isCplt) begin
            tlpCpltDataStreamPipeOutQueueVec[dispatchIdx].enq(outputDataStreamWithMeta);
            $display("outputDataStreamWithMeta=", fshow(outputDataStreamWithMeta));
        end
        else begin
            tlpMemReqDataStreamPipeOutQueue.enq(shiftedRightAlignedStream);
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

typedef PCIE_EXTENDED_TAG_HIGH_PART_WIDTH PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH;
typedef TLog#(PCIE_COMPLETION_BUFFER_INTERNAL_BUFFER_ROW_PER_SLOT) PCIE_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH;

typedef TAdd#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH, PCIE_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH) PCIE_COMPLETION_BUFFER_INNER_STORAGE_ROW_INDEX_WIDTH;

typedef Bit#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH)           PcieCompletionBufferSlotIdx;
typedef Bit#(TLog#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE)) PcieCompletionBufferSlotCnt;

typedef Bit#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INNER_ROW_INDEX_WIDTH) PcieCompletionBufferSlotInnerRowIdx;
typedef Bit#(PCIE_COMPLETION_BUFFER_INNER_STORAGE_ROW_INDEX_WIDTH)  PcieCompletionBufferInnerStorageRowIdx;


typedef struct {
    PcieCompletionBufferSlotUserData userdata;
} PcieCompletionBufferSlotAllocReq deriving(Bits, FShow);

typedef struct {
    PcieCompletionBufferSlotUserData        userdata;
    PcieCompletionBufferSlotInnerRowIdx     writePtr;
    PcieCompletionBufferSlotIdx             slotIdx;
    Bool                                    isCompleted;
    Bool                                    isFirstBeat;
    Bool                                    isFirstRow;
    PcieDataStreamByteIdx                   startByteIdx;
    PcieDataStreamByteCnt                   firstBeatByteNum;
    PcieDataStreamByteCnt                   lastBeatByteNum;
} PcieCompletionBufferSlotMeta deriving(Bits, FShow);

// typedef struct {
//     DataStreamMeta#(PcieDataStreamByteCnt, PcieDataStreamByteIdx) dataStreamMeta;
// } PcieCompletionBufferRowMeta deriving(Bits, FShow);

typedef enum {
    PcieCompletionBufferOutputStateSendStateQueryReq = 0,
    PcieCompletionBufferOutputStateWaitStateQueryResp = 1
} PcieCompletionBufferOutputState deriving(Bits, Eq, FShow);

module mkPcieCompletionBuffer#(DispatchChannelIdx channelIdx)(PcieCompletionBuffer);

    FIFOF#(PcieCompletionBufferSlotAllocReq) tagAllocPipeInQueue <- mkFIFOF;
    FIFOF#(PcieHeaderFieldExtendedTag) tagAllocPipeOutQueue <- mkFIFOF;
    FIFOF#(MemoeyMapAlignedDataStreamWithMetadata) dataStreamPipeInQueue <- mkFIFOF;
    FIFOF#(PcieDataStreamLsbRight) dataStreamPipeOutQueue <- mkFIFOF;


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
    FIFOF#(DataStreamMeta#(PcieDataStreamByteCnt, PcieDataStreamByteIdx))   outputStreamMetaPipelineQueue                       <- mkFIFOF;

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
                userdata: req.userdata,
                writePtr: 0,
                slotIdx: headReg,
                isCompleted: False,
                isFirstBeat: True,
                isFirstRow: True,
                startByteIdx: 0,
                firstBeatByteNum: 0,
                lastBeatByteNum: 0
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
        end

    endrule

    rule handleStreamInput;
        let inputStreamWithMeta = dataStreamPipeInQueue.first;
        dataStreamPipeInQueue.deq;

        $display("inputStreamWithMeta=", fshow(inputStreamWithMeta));

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
        end
    endrule

    rule sendSlotRowDataReadReq;
        let curSlotMeta = outputSlotMetaForSendReadReqPipelineQueue.first;
        if (curReadOutReqPtrReg == curReadOutReqPtrTargetReg) begin
            // This beat is the start of a new output Stream;
            
            curReadOutReqPtrReg <= 0;
            curReadOutReqPtrTargetReg <= curSlotMeta.writePtr;
            curReadOutReqSlotIdx <= curSlotMeta.slotIdx;


            dataStreamStorageVec[0].putReadReq(unpack({pack(curSlotMeta.slotIdx), 0}));
            dataStreamStorageVec[1].putReadReq(unpack({pack(curSlotMeta.slotIdx), 0}));


            let isOnly = curSlotMeta.writePtr == 0;
            let dataStreamMeta = DataStreamMeta {
                byteNum: curSlotMeta.firstBeatByteNum,
                startByteIdx: curSlotMeta.startByteIdx,
                isFirst: True,
                isLast: isOnly
            };
            outputStreamMetaPipelineQueue.enq(dataStreamMeta);

            if (isOnly) begin
                outputSlotMetaForSendReadReqPipelineQueue.deq;
                newCompleteSlotSignal[2] <= True;
            end
        end
        else begin
            let newPtr = curReadOutReqPtrReg + 1;
            curReadOutReqPtrReg <= newPtr;
            dataStreamStorageVec[0].putReadReq(unpack({pack(curReadOutReqSlotIdx), pack(newPtr)}));
            dataStreamStorageVec[1].putReadReq(unpack({pack(curReadOutReqSlotIdx), pack(newPtr)}));

            let isLast = newPtr == curReadOutReqPtrTargetReg;
            let dataStreamMeta = DataStreamMeta {
                byteNum: isLast ? curSlotMeta.lastBeatByteNum : fromInteger(valueOf(PCIE_TLP_DATA_BUNDLE_BYTE_CNT)),
                startByteIdx: 0,
                isFirst: False,
                isLast: isLast
            };
            outputStreamMetaPipelineQueue.enq(dataStreamMeta);

            if (isLast) begin
                outputSlotMetaForSendReadReqPipelineQueue.deq;
                newCompleteSlotSignal[2] <= True;
            end
        end
    endrule

    rule receiveDataStreamRowDataAndOutput;
        let streamLowerPart = dataStreamStorageVec[0].readRespPipeOut.first;
        let streamHigherPart = dataStreamStorageVec[1].readRespPipeOut.first;
        let streamMeta = outputStreamMetaPipelineQueue.first;

        dataStreamStorageVec[0].readRespPipeOut.deq;
        dataStreamStorageVec[1].readRespPipeOut.deq;
        outputStreamMetaPipelineQueue.deq;

        PcieDataStreamLsbRight ds = StreamShifterStream {
            data: unpack({streamHigherPart, streamLowerPart}),
            byteNum: streamMeta.byteNum,
            startByteIdx: streamMeta.startByteIdx,
            isFirst: streamMeta.isFirst,
            isLast: streamMeta.isLast
        };
        dataStreamPipeOutQueue.enq(ds);

        if (ds.isLast) begin
            if (tailReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                tailReg <=fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
            end 
            else begin
                tailReg <= tailReg + 1;
            end
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


typedef struct {
    PcieHeaderFieldLength       length;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieLengthAndByteEn deriving(FShow, Bits);

interface ExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream#(type tAxiData);
    interface PipeIn#(AxiMmBeatW#(tAxiData)) axiWriteBeatPipeIn;
    interface PipeOut#(StreamShifterStream#(tAxiData, Bit#(TLog#(TAdd#(1,TDiv#(SizeOf#(tAxiData), BYTE_WIDTH)))), Bit#(TLog#(TDiv#(SizeOf#(tAxiData), BYTE_WIDTH))))) dataStreamPipeOut;
    interface PipeOut#(PcieLengthAndByteEn) lengthAndByteEnPipeOut;
endinterface

module mkExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream(ExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream#(tAxiData)) provisos (
        Bits#(tAxiData, szAxiData),
        Alias#(Bit#(TDiv#(szAxiData, BYTE_WIDTH)), tByteEn),
        Alias#(Bit#(TDiv#(szAxiData, DWORD_WIDTH)), tDwordEn),
        Bits#(tByteEn, szByteEn),
        Bits#(tDwordEn, szDwordEn),
        Alias#(Bit#(TDiv#(DWORD_WIDTH, BYTE_WIDTH)), tByteEnForDword),
        Bits#(Vector#(TDiv#(szAxiData, DWORD_WIDTH), tByteEnForDword), szByteEn),
        Add#(1, a__, TLog#(TAdd#(1, szDwordEn))),
        Add#(1, b__, TDiv#(szAxiData, DWORD_WIDTH)),
        Add#(c__, TLog#(TAdd#(1, szDwordEn)), SizeOf#(PcieHeaderFieldLength)),
        Add#(f__, TLog#(szByteEn), TLog#(TAdd#(1, szByteEn))),
        Mul#(BYTE_WIDTH, d__, szAxiData),
        Add#(1, e__, TLog#(TAdd#(1, szByteEn)))
    );
    FIFOF#(AxiMmBeatW#(tAxiData)) axiWriteBeatPipeInQueue <- mkFIFOF;
    FIFOF#(StreamShifterStream#(tAxiData, Bit#(TLog#(TAdd#(1,TDiv#(SizeOf#(tAxiData), BYTE_WIDTH)))), Bit#(TLog#(TDiv#(SizeOf#(tAxiData), BYTE_WIDTH))))) dataStreamPipeOutQueue  <- mkFIFOF;
    FIFOF#(PcieLengthAndByteEn) lengthAndByteEnPipeOutQueue <- mkFIFOF;

    Reg#(Bool) isFirstBeatReg <- mkReg(True);
    Reg#(PcieHeaderFieldLength) lengthReg <- mkReg(0);
    Reg#(PcieHeaderFieldFirstDwBe) firstDwBeReg <- mkRegU;


    function tDwordEn byteEnToDwordEn(tByteEn byteEn);
        Vector#(szDwordEn, tByteEnForDword) byteEnGroupVec = unpack(pack(byteEn));
        Vector#(szDwordEn, Bool) dwordEnVec = newVector;
        for (Integer dwIdx = 0; dwIdx < valueOf(szDwordEn); dwIdx = dwIdx + 1) begin
            dwordEnVec[dwIdx] = (byteEnGroupVec[dwIdx] != 0);
        end
        return unpack(pack(dwordEnVec));
    endfunction

    function tByteEnForDword byteEnToFirstLastDwBe(tByteEn byteEn, Bool isCalcFirstDwBe, Bool isDwLengthZero, Bool isDwLengthOne);
        Vector#(szDwordEn, tByteEnForDword) byteEnGroupVec = unpack(pack(byteEn));
        
        for (Integer dwIdx = 0; dwIdx < valueOf(szDwordEn); dwIdx = dwIdx + 1) begin
            if (isCalcFirstDwBe) begin
                if (msb(byteEnGroupVec[dwIdx]) == 0 || (lsb(byteEnGroupVec[dwIdx]) == 1 && msb(byteEnGroupVec[dwIdx]) == 1)) begin
                    byteEnGroupVec[dwIdx] = 0;
                end
            end
            else begin
                if (lsb(byteEnGroupVec[dwIdx]) == 0 || (lsb(byteEnGroupVec[dwIdx]) == 1 && msb(byteEnGroupVec[dwIdx]) == 1)) begin
                    byteEnGroupVec[dwIdx] = 0;
                end
            end
        end

        tByteEnForDword ret = fold(\| , byteEnGroupVec);
        if (ret == 0 && !isDwLengthZero) begin
            ret = -1;
        end

        // if only have one DW, then the last DW EN is zero
        if (isDwLengthOne && !isCalcFirstDwBe) begin
            ret = 0;
        end
        return ret;
    endfunction

    rule preCalcDwordEn;
        let beat = axiWriteBeatPipeInQueue.first;
        axiWriteBeatPipeInQueue.deq;
        
        let dwordEn = byteEnToDwordEn(beat.wstrb);
        let byteNum = countOnes(beat.wstrb);
        let startByteIdx = countZerosMSB(beat.wstrb);  // beat is right aligned
        let validDwordCnt = countOnes(dwordEn);
        let lsbInvalidDword = countZerosLSB(dwordEn);
        let curLength = lengthReg + zeroExtend(pack(validDwordCnt));
        let isDwLengthZero = dwordEn == 0;
        let isDwLengthOne = dwordEn == 1;

        let lastDwBe = byteEnToFirstLastDwBe(beat.wstrb, False, isDwLengthZero, isDwLengthOne);
        let firstDwBe = byteEnToFirstLastDwBe(beat.wstrb, True, isDwLengthZero, isDwLengthOne);

        if (isFirstBeatReg) begin
            firstDwBeReg <= firstDwBe;
        end

        if (beat.wlast) begin
            lengthReg <= 0;
            let out = PcieLengthAndByteEn {
                length: curLength,
                lastDwBe: lastDwBe,
                firstDwBe: isFirstBeatReg ? firstDwBe : firstDwBeReg
            };
            lengthAndByteEnPipeOutQueue.enq(out);
        end
        else begin
            lengthReg <= curLength;
        end

        StreamShifterStream#(tAxiData, Bit#(TLog#(TAdd#(1,TDiv#(SizeOf#(tAxiData), BYTE_WIDTH)))), Bit#(TLog#(TDiv#(SizeOf#(tAxiData), BYTE_WIDTH)))) ds = StreamShifterStream {
            data: unpack(swapEndianByte(pack(beat.wdata))),
            byteNum: pack(byteNum),
            startByteIdx: truncate(pack(startByteIdx)),
            isFirst: isFirstBeatReg,
            isLast: beat.wlast
        };
        dataStreamPipeOutQueue.enq(ds);

    endrule

    interface axiWriteBeatPipeIn = toPipeIn(axiWriteBeatPipeInQueue);
    interface lengthAndByteEnPipeOut = toPipeOut(lengthAndByteEnPipeOutQueue);
    interface dataStreamPipeOut = toPipeOut(dataStreamPipeOutQueue);
endmodule


interface PcieRequestTlpHeaderGenAndPayloadShift#(type tAxiData);
    interface AxiSlavePipes#(tAxiData) axiSlavePipes;
endinterface


// module mkPcieRequestTlpHeaderGenAndPayloadShift(PcieRequestTlpHeaderGenAndPayloadShift#(tAxiData)) provisos (
//         Bits#(tAxiData, szAxiData),
//         Alias#(Bit#(TDiv#(szAxiData, BYTE_WIDTH)), tByteEn),
//         Alias#(Bit#(TDiv#(szAxiData, DWORD_WIDTH)), tDwordEn),
//         Alias#(Bit#(TDiv#(DWORD_WIDTH, BYTE_WIDTH)), tByteEnForDword),
//         Bits#(tByteEn, szByteEn),
//         Bits#(tDwordEn, szDwordEn),
//         Bits#(tByteEnForDword, szByteEnForDword),
//         Add#(1, b__, szDwordEn),
//         Mul#(szDwordEn, szByteEnForDword, szByteEn),
//         Add#(1, b__, TDiv#(szAxiData, DWORD_WIDTH)),
//         Add#(c__, TLog#(TAdd#(1, szDwordEn)), SizeOf#(PcieHeaderFieldLength)),
//         Add#(1, a__, TLog#(TAdd#(1, szDwordEn)))
        
//     );


//     FIFOF#(AxiMmBeatAw)            slaveSideQueueAw   <-  mkFIFOF;
//     FIFOF#(AxiMmBeatW#(tAxiData))  slaveSideQueueW    <-  mkFIFOF;
//     FIFOF#(AxiMmBeatB)             slaveSideQueueB    <-  mkFIFOF;
//     FIFOF#(AxiMmBeatAr)            slaveSideQueueAr   <-  mkFIFOF;
//     FIFOF#(AxiMmBeatR#(tAxiData))  slaveSideQueueR    <-  mkFIFOF;


//     ExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream#(tAxiData) writeStreamMetaExtractor <- mkExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream;

//     mkConnection(writeStreamMetaExtractor.axiWriteBeatPipeIn, toPipeOut(slaveSideQueueW));


//     Reg#(Bool) axiWriteToDataStreamIsFirstReg <- mkReg(True);
//     rule prepareShiftDataStream;

//         let axiBeatIn = writeStreamMetaExtractor.axiWriteBeatPipeOut.first;
//         writeStreamMetaExtractor.axiWriteBeatPipeOut.deq;


//         PcieDataStreamLsbLeft ds = PcieDataStreamLsbLeft {

//         };

//         axiWriteToDataStreamIsFirstReg <= axiBeatIn.wlast;

//     endrule








//     interface AxiSlavePipes axiSlavePipes;
//         interface AxiSlaveWritePipes writePipeIfc;
//             interface  writeAddrPipeIn  = toPipeIn(slaveSideQueueAw);
//             interface  writeDataPipeIn  = toPipeIn(slaveSideQueueW);
//             interface  writeRespPipeOut = toPipeOut(slaveSideQueueB);
//         endinterface

//         interface AxiSlaveReadPipes readPipeIfc;
//             interface  readAddrPipeIn  = toPipeIn(slaveSideQueueAr);
//             interface  readRespPipeOut = toPipeOut(slaveSideQueueR);
//         endinterface
//     endinterface
// endmodule



interface RTilePcie;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;

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

    for (Integer channelIdx = 0; channelIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
        rule testTemp1;
            cpltBufferVec[channelIdx].tagAllocPipeIn.enq(PcieCompletionBufferSlotAllocReq{userdata: fromInteger(channelIdx)});
        endrule
    end

    for (Integer channelIdx = 0; channelIdx < valueOf(GEARBOX_LOGIC_SIDE_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
        rule testTemp2;
            let outputTag = cpltBufferVec[channelIdx].tagAllocPipeOut.first;
            cpltBufferVec[channelIdx].tagAllocPipeOut.deq;
            $display("get alloc tag, channelIdx=%d", channelIdx, ", tagValue=", fshow(outputTag));
        endrule
    end
    //     interface PipeOut#(PcieHeaderFieldExtendedTag) tagAllocPipeOut;
    //     interface PipeOut#(PcieDataStreamLsbRight) dataStreamPipeOut;


    interface pcieRxPipeIn = pcieRxStreamSegmentFork.pcieRxPipeIn;
endmodule