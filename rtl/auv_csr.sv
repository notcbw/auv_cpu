`timescale 1ns/1ns

module auv_csr (
    input   logic           clk, rst_n, en, csr_rd,
    input   logic   [ 2:0]  funct3,
    input   logic   [11:0]  csr_adr,
    input   logic   [31:0]  rs1,
    input   logic   [ 3:0]  rd_i,
    input   logic   [ 4:0]  imm,
    output  logic           stall, reg_wr,
    output  logic   [31:0]  reg_dat_wr,
    output  logic           exc_illegal_inst,
    // CSR space bus
    output  logic   [11:0]  cbus_adr,
    output  logic   [31:0]  cbus_dat_wr,
    input   logic   [31:0]  cbus_dat_rd,
    output  logic           cbus_rd, cbus_wr,
    input   logic           cbus_ack
);

    logic csr_wr;
    logic [31:0] dat;
    assign dat = funct3[2] ? {27'h0, imm} : rs1;
    assign csr_wr = funct3[2] ? (imm == 0) : (rd_i == 0);
    assign cbus_adr = csr_adr;

    always_comb
        case (funct3[1:0])
            default : cbus_dat_wr = dat;
            'b10 : cbus_dat_wr = cbus_dat_rd | dat;
            'b11 : cbus_dat_wr = cbus_dat_rd | ~dat;
        endcase

    logic [1:0] state;
    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            state <= 0;
        end else begin
            case (state)
                0 : state <= en ? 1 : 0;
                1 : begin
                    if (csr_rd & ~cbus_ack)
                        state <= 3;
                    else
                        state <= 2;
                end
                2 : begin
                    if (csr_wr & ~cbus_ack)
                        state <= 3;
                    else
                        state <= 0;
                end
                default : state <= 0;
            endcase
        end

    always_comb
        case (state)
            0 : begin
                stall = en;
                cbus_rd = en & csr_rd;
                cbus_wr = 0;
                reg_wr = 0;
                exc_illegal_inst = 0;
            end
            1 : begin
                stall = 1;
                cbus_rd = 0;
                cbus_wr = csr_wr;
                reg_wr = csr_rd;
                exc_illegal_inst = 0;
            end
            2 : begin
                stall = csr_wr ? ~cbus_ack : 0;
                cbus_rd = 0;
                cbus_wr = 0;
                reg_wr = 0;
                exc_illegal_inst = 0;
            end
            default : begin
                stall = 0;
                cbus_rd = 0;
                cbus_wr = 0;
                reg_wr = 0;
                exc_illegal_inst = 1;
            end
        endcase

endmodule
