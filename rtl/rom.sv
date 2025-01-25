`timescale 1ns/1ns

module rom #(
    parameter string ROM_FNAME = "bootrom.mem",
    parameter integer ROM_SIZE = 8192,
    localparam integer RomSizeWords = ROM_SIZE / 4,
    localparam integer RomWidth = $clog2(RomSizeWords)
) (
    input logic clk,
    input logic [RomWidth-1:0] rom_adr,
    output logic [31:0] rom_dat
);

    reg [31:0] rom [RomSizeWords];

    initial $readmemh(ROM_FNAME, rom);

    always_ff @( posedge clk )
        rom_dat <= rom[rom_adr];

endmodule
