`timescale 1ns/1ns

module auv_sim;

    localparam integer AddrWidth = 24;
    localparam string RomFName = "test_rom/test.mem";
    localparam integer RomSize = 'h400;
    localparam integer RamSize = 'h200;
    localparam integer RomSizeWords = RomSize / 4;
    localparam integer RomWidth = $clog2(RomSizeWords);
    localparam integer RamWidth = $clog2(RamSize);

    logic clk, rst_n, ram_dump;
    logic [RomWidth-1:0] rom_adr;
    logic [31:0] rom_dat;
    logic [AddrWidth-1:0] wb_adr;
    logic [15:0] wb_dat_wr, wb_dat_rd, wb_dat_rom, wb_dat_ram;
    logic wb_ack, wb_ack_rom, wb_ack_ram;
    logic [1:0] wb_sel;
    logic wb_we, wb_stb, wb_err;
    logic wb_cyc, wb_cyc_rom, wb_cyc_ram;

    logic grant_rom, grant_ram, bus_err;
    logic grant_rom_2, grant_ram_2;

    logic int_timer;

    always_comb begin
        grant_ram = 0;
        grant_rom = 0;
        bus_err = 0;
        if (wb_adr[23:10] == 'b0000_0000_0000_00)
            grant_rom = 1;
        else if (wb_adr[23:9] == 'b0000_0001_0000_000)
            grant_ram = 1;
        else
            bus_err = 1;
    end

    assign wb_cyc_rom = wb_cyc & grant_rom;
    assign wb_cyc_ram = wb_cyc & grant_ram;
    assign wb_dat_rd = grant_ram_2 ? wb_dat_ram : wb_dat_rom;
    assign wb_ack = grant_ram_2 ? wb_ack_ram : wb_ack_rom;

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            wb_err <= 0;
            grant_rom_2 <= 0;
            grant_ram_2 <= 0;
        end else begin
            wb_err <= bus_err & wb_cyc;
            grant_rom_2 <= grant_rom;
            grant_ram_2 <= grant_ram;
        end

    sim_ram #(
        .SIZE(RamSize)
    ) ram (
        .clk(clk),
        .dump(ram_dump),
        .wb_adr_i(wb_adr),
        .wb_dat_i(wb_dat_wr),
        .wb_dat_o(wb_dat_ram),
        .wb_sel_i(wb_sel),
        .wb_we_i(wb_we),
        .wb_stb_i(wb_stb),
        .wb_cyc_i(wb_cyc_ram),
        .wb_ack_o(wb_ack_ram)
    );

    auv_top #(
        .ADDR_WIDTH(AddrWidth),
        .ROM_FNAME(RomFName),
        .ROM_SIZE(RomSize),
        .RST_VECTOR(0),
        .NMI_VECTOR(0),
        .INT_COUNT(4)
    ) cpu (
        .clk(clk),
        .rst_n(rst_n),
        .nmi(0),
        .int_timer(int_timer),
        .irq_input(0),
        .wb_adr_o(wb_adr),
        .wb_dat_i(wb_dat_rd),
        .wb_dat_o(wb_dat_wr),
        .wb_sel_o(wb_sel),
        .wb_we_o(wb_we),
        .wb_stb_o(wb_stb),
        .wb_cyc_o(wb_cyc),
        .wb_ack_i(wb_ack),
        .wb_stall_i(0),
        .wb_err_i(wb_err),
        .rom_wb_adr_i(wb_adr[9:0]),
        .rom_wb_dat_o(wb_dat_rom),
        .rom_wb_stb_i(wb_stb),
        .rom_wb_cyc_i(wb_cyc_rom),
        .rom_wb_ack_o(wb_ack_rom)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        // reset
        int_timer = 0;
        ram_dump = 0;
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        // run for 1000 cycles
        repeat (1000) @(posedge clk);
        // dump ram then stop
        ram_dump = 1;
        @(posedge clk);
        $stop;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0);
    end

endmodule
