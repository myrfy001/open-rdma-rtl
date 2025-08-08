module bluerdma_top(
    input  wire                 clk_sys_100m_p      ,

    input  wire                 pcie_ep_perstn      ,
    input  wire                 pcie_ep_refclk0     ,
    input  wire                 pcie_ep_refclk1     ,
    input  wire   [15:0]        rtile_pcie_rx_n_in  ,
    input  wire   [15:0]        rtile_pcie_rx_p_in  ,
    output wire   [15:0]        rtile_pcie_tx_n_out ,
    output wire   [15:0]        rtile_pcie_tx_p_out ,

	input  wire                 qsfpdd_refclk_fht   ,
    input  wire                 qsfpdd_refclk_fgt   ,
    input  wire     [3:0]       qsfpdd0_rx_p        ,
    input  wire     [3:0]       qsfpdd0_rx_n        ,
    output wire     [3:0]       qsfpdd0_tx_p        ,
    output wire     [3:0]       qsfpdd0_tx_n        
);

    wire rtile_pcie_p0_reset_status_n;
	wire rtile_pcie_p0_reset_status_n_buffered;
    wire rtile_pcie_p0_slow_reset_status_n;
    wire rtile_pcie_p0_link_up;
    wire rtile_pcie_p0_dl_up;
    wire rtile_pcie_p0_surprise_down_err;
    wire rtile_pcie_p0_dl_timer_update;
    wire [5:0] rtile_pcie_p0_ltssm_state_delay;
    wire rtile_pcie_p0_ltssm_st_hipfifo_ovrflw;
    wire rtile_pcie_p0_app_xfer_pending;
    wire [7:0]rtile_pcie_p0_pld_gp_status;
    wire [7:0]rtile_pcie_p0_pld_gp_ctrl;
    wire rtile_pcie_p0_pld_gp_status_ready;
    wire rtile_pcie_coreclkout_hip;
    wire rtile_pcie_ninit_done;
    wire rtile_pcie_reconfig_clk;
    wire [20:0]rtile_pcie_reconfig_address;
    wire rtile_pcie_reconfig_read;
    wire [7:0]rtile_pcie_reconfig_readdata;
    wire rtile_pcie_reconfig_readdatavalid;
    wire rtile_pcie_reconfig_write;
    wire [7:0]rtile_pcie_reconfig_writedata;
    wire rtile_pcie_reconfig_waitrequest;
    wire [4:0]rtile_pcie_reconfig_reserved_out;
    wire rtile_pcie_slow_clk;
    wire rtile_pcie_dummy_user_avmm_rst;
    wire rtile_pcie_p0_rx_st_ready;
    wire [255:0]rtile_pcie_p0_rx_st0_data;
    wire rtile_pcie_p0_rx_st0_sop;
    wire rtile_pcie_p0_rx_st0_eop;
    wire rtile_pcie_p0_rx_st0_dvalid;
    wire [2:0]rtile_pcie_p0_rx_st0_empty;
    wire [127:0]rtile_pcie_p0_rx_st0_hdr;
    wire [31:0]rtile_pcie_p0_rx_st0_prefix;
    wire rtile_pcie_p0_rx_st0_hvalid;
    wire rtile_pcie_p0_rx_st0_pvalid;
    wire [2:0]rtile_pcie_p0_rx_st0_bar;
    wire rtile_pcie_p0_rx_st0_pt_parity;
    wire [255:0]rtile_pcie_p0_rx_st1_data;
    wire rtile_pcie_p0_rx_st1_sop;
    wire rtile_pcie_p0_rx_st1_eop;
    wire rtile_pcie_p0_rx_st1_dvalid;
    wire [2:0]rtile_pcie_p0_rx_st1_empty;
    wire [127:0]rtile_pcie_p0_rx_st1_hdr;
    wire [31:0]rtile_pcie_p0_rx_st1_prefix;
    wire rtile_pcie_p0_rx_st1_hvalid;
    wire rtile_pcie_p0_rx_st1_pvalid;
    wire [2:0]rtile_pcie_p0_rx_st1_bar;
    wire rtile_pcie_p0_rx_st1_pt_parity;
    wire [255:0]rtile_pcie_p0_rx_st2_data;
    wire rtile_pcie_p0_rx_st2_sop;
    wire rtile_pcie_p0_rx_st2_eop;
    wire rtile_pcie_p0_rx_st2_dvalid;
    wire [2:0]rtile_pcie_p0_rx_st2_empty;
    wire [127:0]rtile_pcie_p0_rx_st2_hdr;
    wire [31:0]rtile_pcie_p0_rx_st2_prefix;
    wire rtile_pcie_p0_rx_st2_hvalid;
    wire rtile_pcie_p0_rx_st2_pvalid;
    wire [2:0]rtile_pcie_p0_rx_st2_bar;
    wire rtile_pcie_p0_rx_st2_pt_parity;
    wire [255:0]rtile_pcie_p0_rx_st3_data;
    wire rtile_pcie_p0_rx_st3_sop;
    wire rtile_pcie_p0_rx_st3_eop;
    wire rtile_pcie_p0_rx_st3_dvalid;
    wire [2:0]rtile_pcie_p0_rx_st3_empty;
    wire [127:0]rtile_pcie_p0_rx_st3_hdr;
    wire [31:0]rtile_pcie_p0_rx_st3_prefix;
    wire rtile_pcie_p0_rx_st3_hvalid;
    wire rtile_pcie_p0_rx_st3_pvalid;
    wire [2:0]rtile_pcie_p0_rx_st3_bar;
    wire rtile_pcie_p0_rx_st3_pt_parity;
    wire [2:0]rtile_pcie_p0_rx_st_hcrdt_init;
    wire [2:0]rtile_pcie_p0_rx_st_hcrdt_update;
    wire [5:0]rtile_pcie_p0_rx_st_hcrdt_update_cnt;
    wire [2:0]rtile_pcie_p0_rx_st_hcrdt_init_ack;
    wire [2:0]rtile_pcie_p0_rx_st_dcrdt_init;
    wire [2:0]rtile_pcie_p0_rx_st_dcrdt_update;
    wire [11:0]rtile_pcie_p0_rx_st_dcrdt_update_cnt;
    wire [2:0]rtile_pcie_p0_rx_st_dcrdt_init_ack;
    wire [2:0]rtile_pcie_p0_tx_st_hcrdt_init;
    wire [2:0]rtile_pcie_p0_tx_st_hcrdt_update;
    wire [5:0]rtile_pcie_p0_tx_st_hcrdt_update_cnt;
    wire [2:0]rtile_pcie_p0_tx_st_hcrdt_init_ack;
    wire [2:0]rtile_pcie_p0_tx_st_dcrdt_init;
    wire [2:0]rtile_pcie_p0_tx_st_dcrdt_update;
    wire [11:0]rtile_pcie_p0_tx_st_dcrdt_update_cnt;
    wire [2:0]rtile_pcie_p0_tx_st_dcrdt_init_ack;
    wire [127:0]rtile_pcie_p0_tx_st0_hdr;
    wire [31:0]rtile_pcie_p0_tx_st0_prefix;
    wire rtile_pcie_p0_tx_st0_hvalid;
    wire rtile_pcie_p0_tx_st0_pvalid;
    wire [255:0]rtile_pcie_p0_tx_st0_data;
    wire rtile_pcie_p0_tx_st0_sop;
    wire rtile_pcie_p0_tx_st0_eop;
    wire rtile_pcie_p0_tx_st0_dvalid;
    wire [127:0]rtile_pcie_p0_tx_st1_hdr;
    wire [31:0]rtile_pcie_p0_tx_st1_prefix;
    wire rtile_pcie_p0_tx_st1_hvalid;
    wire rtile_pcie_p0_tx_st1_pvalid;
    wire [255:0]rtile_pcie_p0_tx_st1_data;
    wire rtile_pcie_p0_tx_st1_sop;
    wire rtile_pcie_p0_tx_st1_eop;
    wire rtile_pcie_p0_tx_st1_dvalid;
    wire [127:0]rtile_pcie_p0_tx_st2_hdr;
    wire [31:0]rtile_pcie_p0_tx_st2_prefix;
    wire rtile_pcie_p0_tx_st2_hvalid;
    wire rtile_pcie_p0_tx_st2_pvalid;
    wire [255:0]rtile_pcie_p0_tx_st2_data;
    wire rtile_pcie_p0_tx_st2_sop;
    wire rtile_pcie_p0_tx_st2_eop;
    wire rtile_pcie_p0_tx_st2_dvalid;
    wire [127:0]rtile_pcie_p0_tx_st3_hdr;
    wire [31:0]rtile_pcie_p0_tx_st3_prefix;
    wire rtile_pcie_p0_tx_st3_hvalid;
    wire rtile_pcie_p0_tx_st3_pvalid;
    wire [255:0]rtile_pcie_p0_tx_st3_data;
    wire rtile_pcie_p0_tx_st3_sop;
    wire rtile_pcie_p0_tx_st3_eop;
    wire rtile_pcie_p0_tx_st3_dvalid;
    wire rtile_pcie_p0_tx_st_ready;
    wire rtile_pcie_p0_tx_ehp_deallocate_empty;
    wire rtile_pcie_pin_perst_n_o;

	wire ftile_eth_clk_pll;
	wire ftile_eth_reconfig_clk;
	wire ftile_eth_reconfig_reset;
	wire ftile_eth_sys_pll_locked;
	wire ftile_eth_clk_ref;
	wire ftile_eth_clk_sys;
	wire [13:0]ftile_eth_reconfig_eth_addr;
	wire [3:0]ftile_eth_reconfig_eth_byteenable;
	wire ftile_eth_reconfig_eth_readdata_valid;
	wire ftile_eth_reconfig_eth_read;
	wire ftile_eth_reconfig_eth_write;
	wire [31:0]ftile_eth_reconfig_eth_readdata;
	wire [31:0]ftile_eth_reconfig_eth_writedata;
	wire ftile_eth_reconfig_eth_waitrequest;
	wire ftile_eth_rst_n;
	wire ftile_eth_tx_rst_n;
	wire ftile_eth_rx_rst_n;
	wire ftile_eth_rst_ack_n;
	wire ftile_eth_tx_rst_ack_n;
	wire ftile_eth_rx_rst_ack_n;
	wire ftile_eth_cdr_lock;
	wire ftile_eth_tx_pll_locked;
	wire ftile_eth_tx_lanes_stable;
	wire ftile_eth_rx_pcs_ready;
	wire ftile_eth_clk_tx_div;
	wire ftile_eth_clk_rec_div64;
	wire ftile_eth_clk_rec_div;
	wire ftile_eth_rx_block_lock;
	wire ftile_eth_rx_am_lock;
	wire ftile_eth_local_fault_status;
	wire ftile_eth_remote_fault_status;
	wire ftile_eth_stats_snapshot;
	wire ftile_eth_rx_hi_ber;
	wire ftile_eth_rx_pcs_fully_aligned;
	wire [1023:0]ftile_eth_tx_mac_data;
	wire ftile_eth_tx_mac_valid;
	wire [15:0]ftile_eth_tx_mac_inframe;
	wire [47:0]ftile_eth_tx_mac_eop_empty;
	wire ftile_eth_tx_mac_ready;
	wire [15:0]ftile_eth_tx_mac_error;
	wire [15:0]ftile_eth_tx_mac_skip_crc;
	wire [1023:0]ftile_eth_rx_mac_data;
	wire ftile_eth_rx_mac_valid;
	wire [15:0]ftile_eth_rx_mac_inframe;
	wire [47:0]ftile_eth_rx_mac_eop_empty;
	wire [15:0]ftile_eth_rx_mac_fcs_error;
	wire [31:0]ftile_eth_rx_mac_error;
	wire [47:0]ftile_eth_rx_mac_status;
	wire [7:0]ftile_eth_tx_pfc;
	wire [7:0]ftile_eth_rx_pfc;
	wire ftile_eth_tx_pause;
	wire ftile_eth_rx_pause;
	wire ftile_eth_clk_pll;
	wire ftile_eth_anlt_link;



	reset_release reset_release_inst (
		.ninit_done (rtile_pcie_ninit_done)  //  output,  width = 1, ninit_done.reset
	);


    
    

    rtile_pcie_hip rtile_pcie_inst (
		.p0_reset_status_n            (rtile_pcie_p0_reset_status_n),              //  output,    width = 1,      p0_reset_status_n.reset_n
		.p0_slow_reset_status_n       (rtile_pcie_p0_slow_reset_status_n),       //  output,    width = 1, p0_slow_reset_status_n.reset_n
		.p0_link_up_o                 (rtile_pcie_p0_link_up),                 //  output,    width = 1,          p0_hip_status.link_up
		.p0_dl_up_o                   (rtile_pcie_p0_dl_up),                   //  output,    width = 1,                       .dl_up
		.p0_surprise_down_err_o       (rtile_pcie_p0_surprise_down_err),       //  output,    width = 1,                       .surprise_down_err
		.p0_dl_timer_update_o         (rtile_pcie_p0_dl_timer_update),         //  output,    width = 1,                       .dl_timer_update
		.p0_ltssm_state_delay_o       (rtile_pcie_p0_ltssm_state_delay),       //  output,    width = 6,                       .ltssm_state_delay
		.p0_ltssm_st_hipfifo_ovrflw_o (rtile_pcie_p0_ltssm_st_hipfifo_ovrflw), //  output,    width = 1,                       .ltssm_st_hipfifo_ovrflw
		.p0_app_xfer_pending_i        (rtile_pcie_p0_app_xfer_pending),        //   input,    width = 1,          p0_power_mgnt.app_xfer_pending
		.p0_pld_gp_status_i           (rtile_pcie_p0_pld_gp_status),           //   input,    width = 8,              p0_pld_gp.status
		.p0_pld_gp_ctrl_o             (rtile_pcie_p0_pld_gp_ctrl),             //  output,    width = 8,                       .ctrl
		.p0_pld_gp_status_ready_o     (rtile_pcie_p0_pld_gp_status_ready),     //  output,    width = 1,                       .status_ready
		.rx_n_in0                     (rtile_pcie_rx_n_in[0]),                     //   input,    width = 1,             hip_serial.rx_n_in0
		.rx_n_in1                     (rtile_pcie_rx_n_in[1]),                     //   input,    width = 1,                       .rx_n_in1
		.rx_n_in2                     (rtile_pcie_rx_n_in[2]),                     //   input,    width = 1,                       .rx_n_in2
		.rx_n_in3                     (rtile_pcie_rx_n_in[3]),                     //   input,    width = 1,                       .rx_n_in3
		.rx_n_in4                     (rtile_pcie_rx_n_in[4]),                     //   input,    width = 1,                       .rx_n_in4
		.rx_n_in5                     (rtile_pcie_rx_n_in[5]),                     //   input,    width = 1,                       .rx_n_in5
		.rx_n_in6                     (rtile_pcie_rx_n_in[6]),                     //   input,    width = 1,                       .rx_n_in6
		.rx_n_in7                     (rtile_pcie_rx_n_in[7]),                     //   input,    width = 1,                       .rx_n_in7
		.rx_n_in8                     (rtile_pcie_rx_n_in[8]),                     //   input,    width = 1,                       .rx_n_in8
		.rx_n_in9                     (rtile_pcie_rx_n_in[9]),                     //   input,    width = 1,                       .rx_n_in9
		.rx_n_in10                    (rtile_pcie_rx_n_in[10]),                    //   input,    width = 1,                       .rx_n_in10
		.rx_n_in11                    (rtile_pcie_rx_n_in[11]),                    //   input,    width = 1,                       .rx_n_in11
		.rx_n_in12                    (rtile_pcie_rx_n_in[12]),                    //   input,    width = 1,                       .rx_n_in12
		.rx_n_in13                    (rtile_pcie_rx_n_in[13]),                    //   input,    width = 1,                       .rx_n_in13
		.rx_n_in14                    (rtile_pcie_rx_n_in[14]),                    //   input,    width = 1,                       .rx_n_in14
		.rx_n_in15                    (rtile_pcie_rx_n_in[15]),                    //   input,    width = 1,                       .rx_n_in15
		.rx_p_in0                     (rtile_pcie_rx_p_in[0]),                     //   input,    width = 1,                       .rx_p_in0
		.rx_p_in1                     (rtile_pcie_rx_p_in[1]),                     //   input,    width = 1,                       .rx_p_in1
		.rx_p_in2                     (rtile_pcie_rx_p_in[2]),                     //   input,    width = 1,                       .rx_p_in2
		.rx_p_in3                     (rtile_pcie_rx_p_in[3]),                     //   input,    width = 1,                       .rx_p_in3
		.rx_p_in4                     (rtile_pcie_rx_p_in[4]),                     //   input,    width = 1,                       .rx_p_in4
		.rx_p_in5                     (rtile_pcie_rx_p_in[5]),                     //   input,    width = 1,                       .rx_p_in5
		.rx_p_in6                     (rtile_pcie_rx_p_in[6]),                     //   input,    width = 1,                       .rx_p_in6
		.rx_p_in7                     (rtile_pcie_rx_p_in[7]),                     //   input,    width = 1,                       .rx_p_in7
		.rx_p_in8                     (rtile_pcie_rx_p_in[8]),                     //   input,    width = 1,                       .rx_p_in8
		.rx_p_in9                     (rtile_pcie_rx_p_in[9]),                     //   input,    width = 1,                       .rx_p_in9
		.rx_p_in10                    (rtile_pcie_rx_p_in[10]),                    //   input,    width = 1,                       .rx_p_in10
		.rx_p_in11                    (rtile_pcie_rx_p_in[11]),                    //   input,    width = 1,                       .rx_p_in11
		.rx_p_in12                    (rtile_pcie_rx_p_in[12]),                    //   input,    width = 1,                       .rx_p_in12
		.rx_p_in13                    (rtile_pcie_rx_p_in[13]),                    //   input,    width = 1,                       .rx_p_in13
		.rx_p_in14                    (rtile_pcie_rx_p_in[14]),                    //   input,    width = 1,                       .rx_p_in14
		.rx_p_in15                    (rtile_pcie_rx_p_in[15]),                    //   input,    width = 1,                       .rx_p_in15
		.tx_n_out0                    (rtile_pcie_tx_n_out[0]),                    //  output,    width = 1,                       .tx_n_out0
		.tx_n_out1                    (rtile_pcie_tx_n_out[1]),                    //  output,    width = 1,                       .tx_n_out1
		.tx_n_out2                    (rtile_pcie_tx_n_out[2]),                    //  output,    width = 1,                       .tx_n_out2
		.tx_n_out3                    (rtile_pcie_tx_n_out[3]),                    //  output,    width = 1,                       .tx_n_out3
		.tx_n_out4                    (rtile_pcie_tx_n_out[4]),                    //  output,    width = 1,                       .tx_n_out4
		.tx_n_out5                    (rtile_pcie_tx_n_out[5]),                    //  output,    width = 1,                       .tx_n_out5
		.tx_n_out6                    (rtile_pcie_tx_n_out[6]),                    //  output,    width = 1,                       .tx_n_out6
		.tx_n_out7                    (rtile_pcie_tx_n_out[7]),                    //  output,    width = 1,                       .tx_n_out7
		.tx_n_out8                    (rtile_pcie_tx_n_out[8]),                    //  output,    width = 1,                       .tx_n_out8
		.tx_n_out9                    (rtile_pcie_tx_n_out[9]),                    //  output,    width = 1,                       .tx_n_out9
		.tx_n_out10                   (rtile_pcie_tx_n_out[10]),                   //  output,    width = 1,                       .tx_n_out10
		.tx_n_out11                   (rtile_pcie_tx_n_out[11]),                   //  output,    width = 1,                       .tx_n_out11
		.tx_n_out12                   (rtile_pcie_tx_n_out[12]),                   //  output,    width = 1,                       .tx_n_out12
		.tx_n_out13                   (rtile_pcie_tx_n_out[13]),                   //  output,    width = 1,                       .tx_n_out13
		.tx_n_out14                   (rtile_pcie_tx_n_out[14]),                   //  output,    width = 1,                       .tx_n_out14
		.tx_n_out15                   (rtile_pcie_tx_n_out[15]),                   //  output,    width = 1,                       .tx_n_out15
		.tx_p_out0                    (rtile_pcie_tx_p_out[0]),                    //  output,    width = 1,                       .tx_p_out0
		.tx_p_out1                    (rtile_pcie_tx_p_out[1]),                    //  output,    width = 1,                       .tx_p_out1
		.tx_p_out2                    (rtile_pcie_tx_p_out[2]),                    //  output,    width = 1,                       .tx_p_out2
		.tx_p_out3                    (rtile_pcie_tx_p_out[3]),                    //  output,    width = 1,                       .tx_p_out3
		.tx_p_out4                    (rtile_pcie_tx_p_out[4]),                    //  output,    width = 1,                       .tx_p_out4
		.tx_p_out5                    (rtile_pcie_tx_p_out[5]),                    //  output,    width = 1,                       .tx_p_out5
		.tx_p_out6                    (rtile_pcie_tx_p_out[6]),                    //  output,    width = 1,                       .tx_p_out6
		.tx_p_out7                    (rtile_pcie_tx_p_out[7]),                    //  output,    width = 1,                       .tx_p_out7
		.tx_p_out8                    (rtile_pcie_tx_p_out[8]),                    //  output,    width = 1,                       .tx_p_out8
		.tx_p_out9                    (rtile_pcie_tx_p_out[9]),                    //  output,    width = 1,                       .tx_p_out9
		.tx_p_out10                   (rtile_pcie_tx_p_out[10]),                   //  output,    width = 1,                       .tx_p_out10
		.tx_p_out11                   (rtile_pcie_tx_p_out[11]),                   //  output,    width = 1,                       .tx_p_out11
		.tx_p_out12                   (rtile_pcie_tx_p_out[12]),                   //  output,    width = 1,                       .tx_p_out12
		.tx_p_out13                   (rtile_pcie_tx_p_out[13]),                   //  output,    width = 1,                       .tx_p_out13
		.tx_p_out14                   (rtile_pcie_tx_p_out[14]),                   //  output,    width = 1,                       .tx_p_out14
		.tx_p_out15                   (rtile_pcie_tx_p_out[15]),                   //  output,    width = 1,                       .tx_p_out15
		.refclk0                      (pcie_ep_refclk0),                           //   input,    width = 1,                refclk0.clk
		.refclk1                      (pcie_ep_refclk1),                           //   input,    width = 1,                refclk1.clk
		.coreclkout_hip               (rtile_pcie_coreclkout_hip),               //  output,    width = 1,         coreclkout_hip.clk
		.ninit_done                   (rtile_pcie_ninit_done),                   //   input,    width = 1,             ninit_done.reset
		.reconfig_clk                 (rtile_pcie_reconfig_clk),                 //   input,    width = 1,      xcvr_reconfig_clk.clk
		.reconfig_address             (rtile_pcie_reconfig_address),             //   input,   width = 21,          xcvr_reconfig.address
		.reconfig_read                (rtile_pcie_reconfig_read),                //   input,    width = 1,                       .read
		.reconfig_readdata            (rtile_pcie_reconfig_readdata),            //  output,    width = 8,                       .readdata
		.reconfig_readdatavalid       (rtile_pcie_reconfig_readdatavalid),       //  output,    width = 1,                       .readdatavalid
		.reconfig_write               (rtile_pcie_reconfig_write),               //   input,    width = 1,                       .write
		.reconfig_writedata           (rtile_pcie_reconfig_writedata),           //   input,    width = 8,                       .writedata
		.reconfig_waitrequest         (rtile_pcie_reconfig_waitrequest),         //  output,    width = 1,                       .waitrequest
		.reconfig_reserved_out        (rtile_pcie_reconfig_reserved_out),        //  output,    width = 5,     xcvr_reconfig_wire.reserved_out
		.slow_clk                     (rtile_pcie_slow_clk),                     //  output,    width = 1,               slow_clk.clk
		.dummy_user_avmm_rst          (rtile_pcie_dummy_user_avmm_rst),          //   input,    width = 1,    dummy_user_avmm_rst.reset
		.p0_rx_st_ready_i             (rtile_pcie_p0_rx_st_ready),             //   input,    width = 1,              p0_rx_st0.ready
		.p0_rx_st0_data_o             (rtile_pcie_p0_rx_st0_data),             //  output,  width = 256,                       .data
		.p0_rx_st0_sop_o              (rtile_pcie_p0_rx_st0_sop),              //  output,    width = 1,                       .startofpacket
		.p0_rx_st0_eop_o              (rtile_pcie_p0_rx_st0_eop),              //  output,    width = 1,                       .endofpacket
		.p0_rx_st0_dvalid_o           (rtile_pcie_p0_rx_st0_dvalid),           //  output,    width = 1,                       .valid
		.p0_rx_st0_empty_o            (rtile_pcie_p0_rx_st0_empty),            //  output,    width = 3,                       .empty
		.p0_rx_st0_hdr_o              (rtile_pcie_p0_rx_st0_hdr),              //  output,  width = 128,          p0_rx_st_misc.rx_st0_hdr
		.p0_rx_st0_prefix_o           (rtile_pcie_p0_rx_st0_prefix),           //  output,   width = 32,                       .rx_st0_prefix
		.p0_rx_st0_hvalid_o           (rtile_pcie_p0_rx_st0_hvalid),           //  output,    width = 1,                       .rx_st0_hvalid
		.p0_rx_st0_pvalid_o           (rtile_pcie_p0_rx_st0_pvalid),           //  output,    width = 1,                       .rx_st0_pvalid
		.p0_rx_st0_bar_o              (rtile_pcie_p0_rx_st0_bar),              //  output,    width = 3,                       .rx_st0_bar
		.p0_rx_st0_pt_parity_o        (rtile_pcie_p0_rx_st0_pt_parity),        //  output,    width = 1,                       .rx_st0_pt_parity
		.p0_rx_st1_hdr_o              (rtile_pcie_p0_rx_st1_hdr),              //  output,  width = 128,                       .rx_st1_hdr
		.p0_rx_st1_prefix_o           (rtile_pcie_p0_rx_st1_prefix),           //  output,   width = 32,                       .rx_st1_prefix
		.p0_rx_st1_hvalid_o           (rtile_pcie_p0_rx_st1_hvalid),           //  output,    width = 1,                       .rx_st1_hvalid
		.p0_rx_st1_pvalid_o           (rtile_pcie_p0_rx_st1_pvalid),           //  output,    width = 1,                       .rx_st1_pvalid
		.p0_rx_st1_bar_o              (rtile_pcie_p0_rx_st1_bar),              //  output,    width = 3,                       .rx_st1_bar
		.p0_rx_st1_pt_parity_o        (rtile_pcie_p0_rx_st1_pt_parity),        //  output,    width = 1,                       .rx_st1_pt_parity
		.p0_rx_st2_hdr_o              (rtile_pcie_p0_rx_st2_hdr),              //  output,  width = 128,                       .rx_st2_hdr
		.p0_rx_st2_prefix_o           (rtile_pcie_p0_rx_st2_prefix),           //  output,   width = 32,                       .rx_st2_prefix
		.p0_rx_st2_hvalid_o           (rtile_pcie_p0_rx_st2_hvalid),           //  output,    width = 1,                       .rx_st2_hvalid
		.p0_rx_st2_pvalid_o           (rtile_pcie_p0_rx_st2_pvalid),           //  output,    width = 1,                       .rx_st2_pvalid
		.p0_rx_st2_bar_o              (rtile_pcie_p0_rx_st2_bar),              //  output,    width = 3,                       .rx_st2_bar
		.p0_rx_st2_pt_parity_o        (rtile_pcie_p0_rx_st2_pt_parity),        //  output,    width = 1,                       .rx_st2_pt_parity
		.p0_rx_st3_hdr_o              (rtile_pcie_p0_rx_st3_hdr),              //  output,  width = 128,                       .rx_st3_hdr
		.p0_rx_st3_prefix_o           (rtile_pcie_p0_rx_st3_prefix),           //  output,   width = 32,                       .rx_st3_prefix
		.p0_rx_st3_hvalid_o           (rtile_pcie_p0_rx_st3_hvalid),           //  output,    width = 1,                       .rx_st3_hvalid
		.p0_rx_st3_pvalid_o           (rtile_pcie_p0_rx_st3_pvalid),           //  output,    width = 1,                       .rx_st3_pvalid
		.p0_rx_st3_bar_o              (rtile_pcie_p0_rx_st3_bar),              //  output,    width = 3,                       .rx_st3_bar
		.p0_rx_st3_pt_parity_o        (rtile_pcie_p0_rx_st3_pt_parity),        //  output,    width = 1,                       .rx_st3_pt_parity
		.p0_rx_st_hcrdt_init_i        (rtile_pcie_p0_rx_st_hcrdt_init),        //   input,    width = 3,                       .rx_st_Hcrdt_init
		.p0_rx_st_hcrdt_update_i      (rtile_pcie_p0_rx_st_hcrdt_update),      //   input,    width = 3,                       .rx_st_Hcrdt_update
		.p0_rx_st_hcrdt_update_cnt_i  (rtile_pcie_p0_rx_st_hcrdt_update_cnt),  //   input,    width = 6,                       .rx_st_Hcrdt_update_cnt
		.p0_rx_st_hcrdt_init_ack_o    (rtile_pcie_p0_rx_st_hcrdt_init_ack),    //  output,    width = 3,                       .rx_st_Hcrdt_init_ack
		.p0_rx_st_dcrdt_init_i        (rtile_pcie_p0_rx_st_dcrdt_init),        //   input,    width = 3,                       .rx_st_Dcrdt_init
		.p0_rx_st_dcrdt_update_i      (rtile_pcie_p0_rx_st_dcrdt_update),      //   input,    width = 3,                       .rx_st_Dcrdt_update
		.p0_rx_st_dcrdt_update_cnt_i  (rtile_pcie_p0_rx_st_dcrdt_update_cnt),  //   input,   width = 12,                       .rx_st_Dcrdt_update_cnt
		.p0_rx_st_dcrdt_init_ack_o    (rtile_pcie_p0_rx_st_dcrdt_init_ack),    //  output,    width = 3,                       .rx_st_Dcrdt_init_ack
		.p0_rx_st1_data_o             (rtile_pcie_p0_rx_st1_data),             //  output,  width = 256,              p0_rx_st1.data
		.p0_rx_st1_sop_o              (rtile_pcie_p0_rx_st1_sop),              //  output,    width = 1,                       .startofpacket
		.p0_rx_st1_eop_o              (rtile_pcie_p0_rx_st1_eop),              //  output,    width = 1,                       .endofpacket
		.p0_rx_st1_dvalid_o           (rtile_pcie_p0_rx_st1_dvalid),           //  output,    width = 1,                       .valid
		.p0_rx_st1_empty_o            (rtile_pcie_p0_rx_st1_empty),            //  output,    width = 3,                       .empty
		.p0_rx_st2_data_o             (rtile_pcie_p0_rx_st2_data),             //  output,  width = 256,              p0_rx_st2.data
		.p0_rx_st2_sop_o              (rtile_pcie_p0_rx_st2_sop),              //  output,    width = 1,                       .startofpacket
		.p0_rx_st2_eop_o              (rtile_pcie_p0_rx_st2_eop),              //  output,    width = 1,                       .endofpacket
		.p0_rx_st2_dvalid_o           (rtile_pcie_p0_rx_st2_dvalid),           //  output,    width = 1,                       .valid
		.p0_rx_st2_empty_o            (rtile_pcie_p0_rx_st2_empty),            //  output,    width = 3,                       .empty
		.p0_rx_st3_data_o             (rtile_pcie_p0_rx_st3_data),             //  output,  width = 256,              p0_rx_st3.data
		.p0_rx_st3_sop_o              (rtile_pcie_p0_rx_st3_sop),              //  output,    width = 1,                       .startofpacket
		.p0_rx_st3_eop_o              (rtile_pcie_p0_rx_st3_eop),              //  output,    width = 1,                       .endofpacket
		.p0_rx_st3_dvalid_o           (rtile_pcie_p0_rx_st3_dvalid),           //  output,    width = 1,                       .valid
		.p0_rx_st3_empty_o            (rtile_pcie_p0_rx_st3_empty),            //  output,    width = 3,                       .empty
		.p0_tx_st_hcrdt_init_o        (rtile_pcie_p0_tx_st_hcrdt_init),        //  output,    width = 3,          p0_tx_st_misc.tx_st_Hcrdt_init
		.p0_tx_st_hcrdt_update_o      (rtile_pcie_p0_tx_st_hcrdt_update),      //  output,    width = 3,                       .tx_st_Hcrdt_update
		.p0_tx_st_hcrdt_update_cnt_o  (rtile_pcie_p0_tx_st_hcrdt_update_cnt),  //  output,    width = 6,                       .tx_st_Hcrdt_update_cnt
		.p0_tx_st_hcrdt_init_ack_i    (rtile_pcie_p0_tx_st_hcrdt_init_ack),    //   input,    width = 3,                       .tx_st_Hcrdtt_init_ack
		.p0_tx_st_dcrdt_init_o        (rtile_pcie_p0_tx_st_dcrdt_init),        //  output,    width = 3,                       .tx_st_Dcrdt_init
		.p0_tx_st_dcrdt_update_o      (rtile_pcie_p0_tx_st_dcrdt_update),      //  output,    width = 3,                       .tx_st_Dcrdt_update
		.p0_tx_st_dcrdt_update_cnt_o  (rtile_pcie_p0_tx_st_dcrdt_update_cnt),  //  output,   width = 12,                       .tx_st_Dcrdt_update_cnt
		.p0_tx_st_dcrdt_init_ack_i    (rtile_pcie_p0_tx_st_dcrdt_init_ack),    //   input,    width = 3,                       .tx_st_Dcrdt_init_ack
		.p0_tx_st0_hdr_i              (rtile_pcie_p0_tx_st0_hdr),              //   input,  width = 128,                       .tx_st0_hdr
		.p0_tx_st0_prefix_i           (rtile_pcie_p0_tx_st0_prefix),           //   input,   width = 32,                       .tx_st0_prefix
		.p0_tx_st0_hvalid_i           (rtile_pcie_p0_tx_st0_hvalid),           //   input,    width = 1,                       .tx_st0_hvalid
		.p0_tx_st0_pvalid_i           (rtile_pcie_p0_tx_st0_pvalid),           //   input,    width = 1,                       .tx_st0_pvalid
		.p0_tx_st1_hdr_i              (rtile_pcie_p0_tx_st1_hdr),              //   input,  width = 128,                       .tx_st1_hdr
		.p0_tx_st1_prefix_i           (rtile_pcie_p0_tx_st1_prefix),           //   input,   width = 32,                       .tx_st1_prefix
		.p0_tx_st1_hvalid_i           (rtile_pcie_p0_tx_st1_hvalid),           //   input,    width = 1,                       .tx_st1_hvalid
		.p0_tx_st1_pvalid_i           (rtile_pcie_p0_tx_st1_pvalid),           //   input,    width = 1,                       .tx_st1_pvalid
		.p0_tx_st2_hdr_i              (rtile_pcie_p0_tx_st2_hdr),              //   input,  width = 128,                       .tx_st2_hdr
		.p0_tx_st2_prefix_i           (rtile_pcie_p0_tx_st2_prefix),           //   input,   width = 32,                       .tx_st2_prefix
		.p0_tx_st2_hvalid_i           (rtile_pcie_p0_tx_st2_hvalid),           //   input,    width = 1,                       .tx_st2_hvalid
		.p0_tx_st2_pvalid_i           (rtile_pcie_p0_tx_st2_pvalid),           //   input,    width = 1,                       .tx_st2_pvalid
		.p0_tx_st3_hdr_i              (rtile_pcie_p0_tx_st3_hdr),              //   input,  width = 128,                       .tx_st3_hdr
		.p0_tx_st3_prefix_i           (rtile_pcie_p0_tx_st3_prefix),           //   input,   width = 32,                       .tx_st3_prefix
		.p0_tx_st3_hvalid_i           (rtile_pcie_p0_tx_st3_hvalid),           //   input,    width = 1,                       .tx_st3_hvalid
		.p0_tx_st3_pvalid_i           (rtile_pcie_p0_tx_st3_pvalid),           //   input,    width = 1,                       .tx_st3_pvalid
		.p0_tx_st_ready_o             (rtile_pcie_p0_tx_st_ready),             //  output,    width = 1,              p0_tx_st0.ready
		.p0_tx_st0_data_i             (rtile_pcie_p0_tx_st0_data),             //   input,  width = 256,                       .data
		.p0_tx_st0_sop_i              (rtile_pcie_p0_tx_st0_sop),              //   input,    width = 1,                       .startofpacket
		.p0_tx_st0_eop_i              (rtile_pcie_p0_tx_st0_eop),              //   input,    width = 1,                       .endofpacket
		.p0_tx_st0_dvalid_i           (rtile_pcie_p0_tx_st0_dvalid),           //   input,    width = 1,                       .valid
		.p0_tx_st1_data_i             (rtile_pcie_p0_tx_st1_data),             //   input,  width = 256,              p0_tx_st1.data
		.p0_tx_st1_sop_i              (rtile_pcie_p0_tx_st1_sop),              //   input,    width = 1,                       .startofpacket
		.p0_tx_st1_eop_i              (rtile_pcie_p0_tx_st1_eop),              //   input,    width = 1,                       .endofpacket
		.p0_tx_st1_dvalid_i           (rtile_pcie_p0_tx_st1_dvalid),           //   input,    width = 1,                       .valid
		.p0_tx_st2_data_i             (rtile_pcie_p0_tx_st2_data),             //   input,  width = 256,              p0_tx_st2.data
		.p0_tx_st2_sop_i              (rtile_pcie_p0_tx_st2_sop),              //   input,    width = 1,                       .startofpacket
		.p0_tx_st2_eop_i              (rtile_pcie_p0_tx_st2_eop),              //   input,    width = 1,                       .endofpacket
		.p0_tx_st2_dvalid_i           (rtile_pcie_p0_tx_st2_dvalid),           //   input,    width = 1,                       .valid
		.p0_tx_st3_data_i             (rtile_pcie_p0_tx_st3_data),             //   input,  width = 256,              p0_tx_st3.data
		.p0_tx_st3_sop_i              (rtile_pcie_p0_tx_st3_sop),              //   input,    width = 1,                       .startofpacket
		.p0_tx_st3_eop_i              (rtile_pcie_p0_tx_st3_eop),              //   input,    width = 1,                       .endofpacket
		.p0_tx_st3_dvalid_i           (rtile_pcie_p0_tx_st3_dvalid),           //   input,    width = 1,                       .valid
		.p0_tx_ehp_deallocate_empty_o (rtile_pcie_p0_tx_ehp_deallocate_empty), //  output,    width = 1,              p0_tx_ehp.tx_ehp_deallocate_empty
		.pin_perst_n                  (pcie_ep_perstn),                        //   input,    width = 1,              pin_perst.reset_n
		.pin_perst_n_o                (rtile_pcie_pin_perst_n_o)                 //  output,    width = 1,          pin_perst_n_o.reset_n
	);



	iopll iopll_inst (
		.refclk   (clk_sys_100m_p),   
		.locked   (), 
		.rst      (1'b0),     
		.outclk_0 (ftile_eth_reconfig_clk), 
		.outclk_1 () 
	);

	system_clk_and_ftile_ref_clk system_clk_and_ftile_ref_clk_inst (
		.out_systempll_synthlock_0 (), 							//  output,  width = 1, out_systempll_synthlock_0.out_systempll_synthlock
		.out_systempll_clk_0       (ftile_eth_clk_sys),       	//  output,  width = 1,       out_systempll_clk_0.clk
		.out_refclk_fgt_3          (),          				//  output,  width = 1,          out_refclk_fgt_3.clk
		.in_refclk_fgt_3           (qsfpdd_refclk_fgt),        	//   input,  width = 1,                refclk_fgt.in_refclk_fgt_3
		.in_refclk_fht_0           (qsfpdd_refclk_fht),         //   input,  width = 1,                refclk_fht.in_refclk_fht_0
		.out_fht_cmmpll_clk_0      (ftile_eth_clk_ref),      	//  output,  width = 1,      out_fht_cmmpll_clk_0.clk
		.disable_refclk_monitor_3  ()   						//   input,  width = 1,  disable_refclk_monitor_3.disable_refclk_monitor_3
	);

	ftile_reset ftile_reset_inst (
		.clk(ftile_eth_reconfig_clk),
		.i_reset_n(rtile_pcie_pin_perst_n_o),
		.i_reset_ack_n(ftile_eth_rst_ack_n),
		.o_reset_n(ftile_eth_rst_n)
	);



	ftile_eth_hip ftile_eth_hip_inst (
		.o_clk_pll                       (ftile_eth_clk_pll),                       //  output,     width = 1,             o_clk_pll.clk
		.i_reconfig_clk                  (ftile_eth_reconfig_clk),                  //   input,     width = 1,        i_reconfig_clk.clk
		.i_reconfig_reset                (ftile_eth_reconfig_reset),                //   input,     width = 1,      i_reconfig_reset.reset
		.o_sys_pll_locked                (ftile_eth_sys_pll_locked),                //  output,     width = 1,      o_sys_pll_locked.o_sys_pll_locked
		.o_tx_serial                     (qsfpdd0_tx_p),                     		//  output,     width = 8,                serial.o_tx_serial
		.i_rx_serial                     (qsfpdd0_rx_p),                     		//   input,     width = 8,                      .i_rx_serial
		.o_tx_serial_n                   (qsfpdd0_tx_n),                   			//  output,     width = 8,                      .o_tx_serial_n
		.i_rx_serial_n                   (qsfpdd0_rx_n),                   			//   input,     width = 8,                      .i_rx_serial_n
		.i_clk_ref                       (ftile_eth_clk_ref),                       //   input,     width = 1,             i_clk_ref.clk
		.i_clk_sys                       (ftile_eth_clk_sys),                       //   input,     width = 1,             i_clk_sys.clk
		.i_reconfig_eth_addr             (ftile_eth_reconfig_eth_addr),             //   input,    width = 14,    reconfig_eth_slave.address
		.i_reconfig_eth_byteenable       (ftile_eth_reconfig_eth_byteenable),       //   input,     width = 4,                      .byteenable
		.o_reconfig_eth_readdata_valid   (ftile_eth_reconfig_eth_readdata_valid),   //  output,     width = 1,                      .readdatavalid
		.i_reconfig_eth_read             (ftile_eth_reconfig_eth_read),             //   input,     width = 1,                      .read
		.i_reconfig_eth_write            (ftile_eth_reconfig_eth_write),            //   input,     width = 1,                      .write
		.o_reconfig_eth_readdata         (ftile_eth_reconfig_eth_readdata),         //  output,    width = 32,                      .readdata
		.i_reconfig_eth_writedata        (ftile_eth_reconfig_eth_writedata),        //   input,    width = 32,                      .writedata
		.o_reconfig_eth_waitrequest      (ftile_eth_reconfig_eth_waitrequest),      //  output,     width = 1,                      .waitrequest
		.i_clk_tx                        (ftile_eth_clk_pll),                       //   input,     width = 1,              i_tx_clk.clk
		.i_clk_rx                        (ftile_eth_clk_pll),                       //   input,     width = 1,              i_rx_clk.clk
		.i_rst_n                         (ftile_eth_rst_n),                         //   input,     width = 1,               i_rst_n.reset_n
		.i_tx_rst_n                      ('h1),                      				//   input,     width = 1,            i_tx_rst_n.reset_n
		.i_rx_rst_n                      ('h1),                      				//   input,     width = 1,            i_rx_rst_n.reset_n
		.o_rst_ack_n                     (ftile_eth_rst_ack_n),                     //  output,     width = 1,    reset_status_ports.o_rst_ack_n
		.o_tx_rst_ack_n                  (ftile_eth_tx_rst_ack_n),                  //  output,     width = 1,                      .o_tx_rst_ack_n
		.o_rx_rst_ack_n                  (ftile_eth_rx_rst_ack_n),                  //  output,     width = 1,                      .o_rx_rst_ack_n
		.o_cdr_lock                      (ftile_eth_cdr_lock),                      //  output,     width = 1,    clock_status_ports.o_cdr_lock
		.o_tx_pll_locked                 (ftile_eth_tx_pll_locked),                 //  output,     width = 1,                      .o_tx_pll_locked
		.o_tx_lanes_stable               (ftile_eth_tx_lanes_stable),               //  output,     width = 1,                      .o_tx_lanes_stable
		.o_rx_pcs_ready                  (ftile_eth_rx_pcs_ready),                  //  output,     width = 1,                      .o_rx_pcs_ready
		.o_clk_tx_div                    (ftile_eth_clk_tx_div),                    //  output,     width = 1,            clk_tx_div.clk
		.o_clk_rec_div64                 (ftile_eth_clk_rec_div64),                 //  output,     width = 1,         clk_rec_div64.clk
		.o_clk_rec_div                   (ftile_eth_clk_rec_div),                   //  output,     width = 1,           clk_rec_div.clk
		.o_rx_block_lock                 (ftile_eth_rx_block_lock),                 //  output,     width = 1,          status_ports.o_rx_block_lock
		.o_rx_am_lock                    (ftile_eth_rx_am_lock),                    //  output,     width = 1,                      .o_rx_am_lock
		.o_local_fault_status            (ftile_eth_local_fault_status),            //  output,     width = 1,                      .o_local_fault_status
		.o_remote_fault_status           (ftile_eth_remote_fault_status),           //  output,     width = 1,                      .o_remote_fault_status
		.i_stats_snapshot                (ftile_eth_stats_snapshot),                //   input,     width = 1,                      .i_stats_snapshot
		.o_rx_hi_ber                     (ftile_eth_rx_hi_ber),                     //  output,     width = 1,                      .o_rx_hi_ber
		.o_rx_pcs_fully_aligned          (ftile_eth_rx_pcs_fully_aligned),          //  output,     width = 1,                      .o_rx_pcs_fully_aligned
		.i_tx_mac_data                   (ftile_eth_tx_mac_data),                   //   input,  width = 1024,            tx_mac_seg.i_tx_mac_data
		.i_tx_mac_valid                  (ftile_eth_tx_mac_valid),                  //   input,     width = 1,                      .i_tx_mac_valid
		.i_tx_mac_inframe                (ftile_eth_tx_mac_inframe),                //   input,    width = 16,                      .i_tx_mac_inframe
		.i_tx_mac_eop_empty              (ftile_eth_tx_mac_eop_empty),              //   input,    width = 48,                      .i_tx_mac_eop_empty
		.o_tx_mac_ready                  (ftile_eth_tx_mac_ready),                  //  output,     width = 1,                      .o_tx_mac_ready
		.i_tx_mac_error                  (ftile_eth_tx_mac_error),                  //   input,    width = 16,                      .i_tx_mac_error
		.i_tx_mac_skip_crc               (ftile_eth_tx_mac_skip_crc),               //   input,    width = 16,                      .i_tx_mac_skip_crc
		.o_rx_mac_data                   (ftile_eth_rx_mac_data),                   //  output,  width = 1024,            rx_mac_seg.o_rx_mac_data
		.o_rx_mac_valid                  (ftile_eth_rx_mac_valid),                  //  output,     width = 1,                      .o_rx_mac_valid
		.o_rx_mac_inframe                (ftile_eth_rx_mac_inframe),                //  output,    width = 16,                      .o_rx_mac_inframe
		.o_rx_mac_eop_empty              (ftile_eth_rx_mac_eop_empty),              //  output,    width = 48,                      .o_rx_mac_eop_empty
		.o_rx_mac_fcs_error              (ftile_eth_rx_mac_fcs_error),              //  output,    width = 16,                      .o_rx_mac_fcs_error
		.o_rx_mac_error                  (ftile_eth_rx_mac_error),                  //  output,    width = 32,                      .o_rx_mac_error
		.o_rx_mac_status                 (ftile_eth_rx_mac_status),                 //  output,    width = 48,                      .o_rx_mac_status
		.i_tx_pause                      ('h0),                      				//   input,     width = 1,             sfc_ports.i_tx_pause
		.o_rx_pause                      (),                      					//  output,     width = 1,                      .o_rx_pause
		.i_reconfig_xcvr0_addr           ('h0),           							//   input,    width = 18, reconfig_xcvr_slave_0.address
		.i_reconfig_xcvr0_byteenable     ('h0),     								//   input,     width = 4,                      .byteenable
		.o_reconfig_xcvr0_readdata_valid (), 										//  output,     width = 1,                      .readdatavalid
		.i_reconfig_xcvr0_read           ('h0),           							//   input,     width = 1,                      .read
		.i_reconfig_xcvr0_write          ('h0),          							//   input,     width = 1,                      .write
		.o_reconfig_xcvr0_readdata       (),       									//  output,    width = 32,                      .readdata
		.i_reconfig_xcvr0_writedata      ('h0),      								//   input,    width = 32,                      .writedata
		.o_reconfig_xcvr0_waitrequest    (),    									//  output,     width = 1,                      .waitrequest
		.i_reconfig_xcvr1_addr           ('h0),           							//   input,    width = 18, reconfig_xcvr_slave_1.address
		.i_reconfig_xcvr1_byteenable     ('h0),     								//   input,     width = 4,                      .byteenable
		.o_reconfig_xcvr1_readdata_valid (), 										//  output,     width = 1,                      .readdatavalid
		.i_reconfig_xcvr1_read           ('h0),           							//   input,     width = 1,                      .read
		.i_reconfig_xcvr1_write          ('h0),          							//   input,     width = 1,                      .write
		.o_reconfig_xcvr1_readdata       (),       									//  output,    width = 32,                      .readdata
		.i_reconfig_xcvr1_writedata      ('h0),      								//   input,    width = 32,                      .writedata
		.o_reconfig_xcvr1_waitrequest    (),    									//  output,     width = 1,                      .waitrequest
		.i_reconfig_xcvr2_addr           ('h0),           							//   input,    width = 18, reconfig_xcvr_slave_2.address
		.i_reconfig_xcvr2_byteenable     ('h0),     								//   input,     width = 4,                      .byteenable
		.o_reconfig_xcvr2_readdata_valid (), 										//  output,     width = 1,                      .readdatavalid
		.i_reconfig_xcvr2_read           ('h0),           							//   input,     width = 1,                      .read
		.i_reconfig_xcvr2_write          ('h0),          							//   input,     width = 1,                      .write
		.o_reconfig_xcvr2_readdata       (),       									//  output,    width = 32,                      .readdata
		.i_reconfig_xcvr2_writedata      ('h0),      								//   input,    width = 32,                      .writedata
		.o_reconfig_xcvr2_waitrequest    (),    									//  output,     width = 1,                      .waitrequest
		.i_reconfig_xcvr3_addr           ('h0),           							//   input,    width = 18, reconfig_xcvr_slave_3.address
		.i_reconfig_xcvr3_byteenable     ('h0),     								//   input,     width = 4,                      .byteenable
		.o_reconfig_xcvr3_readdata_valid (), 										//  output,     width = 1,                      .readdatavalid
		.i_reconfig_xcvr3_read           ('h0),           							//   input,     width = 1,                      .read
		.i_reconfig_xcvr3_write          ('h0),          							//   input,     width = 1,                      .write
		.o_reconfig_xcvr3_readdata       (),       									//  output,    width = 32,                      .readdata
		.i_reconfig_xcvr3_writedata      ('h0),      								//   input,    width = 32,                      .writedata
		.o_reconfig_xcvr3_waitrequest    (),    									//  output,     width = 1,                      .waitrequest
		.i_clk_pll                       (ftile_eth_clk_pll),                       //   input,     width = 1,             i_clk_pll.clk
		.anlt_link                       (ftile_eth_anlt_link)                      //  output,     width = 1,            anlt_ports.anlt_link
	);

	rtile_reset_output_buffer rtile_reset_output_buffer_inst (
		.clk(rtile_pcie_coreclkout_hip),
		.i_reset_n(rtile_pcie_p0_reset_status_n), 
		.o_reset_n(rtile_pcie_p0_reset_status_n_buffered)
	);

    mkBsvTop bsv_top(
        .CLK(rtile_pcie_coreclkout_hip),
		.RST_N(rtile_pcie_p0_reset_status_n_buffered),
		.CLK_ftileClk(ftile_eth_clk_pll),
		.RST_N_ftileRst(ftile_eth_rst_n),
		// Rtile
		.rtilePcieAdaptorRxRawIfc_data({rtile_pcie_p0_rx_st3_data, rtile_pcie_p0_rx_st2_data, rtile_pcie_p0_rx_st1_data, rtile_pcie_p0_rx_st0_data}),
		.rtilePcieAdaptorRxRawIfc_hdr({rtile_pcie_p0_rx_st3_hdr, rtile_pcie_p0_rx_st2_hdr, rtile_pcie_p0_rx_st1_hdr, rtile_pcie_p0_rx_st0_hdr}),
		.rtilePcieAdaptorRxRawIfc_sop({rtile_pcie_p0_rx_st3_sop, rtile_pcie_p0_rx_st2_sop, rtile_pcie_p0_rx_st1_sop, rtile_pcie_p0_rx_st0_sop}),
		.rtilePcieAdaptorRxRawIfc_eop({rtile_pcie_p0_rx_st3_eop, rtile_pcie_p0_rx_st2_eop, rtile_pcie_p0_rx_st1_eop, rtile_pcie_p0_rx_st0_eop}),
		.rtilePcieAdaptorRxRawIfc_hvalid({rtile_pcie_p0_rx_st3_hvalid, rtile_pcie_p0_rx_st2_hvalid, rtile_pcie_p0_rx_st1_hvalid, rtile_pcie_p0_rx_st0_hvalid}),
		.rtilePcieAdaptorRxRawIfc_dvalid({rtile_pcie_p0_rx_st3_dvalid, rtile_pcie_p0_rx_st2_dvalid, rtile_pcie_p0_rx_st1_dvalid, rtile_pcie_p0_rx_st0_dvalid}),
		.rtilePcieAdaptorRxRawIfc_bar({rtile_pcie_p0_rx_st3_bar, rtile_pcie_p0_rx_st2_bar, rtile_pcie_p0_rx_st1_bar, rtile_pcie_p0_rx_st0_bar}),
		.rtilePcieAdaptorRxRawIfc_empty({rtile_pcie_p0_rx_st3_empty, rtile_pcie_p0_rx_st2_empty, rtile_pcie_p0_rx_st1_empty, rtile_pcie_p0_rx_st0_empty}),
		.rtilePcieAdaptorRxRawIfc_hcrdt_init_ack(rtile_pcie_p0_rx_st_hcrdt_init_ack),
		.rtilePcieAdaptorRxRawIfc_dcrdt_init_ack(rtile_pcie_p0_rx_st_dcrdt_init_ack),
		.rtilePcieAdaptorRxRawIfc_ready(rtile_pcie_p0_rx_st_ready),
		.rtilePcieAdaptorRxRawIfc_hcrdt_init(rtile_pcie_p0_rx_st_hcrdt_init),
		.rtilePcieAdaptorRxRawIfc_hcrdt_update(rtile_pcie_p0_rx_st_hcrdt_update),
		.rtilePcieAdaptorRxRawIfc_hcrdt_update_cnt(rtile_pcie_p0_rx_st_hcrdt_update_cnt),
		.rtilePcieAdaptorRxRawIfc_dcrdt_init(rtile_pcie_p0_rx_st_dcrdt_init),
		.rtilePcieAdaptorRxRawIfc_dcrdt_update(rtile_pcie_p0_rx_st_dcrdt_update),
		.rtilePcieAdaptorRxRawIfc_dcrdt_update_cnt(rtile_pcie_p0_rx_st_dcrdt_update_cnt),
		.rtilePcieAdaptorTxRawIfc_hcrdt_init(rtile_pcie_p0_tx_st_hcrdt_init),
		.rtilePcieAdaptorTxRawIfc_hcrdt_update(rtile_pcie_p0_tx_st_hcrdt_update),
		.rtilePcieAdaptorTxRawIfc_hcrdt_update_cnt(rtile_pcie_p0_tx_st_hcrdt_update_cnt),
		.rtilePcieAdaptorTxRawIfc_dcrdt_init(rtile_pcie_p0_tx_st_dcrdt_init),
		.rtilePcieAdaptorTxRawIfc_dcrdt_update(rtile_pcie_p0_tx_st_dcrdt_update),
		.rtilePcieAdaptorTxRawIfc_dcrdt_update_cnt(rtile_pcie_p0_tx_st_dcrdt_update_cnt),
		.rtilePcieAdaptorTxRawIfc_ready(rtile_pcie_p0_tx_st_ready),
		.rtilePcieAdaptorTxRawIfc_hcrdt_init_ack(rtile_pcie_p0_tx_st_hcrdt_init_ack),
		.rtilePcieAdaptorTxRawIfc_dcrdt_init_ack(rtile_pcie_p0_tx_st_dcrdt_init_ack),
		.rtilePcieAdaptorTxRawIfc_hdr({rtile_pcie_p0_tx_st3_hdr, rtile_pcie_p0_tx_st2_hdr, rtile_pcie_p0_tx_st1_hdr, rtile_pcie_p0_tx_st0_hdr}),
		.rtilePcieAdaptorTxRawIfc_data({rtile_pcie_p0_tx_st3_data, rtile_pcie_p0_tx_st2_data, rtile_pcie_p0_tx_st1_data, rtile_pcie_p0_tx_st0_data}),
		.rtilePcieAdaptorTxRawIfc_sop({rtile_pcie_p0_tx_st3_sop, rtile_pcie_p0_tx_st2_sop, rtile_pcie_p0_tx_st1_sop, rtile_pcie_p0_tx_st0_sop}),
		.rtilePcieAdaptorTxRawIfc_eop({rtile_pcie_p0_tx_st3_eop, rtile_pcie_p0_tx_st2_eop, rtile_pcie_p0_tx_st1_eop, rtile_pcie_p0_tx_st0_eop}),
		.rtilePcieAdaptorTxRawIfc_hvalid({rtile_pcie_p0_tx_st3_hvalid, rtile_pcie_p0_tx_st2_hvalid, rtile_pcie_p0_tx_st1_hvalid, rtile_pcie_p0_tx_st0_hvalid}),
		.rtilePcieAdaptorTxRawIfc_dvalid({rtile_pcie_p0_tx_st3_dvalid, rtile_pcie_p0_tx_st2_dvalid, rtile_pcie_p0_tx_st1_dvalid, rtile_pcie_p0_tx_st0_dvalid}),
		
		// FTile
		.ftileMacAdaptorRxRawIfc_data(ftile_eth_rx_mac_data),
		.ftileMacAdaptorRxRawIfc_valid(ftile_eth_rx_mac_valid),
		.ftileMacAdaptorRxRawIfc_inframe(ftile_eth_rx_mac_inframe),
		.ftileMacAdaptorRxRawIfc_eop_empty(ftile_eth_rx_mac_eop_empty),
		.ftileMacAdaptorRxRawIfc_fcs_error(ftile_eth_rx_mac_fcs_error),
		.ftileMacAdaptorRxRawIfc_error(ftile_eth_rx_mac_error),
		.ftileMacAdaptorRxRawIfc_status_data(ftile_eth_rx_mac_status),
		.ftileMacAdaptorRxRawIfc_ready(),
		.ftileMacAdaptorTxRawIfc_ready(ftile_eth_tx_mac_ready),
		.ftileMacAdaptorTxRawIfc_data(ftile_eth_tx_mac_data),
		.ftileMacAdaptorTxRawIfc_valid(ftile_eth_tx_mac_valid),
		.ftileMacAdaptorTxRawIfc_inframe(ftile_eth_tx_mac_inframe),
		.ftileMacAdaptorTxRawIfc_eop_empty(ftile_eth_tx_mac_eop_empty),
		.ftileMacAdaptorTxRawIfc_error(ftile_eth_tx_mac_error),
		.ftileMacAdaptorTxRawIfc_skip_crc(ftile_eth_tx_mac_skip_crc)
    );


endmodule