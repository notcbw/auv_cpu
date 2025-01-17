`timescale 1ns/1ns

module auv_bootrom #(
    parameter string ROM_FNAME = "bootrom.mem",
    parameter integer ROM_SIZE = 8192,
    localparam integer RomSizeWords = ROM_SIZE / 4,
    localparam integer RomWidth = $clog2(RomSizeWords)
) (
    input   logic                   clk, rst_n,
    // to cpu fetch unit
    input   logic   [RomWidth-1:0]  rom_adr,
    output  logic   [31:0]          rom_dat,
    // 16-bit wishbone 4 slave
    input   logic   [RomWidth+1:0]  wb_adr_i,
    output  logic   [15:0]          wb_dat_o,
    input   logic                   wb_stb_i, wb_cyc_i,
    output  logic                   wb_ack_o
);

    reg [31:0] rom [RomSizeWords];
    initial $readmemh(ROM_FNAME, rom);

    always_ff @( posedge clk )
        rom_dat <= rom[rom_adr];

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            wb_ack_o <= 0;
        end else begin
            wb_ack_o <= 0;
            if (wb_stb_i & wb_cyc_i) begin
                wb_ack_o <= 1;
                wb_dat_o <= rom[wb_adr_i[RomWidth+1:2]][wb_adr_i[0] * 16 +: 16];
            end
        end

endmodule
