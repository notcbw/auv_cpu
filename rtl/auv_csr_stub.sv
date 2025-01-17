// stub to implement machine information regs
module auv_csr_stub (
    input   logic           clk, rst_n,
    // csr bus
    input   logic           cbus_sel,
    output  logic   [31:0]  cbus_dat_rd,
    input   logic           cbus_rd, cbus_wr,
    output  logic           cbus_ack
);

    assign cbus_dat_rd = 0;

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            cbus_ack <= 0;
        end else begin
            if (cbus_ack)
                cbus_ack <= 0;
            if (cbus_sel)
                cbus_ack <= (cbus_rd | cbus_wr);
        end

endmodule
