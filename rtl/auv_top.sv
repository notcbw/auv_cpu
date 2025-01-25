`timescale 1ns/1ns

`include "auv_pkg.sv"

import auv_pkg::*;

module auv_top #(
    parameter integer ADDR_WIDTH = 24,
    parameter string ROM_FNAME = "bootrom.mem",
    parameter integer ROM_SIZE = 8192,
    parameter bit [ADDR_WIDTH-1:0] RST_VECTOR = 'h0,
    parameter bit [ADDR_WIDTH-1:0] NMI_VECTOR = 'h0,
    parameter integer INT_COUNT = 16,
    localparam integer RomSizeWords = ROM_SIZE / 4,
    localparam integer RomWidth = $clog2(RomSizeWords)
) (
    input   logic                       clk, rst_n,
    input   logic                       nmi, int_timer,
    input   logic   [INT_COUNT-1:0]     irq_input,
    // wishbone master
    output  logic   [ADDR_WIDTH-1:0]    wb_adr_o,
    input   logic   [15:0]              wb_dat_i,
    output  logic   [15:0]              wb_dat_o,
    output  logic   [ 1:0]              wb_sel_o,
    output  logic                       wb_we_o, wb_stb_o, wb_cyc_o,
    input   logic                       wb_ack_i, wb_stall_i, wb_err_i,
    // bootrom wishbone slave
    input   logic   [RomWidth+1:0]      rom_wb_adr_i,
    output  logic   [15:0]              rom_wb_dat_o,
    input   logic                       rom_wb_stb_i, rom_wb_cyc_i,
    output  logic                       rom_wb_ack_o
);

    logic exc_illegal_inst, exc_illegal_inst_csr, exc_ecall, exc_ebreak;
    logic exc_load_misalign, exc_store_misalign;
    logic exc_load_fault, exc_store_fault;

    logic [ADDR_WIDTH-3:0] id_pc, ex_pc;

    logic [31:0] if_inst;

    logic [31:0] id_imm;
    logic [3:0] id_rs1, id_rs2, id_rd;
    logic [2:0] id_funct3;
    logic [4:0] id_csr_imm;
    logic id_pop, id_alu_en, id_mem_access, id_pc_wr, id_branch, id_mem_wr;
    logic id_reg_wr, id_link, id_csr_en, id_csr_rd, id_ret, id_wfi;
    logic id_alu_alt, id_zba_shadd, id_zbs_bclrbext, id_zbs_binv, id_zbs_bset;
    sel_op1_t id_sel_op1;
    sel_op2_t id_sel_op2;

    logic [31:0] reg_rs1, reg_rs2;

    logic [ADDR_WIDTH-1:0] ex_pc_wr;
    logic [31:0] ex_reg_wr_dat;
    logic ex_jmp, ex_stall, ex_flush;
    logic ex_reg_wr;

    logic csr_stall, csr_reg_wr;
    logic [31:0] csr_reg_wr_dat;

    logic [11:0] cbus_adr;
    logic [31:0] cbus_dat_wr, cbus_dat_rd;
    logic cbus_rd, cbus_wr, cbus_ack;

    logic [ADDR_WIDTH-3:0] trapc_pc_wr;
    logic trapc_jmp, trapc_flush, trapc_stall;
    logic int_ext;

    logic [ADDR_WIDTH-3:0] pc_wr;
    logic jmp, flush;
    assign pc_wr = trapc_jmp ? trapc_pc_wr : ex_pc_wr[ADDR_WIDTH-1:2];
    assign jmp = ex_jmp | trapc_jmp;
    assign flush = ex_flush | trapc_flush;

    logic reg_wr;
    logic [31:0] reg_wr_dat;
    assign reg_wr = csr_reg_wr | ex_reg_wr;
    assign reg_wr_dat = csr_reg_wr ? csr_reg_wr_dat : ex_reg_wr_dat;

    auv_fetch #(
        .ADDR_WIDTH         ( ADDR_WIDTH        ),
        .ROM_FNAME          ( ROM_FNAME         ),
        .ROM_SIZE           ( ROM_SIZE          )
    ) stage_if (
        .clk                ( clk               ),
        .rst_n              ( rst_n             ),
        .pop                ( id_pop            ),
        .jmp                ( jmp               ),
        .pc_wr              ( pc_wr             ),
        .inst               ( if_inst           ),
        .pc_out             ( id_pc             ),
        .instret            (                   ),
        .wb_adr_i           ( rom_wb_adr_i      ),
        .wb_dat_o           ( rom_wb_dat_o      ),
        .wb_stb_i           ( rom_wb_stb_i      ),
        .wb_cyc_i           ( rom_wb_cyc_i      ),
        .wb_ack_o           ( rom_wb_ack_o      )
    );

    auv_decode #(
        .ADDR_WIDTH         ( ADDR_WIDTH            )
    ) stage_id (
        .clk                ( clk                   ),
        .rst_n              ( rst_n                 ),
        .flush              ( flush                 ),
        .stall_i            ( ex_stall              ),
        .inst               ( if_inst               ),
        .pc_in              ( id_pc                 ),
        .pc_out             ( ex_pc                 ),
        .pop                ( id_pop                ),
        .imm                ( id_imm                ),
        .rs1                ( id_rs1                ),
        .rs2                ( id_rs2                ),
        .rd                 ( id_rd                 ),
        .funct3             ( id_funct3             ),
        .csr_imm            ( id_csr_imm            ),
        .alu_en             ( id_alu_en             ),
        .mem_access         ( id_mem_access         ),
        .pc_wr              ( id_pc_wr              ),
        .branch             ( id_branch             ),
        .mem_wr             ( id_mem_wr             ),
        .reg_wr             ( id_reg_wr             ),
        .link               ( id_link               ),
        .sel_op1            ( id_sel_op1            ),
        .sel_op2            ( id_sel_op2            ),
        .csr_en             ( id_csr_en             ),
        .csr_rd             ( id_csr_rd             ),
        .exc_illegal_inst   ( exc_illegal_inst      ),
        .exc_ecall          ( exc_ecall             ),
        .exc_ebreak         ( exc_ebreak            ),
        .ret                ( id_ret                ),
        .wfi                ( id_wfi                ),
        .alu_alt            ( id_alu_alt            ),
        .zba_shadd          ( id_zba_shadd          ),
        .zbs_bclrbext       ( id_zbs_bclrbext       ),
        .zbs_binv           ( id_zbs_binv           ),
        .zbs_bset           ( id_zbs_bset           )
    );

    auv_regfile regfile (
        .clk    ( clk           ),
        .we     ( reg_wr        ),
        .stall  ( ex_stall      ),
        .ra0    ( id_rs1        ),
        .ra1    ( id_rs2        ),
        .wa     ( id_rd         ),
        .wd     ( reg_wr_dat    ),
        .rd0    ( reg_rs1       ),
        .rd1    ( reg_rs2       )
    );

    auv_execute #(
        .ADDR_WIDTH         ( ADDR_WIDTH            )
    ) stage_ex (
        .clk                ( clk                   ),
        .rst_n              ( rst_n                 ),
        .stall_i            ( trapc_stall | csr_stall ),
        .imm                ( id_imm                ),
        .rs1                ( reg_rs1               ),
        .rs2                ( reg_rs2               ),
        .pc                 ( {{(32-ADDR_WIDTH){1'b0}}, ex_pc, 2'b0} ),
        .funct3             ( id_funct3             ),
        .alu_en             ( id_alu_en             ),
        .mem_access         ( id_mem_access         ),
        .pc_wr_i            ( id_pc_wr              ),
        .branch             ( id_branch             ),
        .mem_wr             ( id_mem_wr             ),
        .reg_wr_i           ( id_reg_wr             ),
        .link               ( id_link               ),
        .sel_op1            ( id_sel_op1            ),
        .sel_op2            ( id_sel_op2            ),
        .reg_wr_dat         ( ex_reg_wr_dat         ),
        .pc_wr              ( ex_pc_wr              ),
        .stall_o            ( ex_stall              ),
        .reg_wr_o           ( ex_reg_wr             ),
        .jmp                ( ex_jmp                ),
        .flush              ( ex_flush              ),
        .exc_load_misalign  ( exc_load_misalign     ),
        .exc_store_misalign ( exc_store_misalign    ),
        .exc_load_fault     ( exc_load_fault        ),
        .exc_store_fault    ( exc_store_fault       ),
        .alu_alt            ( id_alu_alt            ),
        .zba_shadd          ( id_zba_shadd          ),
        .zbs_bclrbext       ( id_zbs_bclrbext       ),
        .zbs_binv           ( id_zbs_binv           ),
        .zbs_bset           ( id_zbs_bset           ),
        .wb_adr_o           ( wb_adr_o              ),
        .wb_dat_i           ( wb_dat_i              ),
        .wb_dat_o           ( wb_dat_o              ),
        .wb_sel_o           ( wb_sel_o              ),
        .wb_we_o            ( wb_we_o               ),
        .wb_stb_o           ( wb_stb_o              ),
        .wb_cyc_o           ( wb_cyc_o              ),
        .wb_ack_i           ( wb_ack_i              ),
        .wb_stall_i         ( wb_stall_i            ),
        .wb_err_i           ( wb_err_i              )
    );

    auv_csr stage_ex_csr (
        .clk                ( clk                   ),
        .rst_n              ( rst_n                 ),
        .en                 ( id_csr_en             ),
        .csr_rd             ( id_csr_rd             ),
        .funct3             ( id_funct3             ),
        .csr_adr            ( id_imm[11:0]          ),
        .rs1                ( reg_rs1               ),
        .rd_i               ( id_rd                 ),
        .imm                ( id_csr_imm            ),
        .stall              ( csr_stall             ),
        .reg_wr             ( csr_reg_wr            ),
        .reg_dat_wr         ( csr_reg_wr_dat        ),
        .exc_illegal_inst   ( exc_illegal_inst_csr  ),
        .cbus_adr           ( cbus_adr              ),
        .cbus_dat_wr        ( cbus_dat_wr           ),
        .cbus_dat_rd        ( cbus_dat_rd           ),
        .cbus_rd            ( cbus_rd               ),
        .cbus_wr            ( cbus_wr               ),
        .cbus_ack           ( cbus_ack              )
    );

    logic cbus_sel_trapc, cbus_ack_trapc;
    logic [31:0] cbus_dat_rd_trapc;
    assign cbus_sel_trapc = (cbus_adr[11:7] == 'b00110);
    auv_trapc #(
        .ADDR_WIDTH             ( ADDR_WIDTH            ),
        .RST_VECTOR             ( RST_VECTOR            ),
        .NMI_VECTOR             ( NMI_VECTOR            )
    ) trapc_unit (
        .clk                    ( clk                   ),
        .rst_n                  ( rst_n                 ),
        .nmi                    ( nmi                   ),
        .stall_i                ( ex_stall              ),
        .int_ext                ( int_ext               ),
        .int_timer              ( int_timer             ),
        .stall                  ( trapc_stall           ),
        .flush                  ( trapc_flush           ),
        .pc_in_id               ( id_pc                 ),
        .pc_in_ex               ( ex_pc                 ),
        .jmp                    ( trapc_jmp             ),
        .pc_wr                  ( trapc_pc_wr           ),
        .exc_illegal_inst       ( exc_illegal_inst      ),
        .exc_illegal_inst_csr   ( exc_illegal_inst_csr  ),
        .exc_ecall              ( exc_ecall             ),
        .exc_ebreak             ( exc_ebreak            ),
        .exc_load_misalign      ( exc_load_misalign     ),
        .exc_store_misalign     ( exc_store_misalign    ),
        .exc_load_fault         ( exc_load_fault        ),
        .exc_store_fault        ( exc_store_fault       ),
        .ret                    ( id_ret                ),
        .wfi                    ( id_wfi                ),
        .cbus_sel               ( cbus_sel_trapc        ),
        .cbus_adr               ( cbus_adr[6:0]         ),
        .cbus_dat_wr            ( cbus_dat_wr           ),
        .cbus_dat_rd            ( cbus_dat_rd_trapc     ),
        .cbus_rd                ( cbus_rd               ),
        .cbus_wr                ( cbus_wr               ),
        .cbus_ack               ( cbus_ack_trapc        )
    );

    logic cbus_sel_intc, cbus_ack_intc;
    logic [31:0] cbus_dat_rd_intc;
    assign cbus_sel_intc = (cbus_adr[11:2] == 'b1111110000);
    auv_intc #(
        .INT_COUNT      ( INT_COUNT         )
    ) intc_unit (
        .clk            ( clk               ),
        .rst_n          ( rst_n             ),
        .irq_input      ( irq_input         ),
        .int_ext        ( int_ext           ),
        .cbus_sel       ( cbus_sel_intc     ),
        .cbus_adr       ( cbus_adr[1:0]     ),
        .cbus_dat_wr    ( cbus_dat_wr       ),
        .cbus_dat_rd    ( cbus_dat_rd_intc  ),
        .cbus_rd        ( cbus_rd           ),
        .cbus_wr        ( cbus_wr           ),
        .cbus_ack       ( cbus_ack_intc     )
    );

    assign cbus_ack = cbus_ack_intc | cbus_ack_trapc;
    always_comb begin
        cbus_dat_rd = 0;
        if (cbus_sel_trapc)
            cbus_dat_rd = cbus_dat_rd_trapc;
        if (cbus_sel_intc)
            cbus_dat_rd = cbus_dat_rd_intc;
    end

endmodule
