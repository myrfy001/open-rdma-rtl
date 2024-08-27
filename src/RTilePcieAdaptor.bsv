import Vector :: *;
import FIFOF :: *;
import PcieTypes :: *;
import Cntrs :: *;

import PrimUtils :: *;

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

    FIFOF#(PcieRxBeat) pcieRxQueue <- mkUGFIFOF;
    FIFOF#(PcieRxBeat) pcieTxQueue <- mkUGFIFOF;

    Reg#(Bool) txReadySignalOutputReg <- mkReg(False);

    Bool txValid = pcieTxQueue.notEmpty && txReadySignalOutputReg;

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
                    pcieRxQueue.notFull,
                    "pcieRxQueue is Full",
                    $format("")
                );

                pcieRxQueue.enq(beat);
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
        
        method PcieTlpHeaderBusSegBundle    header = txValid ? pcieTxQueue.first.header : unpack(0);
        method PcieTlpDataBusSegBundle      data = txValid ? pcieTxQueue.first.data : unpack(0);

        method SopSignalBundle              sop = txValid ? pcieTxQueue.first.sop : unpack(0);
        method EopSignalBundle              eop = txValid ? pcieTxQueue.first.eop : unpack(0);
        method HvalidSignalBundle           hvalid = txValid ? pcieTxQueue.first.hvalid : unpack(0);
        method DvalidSignalBundle           dvalid = txValid ? pcieTxQueue.first.dvalid : unpack(0);
    endinterface
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