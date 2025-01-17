// - implemented csr:
// 0x300 mstatus
// 0x301 misa (zero)
// 0x304 mie
// 0x305 mtvec
// 0x310 mstatush (zero)
// 0x320 mcountinhibit (zero)
// 0x341 mepc
// 0x342 mcause
// 0x343 mtval (zero)
// 0x344 mip

`timescale 1ns/1ns

module auv_trapc #(
    parameter integer ADDR_WIDTH = 24,
    parameter bit [ADDR_WIDTH-1:0] RST_VECTOR = 'h0,
    parameter bit [ADDR_WIDTH-1:0] NMI_VECTOR = 'h0
) (
    input   logic           clk, rst_n, nmi, stall_i,
    input   logic           int_ext, int_timer,
    output  logic           stall, flush,
    input   logic   [ADDR_WIDTH-3:0] pc_in_id, pc_in_ex,
    output  logic           jmp,
    output  logic   [ADDR_WIDTH-3:0] pc_wr,
    // exceptions
    input   logic           exc_illegal_inst, exc_illegal_inst_csr, exc_ecall, exc_ebreak,
    input   logic           exc_load_misalign, exc_store_misalign,
    input   logic           exc_load_fault, exc_store_fault,
    input   logic           ret, wfi,
    // csr bus
    input   logic           cbus_sel,
    input   logic   [ 6:0]  cbus_adr,
    input   logic   [31:0]  cbus_dat_wr,
    output  logic   [31:0]  cbus_dat_rd,
    input   logic           cbus_rd, cbus_wr,
    output  logic           cbus_ack
);

    logic mstatus_mie, mstatus_mpie;
    logic mstatus_mie_n, mstatus_mpie_n;
    logic mie_meie, mie_mtie;
    logic [ADDR_WIDTH-7:0] mtvec_base;
    logic [1:0] mtvec_mode;
    logic [ADDR_WIDTH-3:0] mepc, mepc_n;
    logic mcause_int, mcause_int_n;
    logic [3:0] mcause_exc, mcause_exc_n;

    // store the exception bits for 1 cycle
    logic exc_illegal_inst_l, exc_illegal_inst_csr_l, exc_ecall_l, exc_ebreak_l;
    logic exc_load_misalign_l, exc_store_misalign_l, exc_load_fault_l, exc_store_fault_l;
    always_ff @( posedge clk ) begin
        exc_illegal_inst_l <= exc_illegal_inst;
        exc_illegal_inst_csr_l <= exc_illegal_inst_csr;
        exc_ecall_l <= exc_ecall;
        exc_ebreak_l <= exc_ebreak;
        exc_load_misalign_l <= exc_load_misalign;
        exc_store_misalign_l <= exc_store_misalign;
        exc_load_fault_l <= exc_load_fault;
        exc_store_fault_l <= exc_store_fault;
    end

    logic irq, exc;
    assign irq = (int_ext | int_timer);
    assign exc = (exc_illegal_inst | exc_illegal_inst_csr | exc_ecall | exc_ebreak |
        exc_load_misalign | exc_store_misalign | exc_load_fault | exc_store_fault);

    // mepc_n mux
    logic sel_mepc_ex;
    assign mepc_n = sel_mepc_ex ? pc_in_ex : pc_in_id;

    // state machine
    typedef enum logic [2:0] {
        TCS_RST, TCS_NMI, TCS_IDLE,
        TCS_IRQ, TCS_EXC,
        TCS_RET, TCS_WFI
    } trapc_state_t;
    trapc_state_t state;
    logic nmi_delayed;

    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            state <= TCS_RST;
            nmi_delayed <= 0;
        end else begin
            case (state)
                TCS_RST, TCS_NMI, TCS_IRQ, TCS_EXC, TCS_RET :
                    state <= TCS_IDLE;
                TCS_IDLE : begin
                    state <= TCS_IDLE;
                    if (exc)
                        state <= TCS_EXC;
                    else if (~stall_i) begin
                        if (irq)
                            state <= TCS_IRQ;
                        else if (ret)
                            state <= TCS_RET;
                        else if (wfi)
                            state <= TCS_WFI;
                    end
                end
                TCS_WFI : state <= irq ? TCS_IRQ : TCS_WFI;
                default : state <= TCS_RST;
            endcase

            // nmi edge detect
            if (nmi & ~nmi_delayed)
                state <= TCS_NMI;
            nmi_delayed <= nmi;
        end

    always_comb begin
        mstatus_mie_n = mstatus_mie;
        mstatus_mpie_n = mstatus_mpie;
        mcause_exc_n = mcause_exc;
        mcause_int_n = mcause_int;
        sel_mepc_ex = 0;
        jmp = 0;
        pc_wr = 0;
        case (state)
            TCS_RST : begin
                stall = 1;
                flush = 1;
                mstatus_mie_n = 0;
                mstatus_mpie_n = 0;
                mcause_exc_n = 0;
                mcause_int_n = 0;
                pc_wr = RST_VECTOR[ADDR_WIDTH-1:2];
                jmp = 1;
            end
            TCS_NMI : begin
                stall = 1;
                flush = 1;
                sel_mepc_ex = 0;
                mcause_exc_n = 0;
                mcause_int_n = 1;
                pc_wr = NMI_VECTOR[ADDR_WIDTH-1:2];
                jmp = 1;
            end
            TCS_IDLE : begin
                stall = exc;
                flush = exc;
            end
            TCS_IRQ : begin
                stall = 1;
                flush = 1;
                mstatus_mpie_n = mstatus_mie;
                mstatus_mie_n = 0;
                mcause_int_n = 1;
                if (int_timer)
                    mcause_exc_n = 7;
                else
                    mcause_exc_n = 11;
                sel_mepc_ex = 0;
                pc_wr = {mtvec_base, ((mtvec_mode == 1) ? mcause_exc_n : 4'h0)};
                jmp = 1;
            end
            TCS_EXC : begin
                stall = 1;
                flush = 1;
                mstatus_mpie_n = mstatus_mie;
                mstatus_mie_n = 0;
                mcause_int_n = 0;
                sel_mepc_ex = 0;
                pc_wr = {mtvec_base, 4'b0};
                jmp = 1;

                if (exc_illegal_inst_l) begin
                    mcause_exc_n = 2;
                    sel_mepc_ex = 0;
                end else if (exc_illegal_inst_csr_l) begin
                    mcause_exc_n = 2;
                    sel_mepc_ex = 1;
                end else if (exc_ecall_l) begin
                    mcause_exc_n = 11;
                    sel_mepc_ex = 0;
                end else if (exc_ebreak_l) begin
                    mcause_exc_n = 3;
                    sel_mepc_ex = 0;
                end else if (exc_load_fault_l) begin
                    mcause_exc_n = 5;
                    sel_mepc_ex = 1;
                end else if (exc_store_fault_l) begin
                    mcause_exc_n = 7;
                    sel_mepc_ex = 1;
                end else if (exc_load_misalign_l) begin
                    mcause_exc_n = 4;
                    sel_mepc_ex = 1;
                end else if (exc_store_misalign_l) begin
                    mcause_exc_n = 6;
                    sel_mepc_ex = 1;
                end
            end
            TCS_RET : begin
                stall = 1;
                flush = 1;
                mstatus_mie_n = mstatus_mpie;
                mstatus_mpie_n = 1;
                pc_wr = mepc;
                jmp = 1;
            end
            TCS_WFI : begin
                stall = 1;
                flush = 0;
            end
            default : begin
                stall = 1;
                flush = 1;
            end
        endcase
    end

    // csr control
    always_ff @( posedge clk or negedge rst_n )
        if (~rst_n) begin
            cbus_ack <= 0;
        end else begin
            mstatus_mie <= mstatus_mie_n;
            mstatus_mpie <= mstatus_mpie_n;
            mepc <= mepc_n;
            mcause_int <= mcause_int_n;
            mcause_exc <= mcause_exc_n;
            // process csr access
            cbus_ack <= 0;
            if (cbus_sel) begin
                if (cbus_rd) begin
                    cbus_ack <= 1;
                    case (cbus_adr)
                        7'h01, 7'h10, 7'h20, 7'h43 : cbus_dat_rd <= 0;
                        7'h00 : cbus_dat_rd <= {24'h0, mstatus_mpie, 3'h0, mstatus_mie, 3'h0};
                        7'h04 : cbus_dat_rd <= {20'h0, mie_meie, 3'h0, mie_mtie, 7'h0};
                        7'h05 : cbus_dat_rd <= {{(32-ADDR_WIDTH){1'b0}}, mtvec_base, 4'h0, mtvec_mode};
                        7'h41 : cbus_dat_rd <= {{(32-ADDR_WIDTH){1'b0}}, mepc, 2'b0};
                        7'h42 : cbus_dat_rd <= {mcause_int, 27'h0, mcause_exc};
                        7'h44 : cbus_dat_rd <= {20'h0, int_ext, 3'h0, int_timer, 7'h0};
                        default : cbus_ack <= 0;
                    endcase
                end else if (cbus_wr) begin
                    cbus_ack <= 1;
                    case (cbus_adr)
                        7'h00 : begin
                            mstatus_mie <= cbus_dat_wr[3];
                            mstatus_mpie <= cbus_dat_wr[7];
                        end
                        7'h04 : begin
                            mie_meie <= cbus_dat_wr[11];
                            mie_mtie <= cbus_dat_wr[7];
                        end
                        7'h05 : begin
                            mtvec_base <= cbus_dat_wr[ADDR_WIDTH-1:6];
                            mtvec_mode <= cbus_dat_wr[1:0];
                        end
                        7'h41 : mepc <= cbus_dat_wr[ADDR_WIDTH-1:2];
                        7'h42 : begin
                            mcause_int <= cbus_dat_wr[31];
                            mcause_exc <= cbus_dat_wr[3:0];
                        end
                        default : cbus_ack <= 0;
                    endcase
                end
            end
        end

endmodule
