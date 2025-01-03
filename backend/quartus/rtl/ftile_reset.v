module ftile_reset(
    input  wire                 clk,
    input  wire                 i_reset_n,
    input  wire                 i_reset_ack_n,
    output wire                 o_reset_n
);

    reg  reset_n_reg;

    assign o_reset_n = reset_n_reg;

    always @(posedge clk) begin
        if (!i_reset_n) begin
            reset_n_reg <= 0;
        end
        else if (!i_reset_ack_n) begin
            reset_n_reg <= 1;
        end
    end
endmodule