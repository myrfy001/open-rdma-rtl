module rtile_reset_output_buffer(
    input  wire                 clk,
    input  wire                 i_reset_n,
    output wire                 o_reset_n
);

    reg  reset_n_reg1;
    reg  reset_n_reg2;
    reg  reset_n_reg3;
    reg  reset_n_reg4;

    assign o_reset_n = reset_n_reg4;

    always @(posedge clk) begin
        if (!i_reset_n) begin
            reset_n_reg1 <= 0;
        end
        else begin
            reset_n_reg1 <= 1;
        end

        reset_n_reg2 <= reset_n_reg1;
        reset_n_reg3 <= reset_n_reg2;
        reset_n_reg4 <= reset_n_reg3;
    end
endmodule