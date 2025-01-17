`timescale 1ns/1ns

`include "auv_pkg.sv"

import auv_pkg::*;

module auv_execute #(
    parameter integer ADDR_WIDTH = 24
) (
    input   logic           clk, rst_n, stall_i,
    input   logic   [31:0]  imm, rs1, rs2, pc,
    input   logic   [ 2:0]  funct3,
    input   logic           alu_en, mem_access, pc_wr_i, branch,
    input   logic           mem_wr, reg_wr_i, link,
    input   sel_op1_t       sel_op1,
    input   sel_op2_t       sel_op2,
    output  logic   [31:0]  reg_wr_dat,
    output  logic   [ADDR_WIDTH-1:0] pc_wr,
    output  logic           stall_o, reg_wr_o, jmp, flush,
    output  logic           exc_load_misalign, exc_store_misalign,
    output  logic           exc_load_fault, exc_store_fault,
    // decoded funct7
    input   logic           alu_alt, zba_shadd,
    input   logic           zbs_bclrbext, zbs_binv, zbs_bset,
    // wishbone master
    output  logic   [ADDR_WIDTH-1:0] wb_adr_o,
    input   logic   [15:0]  wb_dat_i,
    output  logic   [15:0]  wb_dat_o,
    output  logic   [ 1:0]  wb_sel_o,
    output  logic           wb_we_o, wb_stb_o, wb_cyc_o,
    input   logic           wb_ack_i, wb_stall_i, wb_err_i
);

    // branch condition
    logic branch_taken, lt, ltu;
    assign lt = $signed(rs1) < $signed(rs2);
    assign ltu = rs1 < rs2;
    always_comb begin
        if (branch) begin
            case (funct3)
                'h0 : branch_taken = (rs1 == rs2);
                'h1 : branch_taken = (rs1 != rs2);
                'h4 : branch_taken = lt;
                'h5 : branch_taken = ~lt;
                'h6 : branch_taken = ltu;
                'h7 : branch_taken = ~ltu;
                default : branch_taken = 0;
            endcase
        end else begin
            branch_taken = 1;
        end
    end

    // operator select
    logic [31:0] op1, op2;
    always_comb
        case (sel_op1)
            OP1_PC : op1 = pc;
            default : begin
                case ({zba_shadd, funct3})
                    default : op1 = rs1;
                    'b1010 : op1 = {rs1[30:0], 1'b0}; //sh1add
                    'b1100 : op1 = {rs1[29:0], 2'b0}; //sh2add
                    'b1110 : op1 = {rs1[28:0], 3'b0}; //sh3add
                endcase
            end
        endcase

    always_comb
        case (sel_op2)
            OP2_IMM : op2 = imm;
            default : op2 = rs2;
        endcase

    // alu
    logic [31:0] alu_add, alu_xor, alu_or, alu_and;
    logic [31:0] alu_sl, alu_sr, alu_slt, alu_sltu;
    logic [31:0] alu_bclr, alu_bext, alu_binv, alu_bset;
    assign alu_add = $signed(op1) + $signed(alu_alt ? ~op2 : op2);
    assign alu_xor = op1 ^ op2;
    assign alu_or = op1 | op2;
    assign alu_and = op1 & op2;
    assign alu_sl = op1 << op2[4:0];
    assign alu_sr = alu_alt ? ($signed(op1) >>> op2[4:0]) : (op1 >> op2[4:0]);
    assign alu_slt = (op1 < op2) ? 32'h1 : 32'h0;
    assign alu_sltu = ($signed(op1) < $signed(op2)) ? 32'h1 : 32'h0;
    assign alu_bclr = op1 & ~32'(1 << op2[4:0]);
    assign alu_bext = {31'h0, op1[op2[4:0]]};
    assign alu_binv = op1 ^ ~32'(1 << op2[4:0]);
    assign alu_bset = op1 | 32'(1 << op2[4:0]);

    logic [31:0] alu_out;
    always_comb
        if (alu_en)
            case (funct3)
                default : alu_out = alu_add;
                'h1 : begin
                    if (zbs_bclrbext)
                        alu_out = alu_bclr;
                    else if (zbs_binv)
                        alu_out = alu_binv;
                    else if (zbs_bset)
                        alu_out =  alu_bset;
                    else
                        alu_out = alu_sl;
                end
                'h2 : begin
                    if (zba_shadd)
                        alu_out = alu_add;
                    else
                        alu_out = alu_slt;
                end
                'h3 : alu_out = alu_sltu;
                'h4 : begin
                    if (zba_shadd)
                        alu_out = alu_add;
                    else
                        alu_out = alu_xor;
                end
                'h5 : begin
                    if (zbs_bclrbext)
                        alu_out = alu_bext;
                    else
                        alu_out = alu_sr;
                end
                'h6 : begin
                    if (zba_shadd)
                        alu_out = alu_add;
                    else
                        alu_out = alu_or;
                end
                'h7 : alu_out = alu_and;
            endcase
        else
            alu_out = alu_add;

    // pc write output
    assign pc_wr = alu_out[ADDR_WIDTH-1:0];
    assign jmp = pc_wr_i & branch_taken;
    assign flush = jmp;

    // wb signal
    logic [31:0] mem_dat;
    logic mem_reg_wr; // set when data is loaded from memory
    assign reg_wr_dat = link ? (pc + 4) : alu_out;
    assign reg_wr_o = ~stall_i & (mem_reg_wr | reg_wr_i);

    // bus
    // detect load/store fault
    assign exc_load_fault = mem_access & ~mem_wr & wb_err_i;
    assign exc_store_fault = mem_access & mem_wr & wb_err_i;

    // detect load/store misalign
    logic misalign;
    assign exc_load_misalign = mem_access & misalign & ~mem_wr;
    assign exc_store_misalign = mem_access & misalign & mem_wr;
    always_comb
        case (funct3[1:0])
            1 : misalign = ~alu_out[0];
            2 : misalign = (alu_out[1:0] != 0);
            default : misalign = 0;
        endcase

    assign wb_we_o = mem_wr;
    assign wb_adr_o[ADDR_WIDTH-1:2] = alu_out[ADDR_WIDTH-1:2];
    assign wb_adr_o[1] = (funct3 == 2) ? (state_bus == 1) : alu_out[0];
    assign wb_adr_o[0] = 0;

    always_comb
        case (funct3[1:0])
            0 : begin
                wb_dat_o = {rs2[7:0], rs2[7:0]};
                wb_sel_o = alu_out[0] ? 2'b10 : 2'b01;
            end
            1 : begin
                wb_dat_o = rs2[15:0];
                wb_sel_o = 2'b11;
            end
            default : begin
                wb_dat_o = (state_bus == 1) ? rs2[31:16] : rs2[15:0];
                wb_sel_o = 2'b11;
            end
        endcase

    logic [15:0] word_buf; // buffer for the upper word
    always_comb
        case (funct3[1:0])
            'h0: begin
                if (alu_out[0])
                    mem_dat = {{24{~funct3[2] & wb_dat_i[7]}}, wb_dat_i[7:0]};
                else
                    mem_dat = {{24{~funct3[2] & wb_dat_i[15]}}, wb_dat_i[15:8]};
            end
            'h1 : mem_dat = {{16{~funct3[2] & wb_dat_i[15]}}, wb_dat_i};
            default : mem_dat = {word_buf, wb_dat_i};
        endcase

    logic mem_access_good; // if the memory access cycle could be started
    assign mem_access_good = ~stall_i & ~misalign & mem_access;
    logic [1:0] state_bus;
    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n)
            state_bus <= 0;
        else begin
            case (state_bus)
                0 : begin
                    if (~wb_stall_i & mem_access_good) begin
                        if (funct3[1:0] == 2)
                            state_bus <= 1;
                        else
                            state_bus <= 2;
                    end
                end
                1 : begin
                    if (wb_ack_i)
                        word_buf <= wb_dat_i;
                    state_bus <= wb_stall_i ? 1 : 2;
                end
                default : state_bus <= 0;
            endcase
        end

    logic stall_mem;
    always_comb
        case (state_bus)
            0 : begin
                stall_mem = mem_access_good;
                mem_reg_wr = 0;
                wb_stb_o = mem_access_good;
                wb_cyc_o = mem_access_good;
            end
            1 : begin
                stall_mem = 1;
                mem_reg_wr = 0;
                wb_stb_o = 1;
                wb_cyc_o = 1;
            end
            default : begin
                stall_mem = 0;
                mem_reg_wr = ~mem_wr;
                wb_stb_o = 0;
                wb_cyc_o = 1;
            end
        endcase

    assign stall_o = stall_mem | stall_i | jmp;

endmodule
