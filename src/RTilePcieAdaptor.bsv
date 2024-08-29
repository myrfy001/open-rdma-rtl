import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import PcieTypes :: *;
import Cntrs :: *;

import DataTypes :: *;
import PAClib :: *;
import ConnectableF :: *;
import PrimUtils :: *;

import StreamShifterG :: *;

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
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, PCIE_SEGMENT_CNT) PCIE_TLP_DATA_BUFFER_WIDTH;
typedef Bit#(PCIE_TLP_DATA_BUFFER_WIDTH) PcieTlpDataBuffer;
typedef Vector#(PCIE_SEGMENT_CNT, PcieTlpDataBuffer) PcieTlpDataBusSegBundle;

typedef Bit#(PCIE_SEGMENT_CNT) SopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) EopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) HvalidSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) DvalidSignalBundle;

typedef 12 CREDIT_COUNTER_WIDTH;
typedef Bit#(CREDIT_COUNTER_WIDTH) CreditCount;


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

typedef Bit#(PCIE_TLP_DATA_BUNDLE_WIDTH) PcieDataStreamData;
typedef Bit#(TAdd#(1, TLog#(TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, BYTE_WIDTH)))) PcieDataStreamByteCnt;
typedef Bit#(TLog#(TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, BYTE_WIDTH))) PcieDataStreamByteIdx;

typedef StreamShifterStream#(PcieDataStreamData, PcieDataStreamByteCnt, PcieDataStreamByteIdx) PcieDataStreamLsbRight;
typedef StreamShifterStream#(PcieDataStreamData, PcieDataStreamByteCnt, PcieDataStreamByteIdx) PcieDataStreamLsbLeft;

`define PCIE_TLP_HEADER_FMT_3DW_NO_DATA             3'b000
`define PCIE_TLP_HEADER_FMT_4DW_NO_DATA             3'b001
`define PCIE_TLP_HEADER_FMT_3DW_WITH_DATA           3'b010
`define PCIE_TLP_HEADER_FMT_4DW_WITH_DATA           3'b011

