`timescale 1ns/1ns

`define INST_NOP 32'h00000013

module auv_fetch #(
    parameter integer ADDR_WIDTH = 24,
    parameter integer BOOTROM_WIDTH = 10
) (
    input   logic           clk, pop, jmp,
    input   logic   [ADDR_WIDTH-3:0] pc_wr,
    output  logic   [31:0]  inst,
    output  logic   [ADDR_WIDTH-3:0] pc_out,
    // to bootrom
    output  logic   [BOOTROM_WIDTH-1:0] rom_adr,
    input   logic   [31:0]  rom_dat
);

    logic [ADDR_WIDTH-3:0] pc, pc_next;

    assign pc_out = pc;
    assign pc_next = (pc + 1);
    assign inst = jmp ? `INST_NOP : rom_dat;

    always_comb
        if (jmp)
            rom_adr = pc_wr[BOOTROM_WIDTH-1:0];
        else if (pop)
            rom_adr = pc_next[BOOTROM_WIDTH-1:0];
        else
            rom_adr = pc[BOOTROM_WIDTH-1:0];

    always_ff @( posedge clk )
        if (jmp)
            pc <= pc_wr;
        else if (pop)
            pc <= pc_next;


endmodule
