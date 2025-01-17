// A simple custom interrupt controller
// - implemented custom csr
// 0xfc0 intce - Interrupt Enable
// 0xfc1 intcp - Interrupt Pending
// 0xfc2 intct - Interrupt Taken

`timescale 1ns/1ns

module auv_intc #(
    parameter integer INT_COUNT = 16,
    localparam integer NumWidth = $clog2(INT_COUNT)
) (
    input   logic           clk, rst_n,
    input   logic   [INT_COUNT-1:0] irq_input,
    output  logic           int_ext,
    // csr bus
    input   logic           cbus_sel,
    input   logic   [ 1:0]  cbus_adr,
    input   logic   [31:0]  cbus_dat_wr,
    output  logic   [31:0]  cbus_dat_rd,
    input   logic           cbus_rd, cbus_wr,
    output  logic           cbus_ack
);

    logic [INT_COUNT-1:0] intce, irq, irq_n;
    logic [NumWidth-1:0] intct, intct_n;

    assign irq_n = irq_input & intce;
    assign int_ext = |irq;
    always_comb begin
        intct_n = 0;
        for (int i = INT_COUNT-1; i >= 0; i = i - 1) begin
            if (irq[i]) begin
                intct_n = i[NumWidth-1:0];
                break;
            end
        end
    end

    always_ff @( posedge clk ) begin
        irq <= irq_n;
        intct <= intct_n;
    end

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            intce <= 0;
            cbus_ack <= 0;
        end else begin
            cbus_ack <= 0;
            if (cbus_sel) begin
                if (cbus_rd) begin
                    cbus_ack <= 1;
                    case (cbus_adr)
                        0 : cbus_dat_rd <= {{(32-INT_COUNT){1'b0}}, intce};
                        1 : cbus_dat_rd <= {{(32-INT_COUNT){1'b0}}, irq_input};
                        2 : cbus_dat_rd <= int_ext ? {{(32-NumWidth){1'b0}}, intct} : 32'hffffffff;
                        default : cbus_ack <= 0;
                    endcase
                end else if (cbus_wr) begin
                    cbus_ack <= 1;
                    case (cbus_adr)
                        0 : intce <= cbus_dat_wr[INT_COUNT-1:0];
                        default : cbus_ack <= 0;
                    endcase
                end
            end
        end

endmodule
