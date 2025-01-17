`timescale 1ns/1ns

module auv_regfile (
    input   logic           clk, we, stall,
    input   logic   [ 3:0]  ra0, ra1, wa,
    input   logic   [31:0]  wd,
    output  logic   [31:0]  rd0, rd1
);

    reg [31:0] ram [15];

    always_ff @( posedge clk )
        if (we)
            ram[wa] <= wd;

    always_ff @( posedge clk )
        if (stall)
            rd0 <= rd0;
        else if (ra0 == 0)
            rd0 <= 0;
        else if (ra0 == wa)
            rd0 <= wd;
        else
            rd0 <= ram[ra0];

     always_ff @( posedge clk )
        if (stall)
            rd1 <= rd1;
        else if (ra1 == 0)
            rd1 <= 0;
        else if (ra1 == wa)
            rd1 <= wd;
        else
            rd1 <= ram[ra1];

endmodule
