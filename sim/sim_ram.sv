`timescale 1ns/1ns

module sim_ram #(
    parameter integer SIZE = 'h100,
    localparam integer Width = $clog2(SIZE)
) (
    input   logic           clk, dump,
    input   logic   [23:0]  wb_adr_i,
    input   logic   [15:0]  wb_dat_i,
    output  logic   [15:0]  wb_dat_o,
    input   logic   [ 1:0]  wb_sel_i,
    input   logic           wb_we_i, wb_stb_i, wb_cyc_i,
    output  logic           wb_ack_o
);

    reg [7:0] mem [SIZE];

    always @( posedge dump ) begin
        int fd;
        $display("dumping ram to dump.mem");
        fd = $fopen("./dump.mem", "w");

        if (fd == 0) begin
            $display("Failed to create dump.mem!");
        end else begin
            int i;
            for (i = 0; i < SIZE; i = i + 1) begin
                $fwrite(fd, "%02X\n", mem[i]);
            end
            $fclose(fd);
            $display("Complete!");
        end
    end

    always_ff @( posedge clk )
        if (wb_cyc_i & wb_stb_i) begin
            wb_ack_o <= 1;
            if (wb_we_i) begin
                if (wb_sel_i[0])
                    mem[{wb_adr_i[Width-1:1], 1'b0}] <= wb_dat_i[7:0];
                if (wb_sel_i[1])
                    mem[{wb_adr_i[Width-1:1], 1'b1}] <= wb_dat_i[15:8];
            end else begin
                wb_dat_o[7:0] <= mem[{wb_adr_i[Width-1:1], 1'b0}];
                wb_dat_o[15:8] <= mem[{wb_adr_i[Width-1:1], 1'b1}];
            end
        end else begin
            wb_ack_o <= 0;
        end

endmodule
