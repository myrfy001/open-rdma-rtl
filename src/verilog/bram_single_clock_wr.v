module bram_single_clock_wr#(
        parameter ADDR_WIDTH = 8,
        parameter DATA_WIDTH = 8,
        parameter FILE = ""
    )(
        output reg [(DATA_WIDTH-1):0] q,
        input [(DATA_WIDTH-1):0] d,
        input [(ADDR_WIDTH-1):0] write_address, read_address,
        input we, clk
    );

    reg [(DATA_WIDTH-1):0] mem [(2**DATA_WIDTH-1):0];

    initial begin : init_rom_block
        $readmemb(FILE, mem);
    end // initial begin


    always @ (posedge clk) begin
        if (we)
            mem[write_address] = d;
        q = mem[read_address]; // q does get d in this clock 
                               // cycle if we is high
    end
endmodule