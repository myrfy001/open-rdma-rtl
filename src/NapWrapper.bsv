import GetPut :: *;
import ClientServer :: *;
import RegFile :: *;
import FIFOF :: *;
import Vector :: *;
import Reserved :: *;

import DataTypes :: *;
import PrimUtils :: *;


typedef 4 VERTICAL_NAP_NODE_ID_WIDTH;
typedef 293 VERTICAL_NAP_DATA_WIDTH;

typedef 256 NOC_DATA_BUS_BIT_WIDTH;
typedef TDiv#(NOC_DATA_BUS_BIT_WIDTH, BYTE_WIDTH) NOC_DATA_BUS_BYTE_WIDTH;
typedef Bit#(NOC_DATA_BUS_BIT_WIDTH) NocData;

typedef Bit#(VERTICAL_NAP_NODE_ID_WIDTH) VerticalNapsrcOrDstNodeId;
typedef Bit#(VERTICAL_NAP_DATA_WIDTH) VerticalNapData;

typedef VERTICAL_NAP_DATA_WIDTH ETHERNET_NAP_DATA_WIDTH;
typedef Bit#(ETHERNET_NAP_DATA_WIDTH) EthernetNapData;

typedef 15 ETHERNET_NAP_NODE_ID; // according to UG086, the node ID of EIU is 4'hf

typedef 5 ETH_NAP_MOD_WIDTH;
typedef Bit#(ETH_NAP_MOD_WIDTH) EthernetNapMod;

typedef 30 ETH_NAP_TIMESTAMP_WIDTH;
typedef Bit#(ETH_NAP_TIMESTAMP_WIDTH) EthernetNapTimestamp;

typedef 5 ETH_NAP_SEQ_ID_WIDTH;
typedef Bit#(ETH_NAP_SEQ_ID_WIDTH) EthernetNapSeqID;


typedef struct {
    ReservedZero#(16) revd1;
    EthernetNapSeqID sequenceID;
    Bool vlan;
    Bool transmitError;
    Bool invertedCRC;
    Bool shortFrame;
    Bool fifoOverflow;
    Bool decodeError;
    Bool crcError;
    Bool lengthError;
    Bool error;
} EthernetNapRecvFlags deriving(Bits, FShow, Eq);


typedef struct {
    ReservedZero#(2) rsvd2;
    EthernetNapTimestamp timestamp;
    ReservedZero#(ETH_NAP_MOD_WIDTH) rsvd1;
    NocData data;
} EthernetNapRecvFirstBeat deriving(Bits, FShow, Eq);

typedef struct {
    ReservedZero#(2) rsvd1;
    EthernetNapRecvFlags flags;
    EthernetNapMod mod;
    NocData data;
} EthernetNapRecvOtherBeat deriving(Bits, FShow, Eq);

typedef 17 ETH_NAP_TRANSMIT_ID_FLAG_WIDTH;
typedef Bit#(ETH_NAP_TRANSMIT_ID_FLAG_WIDTH) EthernetNapTransmitID;

typedef struct {
    ReservedZero#(6) revd1;
    Bool classB;
    Bool classA;
    Bool crcOverride;
    Bool crcInvert;
    Bool crcInsert;
    Bool txError;
    Bool frame;
    EthernetNapTransmitID id;
} EthernetNapSendFlags deriving(Bits, FShow, Eq);

typedef struct {
    ReservedZero#(2) rsvd2;
    EthernetNapTimestamp timestamp;
    ReservedZero#(ETH_NAP_MOD_WIDTH) rsvd1;
    NocData data;
} EthernetNapSendFirstBeat deriving(Bits, FShow, Eq);

typedef struct {
    ReservedZero#(2) rsvd1;
    EthernetNapSendFlags flags;
    EthernetNapMod mod;
    NocData data;
} EthernetNapSendOtherBeat deriving(Bits, FShow, Eq);



interface ACX_NAP_ETHERNET_WRAPPER;
    
    // input port
    method Action tx_valid(Bool val);
    method Action tx_data(VerticalNapData val);
    method Action tx_sop(Bool val);
    method Action tx_eop(Bool val);
    method Action rx_ready(Bool val);

    // output port
    method Bool rx_valid;
    method VerticalNapsrcOrDstNodeId rx_src;
    method VerticalNapData rx_data;
    method Bool rx_sop;
    method Bool rx_eop;
    method Bool tx_ready;  
