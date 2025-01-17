`timescale 1ns/1ns

`include "auv_pkg.sv"

import auv_pkg::*;

module auv_decode #(
    parameter integer ADDR_WIDTH = 24
) (
    input   logic           clk, rst_n, flush, stall_i,
    input   logic   [31:0]  inst,
    input   logic   [ADDR_WIDTH-3:0] pc_in,
    output  logic   [ADDR_WIDTH-3:0] pc_out,
    output  logic           pop,
    output  logic   [31:0]  imm,
    output  logic   [ 3:0]  rs1, rs2, rd,
    output  logic   [ 2:0]  funct3,
    output  logic   [ 4:0]  csr_imm,
    output  logic           alu_en, mem_access, pc_wr, branch,
    output  logic           mem_wr, reg_wr, link,
    output  sel_op1_t       sel_op1,
    output  sel_op2_t       sel_op2,
    output  logic           csr_en, csr_rd,
    // exceptions
    output  logic           exc_illegal_inst, exc_ecall, exc_ebreak,
    output  logic           ret, wfi,
    // funct7 decoded signal
    output  logic           alu_alt, zba_shadd,
    output  logic           zbs_bclrbext, zbs_binv, zbs_bset
);

    logic [31:0] imm_i;
    logic [3:0] rd_i;
    logic [2:0] funct3_i;

    // immediate decode
    always_comb begin : dec_imm_i
        casez (inst[6:2])
            'b0?101 : imm_i = {inst[31:12], 12'h0};
            'b11011 : imm_i = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            'b11001, 'b00?00, 'b11100 : imm_i = {{20{inst[31]}}, inst[31:20]};
            'b11000 : imm_i = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            'b01000 : imm_i = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            'b01100 : imm_i = {{20{inst[31]}}, inst[31:25], 5'h0};
            default : imm_i = 0;
        endcase
    end

    // reg address decode
    assign rd_i = flush ? 0 : inst[10:7];

    always_comb
        case (inst[6:2])
            'b01101 : rs1 = 0; // lui
            'b00101 : rs1 = 0; // auipc
            'b11011 : rs1 = 0; // jal
            default : rs1 = inst[18:15];
        endcase

    always_comb
        case (inst[6:2])
            'b01101 : rs2 = 0; // lui
            'b00101 : rs2 = 0; // auipc
            'b11011 : rs2 = 0; // jal
            'b11000, 'b01000, 'b01100 : rs2 = inst[23:20];
            default : rs2 = 0;
        endcase

    assign funct3_i = flush ? 0 : inst[14:12];
    assign pop = ~stall_i;

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n | flush) begin
            csr_imm <= 0;
            rd <= 0;
            funct3 <= 0;
        end else if (~stall_i) begin
            csr_imm <= inst[19:15];
            imm <= imm_i;
            rd <= rd_i;
            funct3 <= funct3_i;
            pc_out <= pc_in;
        end

    // funct7 decode
    logic alu_alt_i;
    logic zbs_bclrbext_i, zbs_binv_i, zbs_bset_i;
    logic zba_shadd_i;
    logic funct7_unimpl;
    always_comb begin
        alu_alt_i = 0;
        zbs_bclrbext_i = 0;
        zbs_binv_i = 0;
        zbs_bset_i = 0;
        zba_shadd_i = 0;
        funct7_unimpl = 0;
        case (inst[31:25])
            'b0000000 : begin end
            'b0100000 : alu_alt_i = 1;
            'b0010000 : zba_shadd_i = (alu_en_i & (sel_op2_i == OP2_RS2));
            'b0100100 : zbs_bclrbext_i = 1;
            'b0110110 : zbs_binv_i = 1;
            'b0010100 : zbs_bset_i = 1;
            default : funct7_unimpl = 1;
        endcase
    end

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n | flush) begin
            alu_alt <= 0;
            zba_shadd <= 0;
            zbs_bclrbext <= 0;
            zbs_binv <= 0;
            zbs_bset <= 0;
        end else if (~stall_i) begin
            alu_alt <= alu_alt_i;
            zba_shadd <= zba_shadd_i;
            zbs_bclrbext <= zbs_bclrbext_i;
            zbs_binv <= zbs_binv_i;
            zbs_bset <= zbs_bset_i;
        end

    // opcode decode
    logic alu_en_i, mem_access_i, pc_wr_i, branch_i;
    logic mem_wr_i, reg_wr_i, link_i, csr_en_i;
    sel_op1_t sel_op1_i;
    sel_op2_t sel_op2_i;

    always_comb begin
        exc_illegal_inst = 0;
        exc_ecall = 0;
        exc_ebreak = 0;
        ret = 0;
        wfi = 0;
        alu_en_i = 0;
        mem_access_i = 0;
        pc_wr_i = 0;
        branch_i = 0;
        mem_wr_i = 0;
        reg_wr_i = 0;
        link_i = 0;
        csr_en_i = 0;
        sel_op1_i = OP1_RS1;
        sel_op2_i = OP2_RS2;
        if (inst[1:0] != 2'b11) begin
            exc_illegal_inst = 1;
        end else begin
            case (inst[6:2])
                'b00000 : begin // load
                    mem_access_i = 1;
                    sel_op2_i = OP2_IMM;
                end
                'b00100 : begin // op_imm
                    exc_illegal_inst = 0;
                    alu_en_i = 1;
                    reg_wr_i = 1;
                    sel_op2_i = OP2_IMM;
                end
                'b00101 : begin // auipc
                    reg_wr_i = 1;
                    sel_op1_i = OP1_PC;
                    sel_op2_i = OP2_IMM;
                end
                'b01000 : begin // store
                    mem_access_i = 1;
                    mem_wr_i = 1;
                    sel_op2_i = OP2_IMM;
                end
                'b01100 : begin // op
                    exc_illegal_inst = funct7_unimpl;
                    alu_en_i = 1;
                    reg_wr_i = 1;
                end
                'b01101 : begin // lui
                    reg_wr_i = 1;
                    sel_op2_i = OP2_IMM;
                end
                'b11000 : begin // branch
                    pc_wr_i = 1;
                    branch_i = 1;
                    sel_op1_i = OP1_PC;
                    sel_op2_i = OP2_IMM;
                end
                'b11001 : begin // jalr
                    pc_wr_i = 1;
                    reg_wr_i = 1;
                    link_i = 1;
                    sel_op2_i = OP2_IMM;
                end
                'b11011 : begin // jal
                    pc_wr_i = 1;
                    reg_wr_i = 1;
                    link_i = 1;
                    sel_op1_i = OP1_PC;
                    sel_op2_i = OP2_IMM;
                end
                'b11100 : begin // system
                    case (inst[14:12])
                        'b000 : begin
                            casez (inst[31:20])
                                'b0000000_00000 : exc_ecall = 1;
                                'b0000000_00001 : exc_ebreak = 1;
                                'b0011000_00010 : ret = 1;
                                'b0001000_00101 : wfi = 1;
                                default : exc_illegal_inst = 1;
                            endcase
                        end
                        'b100 : exc_illegal_inst = 1;
                        default : csr_en_i = 1;
                    endcase
                end
                default : begin // unimplemented
                    exc_illegal_inst = 1;
                end
            endcase
        end
    end

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n | flush) begin
            alu_en <= 0;
            mem_access <= 0;
            pc_wr <= 0;
            branch <= 0;
            mem_wr <= 0;
            reg_wr <= 0;
            link <= 0;
            csr_en <= 0;
            csr_rd <= 0;
            sel_op1 <= OP1_RS1;
            sel_op2 <= OP2_RS2;
        end else if (~stall_i) begin
            alu_en <= alu_en_i;
            mem_access <= mem_access_i;
            pc_wr <= pc_wr_i;
            branch <= branch_i;
            mem_wr <= mem_wr_i;
            reg_wr <= reg_wr_i;
            link <= link_i;
            csr_en <= csr_en_i;
            csr_rd <= (inst[10:7] != 0);
            sel_op1 <= sel_op1_i;
            sel_op2 <= sel_op2_i;
        end

endmodule
