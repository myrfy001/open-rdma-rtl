import GetPut :: *;
import ClientServer :: *;
import RegFile :: *;
import FIFOF :: *;
import Vector :: *;

import PrimUtils :: *;


typedef 4 VERTICAL_NAP_NODE_ID_WIDTH;
typedef 293 VERTICAL_NAP_DATA_WIDTH;

typedef Bit#(VERTICAL_NAP_NODE_ID_WIDTH) VerticalNapNodeId;
typedef Bit#(VERTICAL_NAP_DATA_WIDTH) VerticalNapData;



interface ACX_NAP_ETHERNET_WRAPPER;
    // input port
    method Action tx_valid(Bool val);
    method Action tx_data(VerticalNapData val);
    method Action tx_sop(Bool val);
    method Action tx_eop(Bool val);
    method Action rx_ready(Bool val);

    // output port
    method Bool rx_valid;
    method VerticalNapNodeId rx_src;
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
    schedule (tx_valid, tx_data, tx_sop, tx_eop, rx_ready) C (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);
    schedule (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready) SB (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);


endmodule


module mkAcxNapEthernetWrapper#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(ACX_NAP_ETHERNET_WRAPPER);

    let inst <- mkAcxNapEthernetWrapperInner(tx_eiu_channel, rx_eiu_channel);
    return inst;
endmodule

typedef struct {
    VerticalNapNodeId nodeId;
    VerticalNapData data;
    Bool sop;
    Bool eop;
} VerticalNapBeatEntry deriving(Bits, FShow);


interface AcxNapEthernet;
    method Action send(VerticalNapBeatEntry beat);
    method ActionValue#(VerticalNapBeatEntry) recv;
endinterface

module mkAcxNapEthernet#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(AcxNapEthernet);

    FIFOF#(VerticalNapBeatEntry) txQ <- mkFIFOF;
    FIFOF#(VerticalNapBeatEntry) rxQ <- mkFIFOF;
    
    let ethNap <- mkAcxNapEthernetWrapper(tx_eiu_channel, rx_eiu_channel);

    rule forwardTxAxiSignal;
        if (txQ.notEmpty) begin
            let txBeat = txQ.first;
            ethNap.tx_valid(True);
            ethNap.tx_data(txBeat.data);
            ethNap.tx_sop(txBeat.sop);
            ethNap.tx_eop(txBeat.eop);
            if (ethNap.tx_ready) begin
                txQ.deq;
            end
        end
        else begin
            ethNap.tx_valid(False);
        end
    endrule

    rule forwardRxAxiSignal;
        if (rxQ.notFull) begin
            ethNap.rx_ready(True);
            if (ethNap.rx_valid) begin
                let recvBeat = VerticalNapBeatEntry{
                    nodeId: 4'hF, // according to UG086, the node ID of EIU is 4'hf
                    data: ethNap.rx_data,
                    Bool ethNap.sop,
                    Bool ethNap.eop
                };
                rxQ.enq(recvBeat);
            end
        end
        else begin
            ethNap.rx_ready(False);
        end
    endrule



    method Action send(VerticalNapBeatEntry beat);
    endmethod

    method ActionValue#(VerticalNapBeatEntry) recv;
        return ?;
    endmethod
endmodule



// AW channel ==============
typedef 8 NAP_AXI_AWID_WIDTH;
typedef Bit#(NAP_AXI_AWID_WIDTH) NapAxiAwid;

typedef 28 NAP_AXI_AWADDR_WIDTH;
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

typedef 28 NAP_AXI_ARADDR_WIDTH;
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





interface ACX_NAP_AXI_MASTER_WRAPPER;
    // input port
    method Action tx_valid(Bool val);
    method Action tx_data(VerticalNapData val);
    method Action tx_sop(Bool val);
    method Action tx_eop(Bool val);
    method Action rx_ready(Bool val);

    // output port
    method Bool rx_valid;
    method VerticalNapNodeId rx_src;
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
    schedule (tx_valid, tx_data, tx_sop, tx_eop, rx_ready) C (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);
    schedule (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready) SB (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);


endmodule