endinterface


import "BVI" ACX_NAP_ETHERNET =
module mkAcxNapEthernetWrapperInner#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(ACX_NAP_ETHERNET_WRAPPER);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    parameter tx_mode = 4'b0111;  // 400G_PKT, From UG086 Table 233
    parameter rx_mode = 4'b0111;  // 400G_PKT, From UG086 Table 233
    parameter tx_mac_id = 2'b00;  // 400G_MAC0, From UG086 Table 233
    parameter rx_mac_id = 2'b00;  // 400G_MAC0, From UG086 Table 233
    parameter tx_eiu_channel = tx_eiu_channel;
    parameter rx_eiu_channel = rx_eiu_channel;

    input_clock (clk) = clk;
    input_reset rstN(rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    port tx_dest = 4'hF;  // 400G_MAC0, From UG086 Table 233, means to EIU

    
    // input port
    method tx_valid(tx_valid) enable((*inhigh*) EN_NO_USE_1) clocked_by(clk) reset_by(no_reset);
    method tx_data(tx_data) enable((*inhigh*) EN_NO_USE_2) clocked_by(clk) reset_by(no_reset);
    method tx_sop(tx_sop) enable((*inhigh*) EN_NO_USE_3) clocked_by(clk) reset_by(no_reset);
    method tx_eop(tx_eop) enable((*inhigh*) EN_NO_USE_4) clocked_by(clk) reset_by(no_reset);
    method rx_ready(rx_ready) enable((*inhigh*) EN_NO_USE_5) clocked_by(clk) reset_by(no_reset);

    // output port
    method rx_valid rx_valid clocked_by(clk) reset_by(no_reset);
    method rx_src rx_src clocked_by(clk) reset_by(no_reset);
    method rx_data rx_data clocked_by(clk) reset_by(no_reset);
    method rx_sop rx_sop clocked_by(clk) reset_by(no_reset);
    method rx_eop rx_eop clocked_by(clk) reset_by(no_reset);
    method tx_ready tx_ready clocked_by(clk) reset_by(no_reset);  

    schedule (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready) CF (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready);
    schedule (tx_valid, tx_data, tx_sop, tx_eop) CF (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);

    schedule (rx_ready) C (rx_ready);
    schedule (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready) CF (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);


endmodule


module mkAcxNapEthernetPrimitiveWrapper#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(ACX_NAP_ETHERNET_WRAPPER);

    let inst <- mkAcxNapEthernetWrapperInner(tx_eiu_channel, rx_eiu_channel);
    return inst;
endmodule

typedef struct {
    VerticalNapsrcOrDstNodeId srcOrDstNodeId;
    VerticalNapData data;
    Bool sop;
    Bool eop;
} VerticalNapBeatEntry deriving(Bits, FShow);

typedef VerticalNapBeatEntry EthernetNapBeatEntry;


interface AcxNapEthernetWrapper;
    method Action send(VerticalNapBeatEntry beat);
    method ActionValue#(VerticalNapBeatEntry) recv;
endinterface

module mkAcxNapEthernetWrapper#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(AcxNapEthernetWrapper);

    FIFOF#(VerticalNapBeatEntry) txQ <- mkUGFIFOF;
    FIFOF#(VerticalNapBeatEntry) rxQ <- mkUGFIFOF;
    
    let ethNap <- mkAcxNapEthernetPrimitiveWrapper(tx_eiu_channel, rx_eiu_channel);

    rule forwardTxAxiSignal;
        let txBeat = txQ.first;
        ethNap.tx_valid(txQ.notEmpty);
        ethNap.tx_data(txBeat.data);
        ethNap.tx_sop(txBeat.sop);
        ethNap.tx_eop(txBeat.eop);

        if (txQ.notEmpty) begin
            if (ethNap.tx_ready) begin
                txQ.deq;
            end
        end
    endrule

    rule forwardRxAxiSignal;
        if (rxQ.notFull) begin
            ethNap.rx_ready(True);
            if (ethNap.rx_valid) begin
                let recvBeat = VerticalNapBeatEntry{
                    srcOrDstNodeId: fromInteger(valueOf(ETHERNET_NAP_NODE_ID)),
                    data: ethNap.rx_data,
                    sop: ethNap.rx_sop,
                    eop: ethNap.rx_eop
                };
                rxQ.enq(recvBeat);
            end
        end
        else begin
            ethNap.rx_ready(False);
        end
    endrule



    method Action send(VerticalNapBeatEntry beat) if (txQ.notFull);
        txQ.enq(beat);
    endmethod

    method ActionValue#(VerticalNapBeatEntry) recv if (rxQ.notEmpty);
        rxQ.deq;
        return rxQ.first;
    endmethod
endmodule



// AW channel ==============
typedef 8 NAP_AXI_AWID_WIDTH;
typedef Bit#(NAP_AXI_AWID_WIDTH) NapAxiAwid;

typedef 42 NAP_AXI_AWADDR_WIDTH;
typedef Bit#(NAP_AXI_AWADDR_WIDTH) NapAxiAwaddr;

typedef 8 NAP_AXI_AWLEN_WIDTH;
typedef Bit#(NAP_AXI_AWLEN_WIDTH) NapAxiAwlen;

typedef 3 NAP_AXI_AWSIZE_WIDTH;
typedef Bit#(NAP_AXI_AWSIZE_WIDTH) NapAxiAwsize;

typedef 2 NAP_AXI_AWBURST_WIDTH;
typedef Bit#(NAP_AXI_AWBURST_WIDTH) NapAxiAwburst;

typedef 4 NAP_AXI_AWQOS_WIDTH;
typedef Bit#(NAP_AXI_AWQOS_WIDTH) NapAxiAwqos;

// W channel ==============
typedef 256 NAP_AXI_WDATA_WIDTH;
typedef Bit#(NAP_AXI_WDATA_WIDTH) NapAxiWdata;

typedef 32 NAP_AXI_WSTRB_WIDTH;
typedef Bit#(NAP_AXI_WSTRB_WIDTH) NapAxiWstrb;

// B channel ==============
typedef 8 NAP_AXI_BID_WIDTH;
typedef Bit#(NAP_AXI_BID_WIDTH) NapAxiBid;

typedef 2 NAP_AXI_BRESP_WIDTH;
typedef Bit#(NAP_AXI_BRESP_WIDTH) NapAxiBresp;

// AR channel ==============
typedef 8 NAP_AXI_ARID_WIDTH;
typedef Bit#(NAP_AXI_ARID_WIDTH) NapAxiArid;

typedef 42 NAP_AXI_ARADDR_WIDTH;
typedef Bit#(NAP_AXI_ARADDR_WIDTH) NapAxiAraddr;

typedef 8 NAP_AXI_ARLEN_WIDTH;
typedef Bit#(NAP_AXI_ARLEN_WIDTH) NapAxiArlen;

typedef 3 NAP_AXI_ARSIZE_WIDTH;
typedef Bit#(NAP_AXI_ARSIZE_WIDTH) NapAxiArsize;

typedef 2 NAP_AXI_ARBURST_WIDTH;
typedef Bit#(NAP_AXI_ARBURST_WIDTH) NapAxiArburst;

typedef 4 NAP_AXI_ARQOS_WIDTH;
typedef Bit#(NAP_AXI_ARQOS_WIDTH) NapAxiArqos;

// R channel ==============
typedef 8 NAP_AXI_RID_WIDTH;
typedef Bit#(NAP_AXI_RID_WIDTH) NapAxiRid;

typedef 256 NAP_AXI_RDATA_WIDTH;
typedef Bit#(NAP_AXI_RDATA_WIDTH) NapAxiRdata;

typedef 2 NAP_AXI_RRESP_WIDTH;
typedef Bit#(NAP_AXI_RRESP_WIDTH) NapAxiRresp;

typedef enum {
    NapAxiSize1B   = 0,
    NapAxiSize2B   = 1,
    NapAxiSize4B   = 2,
    NapAxiSize8B   = 3,
    NapAxiSize16B  = 4,
    NapAxiSize32B  = 5,
    NapAxiSize64B  = 6,
    NapAxiSize128B = 7
} NapAxiSize deriving(Bits, FShow, Eq);

typedef enum {
    NapAxiBurstFixed  = 0,
    NapAxiBurstIncr   = 1,
    NapAxiBurstWrap   = 2
} NapAxiBurst deriving(Bits, FShow, Eq);

typedef struct {
    NapAxiAwid awid;
    NapAxiAwaddr awaddr;
    NapAxiAwlen awlen;
    NapAxiAwsize awsize;
    NapAxiAwburst awburst;
    Bool awlock;  
    NapAxiAwqos awqos;
} AxiMmNapBeatAw deriving(Bits, FShow);

typedef struct {
    NapAxiWdata wdata;
    NapAxiWstrb wstrb;
    Bool wlast;
} AxiMmNapBeatW deriving(Bits, FShow);

typedef struct {
    NapAxiBid bid;
    NapAxiBresp bresp;
} AxiMmNapBeatB deriving(Bits, FShow);

typedef struct {
    NapAxiArid arid;
    NapAxiAraddr araddr;
    NapAxiArlen arlen;
    NapAxiArsize arsize;
    NapAxiArburst arburst;
    Bool arlock;
    NapAxiArqos arqos;
} AxiMmNapBeatAr deriving(Bits, FShow);

typedef struct {
    NapAxiRid rid;
    NapAxiRdata rdata;
    NapAxiRresp rresp;
    Bool rlast;
} AxiMmNapBeatR deriving(Bits, FShow);


interface ACX_NAP_AXI_MASTER_WRAPPER;
    
    // aw channel ===========
    // output port
    method NapAxiAwid awid;
    method NapAxiAwaddr awaddr;
    method NapAxiAwlen awlen;
    method NapAxiAwsize awsize;
    method NapAxiAwburst awburst;
    method Bool awlock;
    method NapAxiAwqos awqos;
    method Bool awvalid;
    // input port
    method Action awready(Bool val);

    // w channel ===========
    // output port
    method NapAxiWdata wdata;
    method NapAxiWstrb wstrb;
    method Bool wlast;
    method Bool wvalid;
    // input port
    method Action wready(Bool val);

    // b channel ===========
    // output port 
    method Bool bready;
    // input port
    method Action bid(NapAxiBid val);
    method Action bresp(NapAxiBresp val);
    method Action bvalid(Bool val);

    // ar channel ===========
    // output port 
    method NapAxiArid arid;
    method NapAxiAraddr araddr;
    method NapAxiArlen arlen;
    method NapAxiArsize arsize;
    method NapAxiArburst arburst;
    method Bool arlock;
    method NapAxiArqos arqos;
    method Bool arvalid;
    // input port
    method Action arready(Bool val);

    // r channel ===========
    // output port
    method Bool rready;
    // input port
    method Action rid(NapAxiRid val);
    method Action rdata(NapAxiRdata val);
    method Action rresp(NapAxiRresp val);
    method Action rlast(Bool val);
    method Action rvalid(Bool val);
endinterface


import "BVI" ACX_NAP_AXI_MASTER =
module mkAcxNapAxiMasterWrapperInner(ACX_NAP_AXI_MASTER_WRAPPER);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    input_clock (clk) = clk;
    input_reset rstN(rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    // aw channel ===========
    // output port 
    method awid awid clocked_by(clk) reset_by(no_reset);
    method awaddr awaddr clocked_by(clk) reset_by(no_reset);
    method awlen awlen clocked_by(clk) reset_by(no_reset);
    method awsize awsize clocked_by(clk) reset_by(no_reset);
    method awburst awburst clocked_by(clk) reset_by(no_reset);
    method awlock awlock clocked_by(clk) reset_by(no_reset);  
    method awqos awqos clocked_by(clk) reset_by(no_reset);
    method awvalid awvalid clocked_by(clk) reset_by(no_reset);
    // input port
    method awready(awready) enable((*inhigh*) EN_NO_USE_1) clocked_by(clk) reset_by(no_reset);

    // w channel ===========
    // output port
    method wdata wdata clocked_by(clk) reset_by(no_reset);
    method wstrb wstrb clocked_by(clk) reset_by(no_reset);
    method wlast wlast clocked_by(clk) reset_by(no_reset);
    method wvalid wvalid clocked_by(clk) reset_by(no_reset);
    // input port
    method wready(wready) enable((*inhigh*) EN_NO_USE_2) clocked_by(clk) reset_by(no_reset);

    // b channel ===========
    // output port 
    method bready bready clocked_by(clk) reset_by(no_reset);
    // input port
    method bid(bid) enable((*inhigh*) EN_NO_USE_3) clocked_by(clk) reset_by(no_reset);
    method bresp(bresp) enable((*inhigh*) EN_NO_USE_4) clocked_by(clk) reset_by(no_reset);
    method bvalid(bvalid) enable((*inhigh*) EN_NO_USE_5) clocked_by(clk) reset_by(no_reset);

    // ar channel ===========
    // output port 
    method arid arid clocked_by(clk) reset_by(no_reset);
    method araddr araddr clocked_by(clk) reset_by(no_reset);
    method arlen arlen clocked_by(clk) reset_by(no_reset);
    method arsize arsize clocked_by(clk) reset_by(no_reset);
    method arburst arburst clocked_by(clk) reset_by(no_reset);
    method arlock arlock clocked_by(clk) reset_by(no_reset);
    method arqos arqos clocked_by(clk) reset_by(no_reset);
    method arvalid arvalid clocked_by(clk) reset_by(no_reset);
    // input port
    method arready(arready) enable((*inhigh*) EN_NO_USE_6) clocked_by(clk) reset_by(no_reset);

    // r channel ===========
    // output port
    method rready rready clocked_by(clk) reset_by(no_reset);
    // input port
    method rid(rid) enable((*inhigh*) EN_NO_USE_7) clocked_by(clk) reset_by(no_reset);
    method rdata(rdata) enable((*inhigh*) EN_NO_USE_8) clocked_by(clk) reset_by(no_reset);
    method rresp(rresp) enable((*inhigh*) EN_NO_USE_9) clocked_by(clk) reset_by(no_reset);
    method rlast(rlast) enable((*inhigh*) EN_NO_USE_10) clocked_by(clk) reset_by(no_reset);
    method rvalid(rvalid) enable((*inhigh*) EN_NO_USE_11) clocked_by(clk) reset_by(no_reset);

    schedule (awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready
            ) CF (
                awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready);
    
    schedule (awready, wready, bid, bresp, bvalid, arready, 
                rid, rdata, rresp, rlast, rvalid
            ) C (
                awready, wready, bid, bresp, bvalid, arready,
                rid, rdata, rresp, rlast, rvalid);

    schedule (awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready
            ) SB (
                awready, wready, bid, bresp, bvalid, arready,
                rid, rdata, rresp, rlast, rvalid);
endmodule



module mkAcxNapAxiMasterPrimitiveWrapper(ACX_NAP_AXI_MASTER_WRAPPER);
    let inst <- mkAcxNapAxiMasterWrapperInner;
    return inst;
endmodule



interface AcxNapMasterWrapper;
    method ActionValue#(AxiMmNapBeatAw) recvWriteAddr;
    method ActionValue#(AxiMmNapBeatW) recvWriteData;
    method Action sendWriteResp(AxiMmNapBeatB beat);

    method ActionValue#(AxiMmNapBeatAr) recvReadAddr;
    method Action sendReadResp(AxiMmNapBeatR beat);
endinterface

module mkAcxNapMasterWrapper(AcxNapMasterWrapper);

    FIFOF#(AxiMmNapBeatAw) awQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatW)   wQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatB)   bQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatAr) arQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatR)   rQ   <- mkUGFIFOF;
    
    let axiMasterNap <- mkAcxNapAxiMasterPrimitiveWrapper;

    rule forwardAxiSignalAw;
        if (awQ.notFull) begin
            axiMasterNap.awready(True);
            if (axiMasterNap.awvalid) begin
                let recvBeat = AxiMmNapBeatAw{
                    awid: axiMasterNap.awid,
                    awaddr: zeroExtend(axiMasterNap.awaddr),
                    awlen: axiMasterNap.awlen,
                    awsize: axiMasterNap.awsize,
                    awburst: axiMasterNap.awburst,
                    awlock: axiMasterNap.awlock,
                    awqos: axiMasterNap.awqos
                };
                awQ.enq(recvBeat);
            end
        end
        else begin
            axiMasterNap.awready(False);
        end
    endrule

    rule forwardAxiSignalW;
        if (wQ.notFull) begin
            axiMasterNap.wready(True);
            if (axiMasterNap.wvalid) begin
                let recvBeat = AxiMmNapBeatW{
                    wdata: axiMasterNap.wdata,
                    wstrb: axiMasterNap.wstrb,
                    wlast: axiMasterNap.wlast
                };
                wQ.enq(recvBeat);
            end
        end
        else begin
            axiMasterNap.wready(False);
        end
    endrule


    rule forwardAxiSignalB;
        let bBeat = bQ.first;
        axiMasterNap.bvalid(bQ.notEmpty);
        axiMasterNap.bid(bBeat.bid);
        axiMasterNap.bresp(bBeat.bresp);
        if (bQ.notEmpty) begin
            if (axiMasterNap.bready) begin
                bQ.deq;
            end
        end
    endrule

    
    rule forwardAxiSignalAr;
        if (arQ.notFull) begin
            axiMasterNap.arready(True);
            if (axiMasterNap.arvalid) begin
                let recvBeat = AxiMmNapBeatAr{
                    arid: axiMasterNap.arid,
                    araddr: zeroExtend(axiMasterNap.araddr),
                    arlen: axiMasterNap.arlen,
                    arsize: axiMasterNap.arsize,
                    arburst: axiMasterNap.arburst,
                    arlock: axiMasterNap.arlock,
                    arqos: axiMasterNap.arqos
                };
                arQ.enq(recvBeat);
            end
        end
        else begin
            axiMasterNap.arready(False);
        end
    endrule


    rule forwardAxiSignalR;
        let rBeat = rQ.first;
        axiMasterNap.rvalid(rQ.notEmpty);
        axiMasterNap.rid(rBeat.rid);
        axiMasterNap.rdata(rBeat.rdata);
        axiMasterNap.rresp(rBeat.rresp);
        axiMasterNap.rlast(rBeat.rlast);

        if (rQ.notEmpty) begin
            if (axiMasterNap.rready) begin
                rQ.deq;
            end
        end
    endrule


    method ActionValue#(AxiMmNapBeatAw) recvWriteAddr if (awQ.notEmpty);
        awQ.deq;
        return awQ.first;
    endmethod

    method ActionValue#(AxiMmNapBeatW) recvWriteData if (wQ.notEmpty);
        wQ.deq;
        return wQ.first;
    endmethod

    method Action sendWriteResp(AxiMmNapBeatB beat) if (bQ.notFull);
        bQ.enq(beat);
    endmethod

    method ActionValue#(AxiMmNapBeatAr) recvReadAddr if (arQ.notEmpty);
        arQ.deq;
        return arQ.first;
    endmethod

    method Action sendReadResp(AxiMmNapBeatR beat) if (rQ.notFull);
        rQ.enq(beat);
    endmethod
    
endmodule



interface ACX_NAP_AXI_SLAVE_WRAPPER;
    
    // aw channel ===========
    // input port
    method Action awid(NapAxiAwid val);
    method Action awaddr(NapAxiAwaddr val);
    method Action awlen(NapAxiAwlen val);
    method Action awsize(NapAxiAwsize val);
    method Action awburst(NapAxiAwburst val);
    method Action awlock(Bool val);
    method Action awqos(NapAxiAwqos val);
    method Action awvalid(Bool val);
    // output port
    method Bool awready;

    // w channel ===========
    // input port
    method Action wdata(NapAxiWdata val);
    method Action wstrb(NapAxiWstrb val);
    method Action wlast(Bool val);
    method Action wvalid(Bool val);
    // output port
    method Bool wready;

    // b channel ===========
    // input port
    method Action bready(Bool val);
    // output port 
    method NapAxiBid bid;
    method NapAxiBresp bresp;
    method Bool bvalid;

    // ar channel ===========
    // input port
    method Action arid(NapAxiArid val);
    method Action araddr(NapAxiAraddr val);
    method Action arlen(NapAxiArlen val);
    method Action arsize(NapAxiArsize val);
    method Action arburst(NapAxiArburst val);
    method Action arlock(Bool val);
    method Action arqos(NapAxiArqos val);
    method Action arvalid(Bool val);
    // output port 
    method Bool arready;

    // r channel ===========
    // input port
    method Action rready(Bool val);
    // output port
    method NapAxiRid rid;
    method NapAxiRdata rdata;
    method NapAxiRresp rresp;
    method Bool rlast;
    method Bool rvalid;
endinterface


import "BVI" ACX_NAP_AXI_SLAVE =
module mkAcxNapAxiSlaveWrapperInner(ACX_NAP_AXI_SLAVE_WRAPPER);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    input_clock (clk) = clk;
    input_reset rstN(rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    // aw channel ===========
    // input port
    method awid(awid) enable((*inhigh*) EN_NO_USE_1) clocked_by(clk) reset_by(no_reset);
    method awaddr(awaddr) enable((*inhigh*) EN_NO_USE_2) clocked_by(clk) reset_by(no_reset);
    method awlen(awlen) enable((*inhigh*) EN_NO_USE_3) clocked_by(clk) reset_by(no_reset);
    method awsize(awsize) enable((*inhigh*) EN_NO_USE_4) clocked_by(clk) reset_by(no_reset);
    method awburst(awburst) enable((*inhigh*) EN_NO_USE_5) clocked_by(clk) reset_by(no_reset);
    method awlock(awlock) enable((*inhigh*) EN_NO_USE_6) clocked_by(clk) reset_by(no_reset);
    method awqos(awqos) enable((*inhigh*) EN_NO_USE_7) clocked_by(clk) reset_by(no_reset);
    method awvalid(awvalid) enable((*inhigh*) EN_NO_USE_8) clocked_by(clk) reset_by(no_reset);
    // output port
    method awready awready clocked_by(clk) reset_by(no_reset);


    // w channel ===========
    // input port
    method wdata(wdata) enable((*inhigh*) EN_NO_USE_9) clocked_by(clk) reset_by(no_reset);
    method wstrb(wstrb) enable((*inhigh*) EN_NO_USE_10) clocked_by(clk) reset_by(no_reset);
    method wlast(wlast) enable((*inhigh*) EN_NO_USE_11) clocked_by(clk) reset_by(no_reset);
    method wvalid(wvalid) enable((*inhigh*) EN_NO_USE_12) clocked_by(clk) reset_by(no_reset);
   // output port
    method wready wready clocked_by(clk) reset_by(no_reset);

    // b channel ===========
    // input port
    method bready(bready) enable((*inhigh*) EN_NO_USE_13) clocked_by(clk) reset_by(no_reset);
    // output port 
    method bid bid clocked_by(clk) reset_by(no_reset);
    method bresp bresp clocked_by(clk) reset_by(no_reset);
    method bvalid bvalid clocked_by(clk) reset_by(no_reset);

    // ar channel ===========
    // input port
    method arid(arid) enable((*inhigh*) EN_NO_USE_14) clocked_by(clk) reset_by(no_reset);
    method araddr(araddr) enable((*inhigh*) EN_NO_USE_15) clocked_by(clk) reset_by(no_reset);
    method arlen(arlen) enable((*inhigh*) EN_NO_USE_16) clocked_by(clk) reset_by(no_reset);
    method arsize(arsize) enable((*inhigh*) EN_NO_USE_17) clocked_by(clk) reset_by(no_reset);
    method arburst(arburst) enable((*inhigh*) EN_NO_USE_18) clocked_by(clk) reset_by(no_reset);
    method arlock(arlock) enable((*inhigh*) EN_NO_USE_19) clocked_by(clk) reset_by(no_reset);
    method arqos(arqos) enable((*inhigh*) EN_NO_USE_20) clocked_by(clk) reset_by(no_reset);
    method arvalid(arvalid) enable((*inhigh*) EN_NO_USE_21) clocked_by(clk) reset_by(no_reset);
    // output port 
    method arready arready clocked_by(clk) reset_by(no_reset);
   
    // r channel ===========
    // input port
    method rready(rready) enable((*inhigh*) EN_NO_USE_22) clocked_by(clk) reset_by(no_reset);
    // output port
    method rid rid clocked_by(clk) reset_by(no_reset);
    method rdata rdata clocked_by(clk) reset_by(no_reset);
    method rresp rresp clocked_by(clk) reset_by(no_reset);
    method rlast rlast clocked_by(clk) reset_by(no_reset);
    method rvalid rvalid clocked_by(clk) reset_by(no_reset);

    schedule (awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready, bid, awready, 
                wready, bvalid, arready, rid, rdata, rresp, 
                rlast, rvalid, bresp
            ) CF (
                awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready, bresp, bvalid,
                awready, wready, bvalid, arready, rid, rdata,
                rresp, rlast, rvalid, bid);


endmodule

module mkAcxNapAxiSlavePrimitiveWrapper(ACX_NAP_AXI_SLAVE_WRAPPER);
    let inst <- mkAcxNapAxiSlaveWrapperInner;
    return inst;
endmodule



interface AcxNapSlaveWrapper;

    method Action sendWriteAddr(AxiMmNapBeatAw beat);
    method Action sendWriteData(AxiMmNapBeatW beat);
    method ActionValue#(AxiMmNapBeatB) recvWriteResp;

    method Action sendReadAddr(AxiMmNapBeatAr beat);
    method ActionValue#(AxiMmNapBeatR) recvReadResp;
endinterface

module mkAcxNapSlaveWrapper(AcxNapSlaveWrapper);

    FIFOF#(AxiMmNapBeatAw) awQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatW)   wQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatB)   bQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatAr) arQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatR)   rQ   <- mkUGFIFOF;
    
    let axiSlaveNap <- mkAcxNapAxiSlavePrimitiveWrapper;


    rule forwardAxiSignalAw;
        let awBeat = awQ.first;
        axiSlaveNap.awvalid(awQ.notEmpty);

        axiSlaveNap.awid(awBeat.awid);
        axiSlaveNap.awaddr(awBeat.awaddr);
        axiSlaveNap.awlen(awBeat.awlen);
        axiSlaveNap.awsize(awBeat.awsize);
        axiSlaveNap.awburst(awBeat.awburst);
        axiSlaveNap.awlock(awBeat.awlock);
        axiSlaveNap.awqos(awBeat.awqos);

        if (awQ.notEmpty) begin
            if (axiSlaveNap.awready) begin
                awQ.deq;
            end
        end
    endrule


    rule forwardAxiSignalW;
        let wBeat = wQ.first;
        axiSlaveNap.wvalid(wQ.notEmpty);

        axiSlaveNap.wdata(wBeat.wdata);
        axiSlaveNap.wstrb(wBeat.wstrb);
        axiSlaveNap.wlast(wBeat.wlast);

        if (wQ.notEmpty) begin
            if (axiSlaveNap.wready) begin
                wQ.deq;
            end
        end
    endrule


    rule forwardAxiSignalB;
        if (bQ.notFull) begin
            axiSlaveNap.bready(True);
            if (axiSlaveNap.bvalid) begin
                let recvBeat = AxiMmNapBeatB{
                    bid: axiSlaveNap.bid,
                    bresp: axiSlaveNap.bresp
                };
                bQ.enq(recvBeat);
            end
        end
        else begin
            axiSlaveNap.bready(False);
        end
    endrule

    
    rule forwardAxiSignalAr;
        let arBeat = arQ.first;
        axiSlaveNap.arvalid(arQ.notEmpty);
        axiSlaveNap.arid(arBeat.arid);
        axiSlaveNap.araddr(arBeat.araddr);
        axiSlaveNap.arlen(arBeat.arlen);
        axiSlaveNap.arsize(arBeat.arsize);
        axiSlaveNap.arburst(arBeat.arburst);
        axiSlaveNap.arlock(arBeat.arlock);
        axiSlaveNap.arqos(arBeat.arqos);

        if (arQ.notEmpty) begin
            if (axiSlaveNap.arready) begin
                arQ.deq;
            end
        end
        
    endrule

    rule forwardAxiSignalR;
        if (rQ.notFull) begin
            axiSlaveNap.rready(True);
            if (axiSlaveNap.rvalid) begin
                let recvBeat = AxiMmNapBeatR{
                    rid: axiSlaveNap.rid,
                    rdata: axiSlaveNap.rdata,
                    rresp: axiSlaveNap.rresp,
                    rlast: axiSlaveNap.rlast
                };
                rQ.enq(recvBeat);
            end
        end
        else begin
            axiSlaveNap.rready(False);
        end
    endrule

    
    
    method Action sendWriteAddr(AxiMmNapBeatAw beat) if (awQ.notFull);
        awQ.enq(beat);
    endmethod

    method Action sendWriteData(AxiMmNapBeatW beat) if (wQ.notFull);
        wQ.enq(beat);
    endmethod

    method ActionValue#(AxiMmNapBeatB) recvWriteResp if (bQ.notEmpty);
        bQ.deq;
        return bQ.first;
    endmethod

    method Action sendReadAddr(AxiMmNapBeatAr beat) if (arQ.notFull);
        arQ.enq(beat);
    endmethod

    method ActionValue#(AxiMmNapBeatR) recvReadResp if (rQ.notEmpty);
        rQ.deq;
        return rQ.first;
    endmethod
    
endmodule