`define PCIE_TLP_HEADER_TYPE_MEM_READ               5'b00000
`define PCIE_TLP_HEADER_TYPE_MEM_WRITE              5'b00000
`define PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA          5'b01010

interface PcieRxStreamSegmentFork;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
    interface Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(PcieDataStreamLsbRight)) tlpDataStreamPipeOutVec;
    interface Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(PcieTlpHeaderBuffer)) tlpHeaderPipeOutVec;
endinterface

module mkPcieRxStreamSegmentFork(PcieRxStreamSegmentFork);
    FIFOF#(PcieRxBeat) pcieRxPipeInQueue <- mkFIFOF;

    Reg#(PcieRxHandlerIdx) curPrimHandlerIdxReg <- mkReg(0);

    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(PcieDataStreamLsbRight)) tlpDataStreamPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(PcieTlpHeaderBuffer)) tlpHeaaderPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(PcieDataStreamLsbRight)) tlpDataStreamPipeOutInstVec = newVector;
    Vector#(PCIE_RX_HANDLER_CNT, PipeOut#(PcieTlpHeaderBuffer)) tlpHeaaderPipeOutInstVec = newVector;

    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        tlpDataStreamPipeOutInstVec[handlerIdx] = toPipeOut(tlpDataStreamPipeOutQueueVec[handlerIdx]);
        tlpHeaaderPipeOutInstVec[handlerIdx] = toPipeOut(tlpHeaaderPipeOutQueueVec[handlerIdx]);
    end

    Reg#(Bool) prevTlpSpanNextBeatReg <- mkReg(False);

    Vector#(PCIE_RX_HANDLER_CNT, FIFOF#(RawPcieRxStreamWithMeta)) handlerInputQueueVec <- replicateM(mkFIFOF);

    rule preCalcRxBeatMeta;
        let beat = pcieRxPipeInQueue.first;
        pcieRxPipeInQueue.deq;

        Bool isTlpSpanNextBeat = case (pack(beat.eop)) matches
            'b1???: False;
            'b01??: (beat.sop[3] == 1);
            'b001?: (beat.sop[3] == 1 || beat.sop[2] == 1);
            'b0001: (beat.sop[3] == 1 || beat.sop[2] == 1 || beat.sop[1] == 1);
            'b0000: True;
        endcase;

        prevTlpSpanNextBeatReg <= isTlpSpanNextBeat;

        PcieSegmentIdx tlpCnt = case (pack((beat.sop))) matches
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


        Vector#(PCIE_RX_HANDLER_CNT, Maybe#(PcieSegmentIdx)) tlpFirstSegmentIdxVec = case (pack((beat.sop))) matches
            'b0000: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Invalid, tagged Valid 0) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b0001: vec(tagged Invalid, tagged Invalid, tagged Valid 0);
            'b0010: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Valid 1, tagged Valid 0) : vec(tagged Invalid, tagged Invalid, tagged Valid 1));
            'b0011: vec(tagged Invalid, tagged Valid 1, tagged Valid 0);
            'b0100: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Valid 2, tagged Valid 0) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b0101: vec(tagged Invalid, tagged Valid 2, tagged Valid 0);
            'b0110: (prevTlpSpanNextBeatReg ? vec(tagged Valid 2, tagged Valid 1, tagged Valid 0) : vec(tagged Invalid, tagged Valid 2, tagged Valid 1));
            'b0111: vec(tagged Valid 2, tagged Valid 1, tagged Valid 0);
            'b1000: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Valid 3, tagged Valid 0) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b1001: vec(tagged Invalid, tagged Valid 3, tagged Valid 0);
            'b1010: (prevTlpSpanNextBeatReg ? vec(tagged Valid 3, tagged Valid 1, tagged Valid 0) : vec(tagged Invalid, tagged Valid 3, tagged Valid 1));
            'b1011: vec(tagged Valid 3, tagged Valid 1, tagged Valid 0);
            'b1100: (prevTlpSpanNextBeatReg ? vec(tagged Valid 3, tagged Valid 2, tagged Valid 0) : vec(tagged Invalid, tagged Invalid, tagged Invalid));
            'b1101: vec(tagged Valid 3, tagged Valid 2, tagged Valid 0);
            'b1110: (prevTlpSpanNextBeatReg ? vec(tagged Invalid, tagged Invalid, tagged Invalid) : vec(tagged Valid 3, tagged Valid 2, tagged Valid 1));
            'b1111: vec(tagged Invalid, tagged Invalid, tagged Invalid);
        endcase;

        for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
            if (tlpFirstSegmentIdxVec[handlerIdx] matches tagged Valid .startSegIdx) begin
                let ent = RawPcieRxStreamWithMeta {
                    rxBeat: beat,
                    startSegIdx: startSegIdx
                };

                let curPrimHandlerIdxWide = {1'b0, pack(curPrimHandlerIdxReg)};
                curPrimHandlerIdxWide = curPrimHandlerIdxWide + fromInteger(handlerIdx);
                if (curPrimHandlerIdxWide > fromInteger(valueOf(PCIE_RX_HANDLER_CNT) - 1)) begin
                    curPrimHandlerIdxWide = curPrimHandlerIdxWide - fromInteger(valueOf(PCIE_RX_HANDLER_CNT) - 1);
                end

                PcieRxHandlerIdx curPrimHandlerIdx = truncate(curPrimHandlerIdxWide);

                handlerInputQueueVec[curPrimHandlerIdx].enq(ent);
            end
        end

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

    for (Integer handlerIdx = 0; handlerIdx < valueOf(PCIE_RX_HANDLER_CNT); handlerIdx = handlerIdx + 1) begin
        rule rawPcieRxInputToInternalDataType;
            let beat = handlerInputQueueVec[handlerIdx].first;
            handlerInputQueueVec[handlerIdx].deq;

            let sopBundle = beat.rxBeat.sop;
            let eopBundle = beat.rxBeat.eop;

            let isFirst = sopBundle[beat.startSegIdx] == 1;
            // for non-first beat, if there is at least one eop, then this beat must be eop.
            Bool notFirstBeatIsEop = pack(eopBundle) != 0;

            Bool firstBeatIsEop = case (beat.startSegIdx)
                0: (eopBundle[3:0] != 0);
                1: (eopBundle[3:1] != 0);
                2: (eopBundle[3:2] != 0);
                3: (eopBundle[3:3] != 0);
            endcase;

            Bool isLast = isFirst ? firstBeatIsEop : notFirstBeatIsEop;

            let tlpDataLenMaybe = getDataLenFromTlpHeader(beat.rxBeat.header);

            // let ds = PcieDataStreamLsbRight {
            //     data: beat.rxBeat.data,
            //     byteNum: 
            //     startByteIdx: 
            //     isFirst: isFirst,
            //     isLast: isLast
            // };

        endrule
    end


    interface pcieRxPipeIn = toPipeIn(pcieRxPipeInQueue);
    interface tlpDataStreamPipeOutVec = tlpDataStreamPipeOutInstVec;
    interface tlpHeaderPipeOutVec = tlpHeaaderPipeOutInstVec;
endmodule

function Bool isPcieTlpHasPayload(PcieTlpHeaderBuffer tlpBuffer);
    PcieHeaderFieldFmt fmt = unpack(truncateLSB(tlpBuffer));
    return fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA || fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA;
endfunction

function Maybe#(PcieTlpDataByteLen) getDataLenFromTlpHeader(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = unpack(truncateLSB(tlpBuffer));

    PcieTlpDataByteLen length = zeroExtend(headerFirstDW.commonHeader.length);
    length[valueOf(SizeOf#(PcieHeaderFieldLength))] = pack(headerFirstDW.commonHeader.length == 0);  // length == 0 means 4096 bytes
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
            return tagged Valid isLastCplt ? extendedByteCount : adjustedLength;
        end
        else begin
            return tagged Invalid;
        end
    end
endfunction
