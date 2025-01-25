`timescale 1ns/1ns

`define INST_NOP 32'h00000013

module auv_fetch #(
    parameter integer ADDR_WIDTH = 24,
    parameter string ROM_FNAME = "bootrom.mem",
    parameter integer ROM_SIZE = 8192,
    localparam integer RomSizeWords = ROM_SIZE / 4,
    localparam integer RomWidth = $clog2(RomSizeWords)
) (
    input   logic                       clk, rst_n, pop, jmp,
    input   logic   [ADDR_WIDTH-3:0]    pc_wr,
    output  logic   [31:0]              inst,
    output  logic   [ADDR_WIDTH-3:0]    pc_out,
    output  logic                       instret,
    // bootrom bridge for data access
    input   logic   [RomWidth+1:0]      wb_adr_i,
    output  logic   [15:0]              wb_dat_o,
    input   logic                       wb_stb_i, wb_cyc_i,
    output  logic                       wb_ack_o
);

    logic data_access;
    assign data_access = (wb_stb_i & wb_cyc_i);

    // bootrom
    logic [RomWidth-1:0] rom_adr, rom_adr_fetch;
    logic [31:0] rom_dat;
    assign rom_adr = data_access ? wb_adr_i[RomWidth+1:2] : rom_adr_fetch;

    rom #(
        .ROM_FNAME(ROM_FNAME),
        .ROM_SIZE(ROM_SIZE)
    ) bootrom (
        .clk(clk),
        .rom_adr(rom_adr),
        .rom_dat(rom_dat)
    );

    // instruction fetch
    logic [ADDR_WIDTH-3:0] pc, pc_next;
    logic inst_invalid;

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n)
            inst_invalid <= 0;
        else
            inst_invalid <= data_access;

    assign pc_out = pc;
    assign pc_next = (pc + 1);
    assign inst = (jmp | inst_invalid) ? `INST_NOP : rom_dat;
    assign instret = (pop & ~data_access);

    always_comb
        if (jmp)
            rom_adr_fetch = pc_wr[RomWidth-1:0];
        else if (pop)
            rom_adr_fetch = pc_next[RomWidth-1:0];
        else
            rom_adr_fetch = pc[RomWidth-1:0];

    always_ff @( posedge clk )
        if (jmp)
            pc <= pc_wr;
        else if (instret)
            pc <= pc_next;

    // wishbone logic for data access
    logic data_word_sel;
    assign wb_dat_o = data_word_sel ? rom_dat[31:16] : rom_dat[15:0];
    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            wb_ack_o <= 0;
            data_word_sel <= 0;
        end else begin
            wb_ack_o <= data_access;
            data_word_sel <= wb_adr_i[1];
        end


endmodule
