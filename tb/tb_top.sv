`timescale 1ns/1ps
`include "img_pkg.svh"

module tb_top;
    import img_pkg::*;

    localparam int IMG_WIDTH           = 640;
    localparam int IMG_HEIGHT          = 480;
    localparam int N_PIX               = IMG_WIDTH * IMG_HEIGHT;
    localparam int CLK_PERIOD          = 10;
    localparam int TIMEOUT_CYCLES      = 10_000_000;
    localparam int STALL_CYCLES        = 50_000;
    localparam int MAX_PRINT_ERR       = 10;
    localparam int IDLE_GAP_HARD_LIMIT = 100;

    // Per-cycle probability (in %) that the idle gap ends.
    // 100 = always back-to-back, 70 = mixed, 1..99 = fraction, 0 = never (bad).
    localparam int GAP_END_PCT = 70;

    localparam int SEED_SRC_INIT  = 32'hDEAD_BEEF;
    localparam int SEED_SINK_INIT = 32'hCAFE_BABE;

    int unsigned rng_src  = SEED_SRC_INIT;
    int unsigned rng_sink = SEED_SINK_INIT;

    function automatic int unsigned rng_step(inout int unsigned state);
        state = state ^ (state << 13);
        state = state ^ (state >> 17);
        state = state ^ (state << 5);
        rng_step = state;
    endfunction

    typedef struct {
        pixel_t data;
        bit     last;
    } mon_trans_t;

    logic   clk, rstn;
    logic   s_tvalid, s_tready;
    pixel_t s_tdata;
    logic   m_tvalid, m_tready, m_tlast;
    pixel_t m_tdata;

    inv_horiz_img #(.IMG_HEIGHT(IMG_HEIGHT), .IMG_WIDTH(IMG_WIDTH)) u_dut (
        .clk(clk), .rstn(rstn),
        .s_tvalid(s_tvalid), .s_tready(s_tready), .s_tdata(s_tdata),
        .m_tvalid(m_tvalid), .m_tready(m_tready), .m_tdata(m_tdata), .m_tlast(m_tlast)
    );

    mailbox #(pixel_t)     gen2drv_mbx = new(4);
    mailbox #(pixel_t)     mon_in_mbx  = new();
    mailbox #(mon_trans_t) mon_out_mbx = new();

    pixel_t img_in  [N_PIX];
    pixel_t img_out [N_PIX];

    int sent_cnt  = 0;
    int recv_cnt  = 0;
    int err_cnt   = 0;
    int tlast_cnt = 0;
    int tlast_idx = -1;

    int mon_out_idx = 0;
    int pred_col    = 0;
    int comp_idx    = 0;

    int cov_s_tvalid_low = 0;
    int cov_m_tready_low = 0;
    int cov_s_idle_min   = 32'h7FFF_FFFF;
    int cov_s_idle_max   = 0;
    int cov_gap_0        = 0;
    int cov_gap_n        = 0;
    int cov_forced_idle  = 0;

    int  test_last_recv = -1;
    int  test_stall_cnt = 0;
    bit  test_done      = 1'b0;
    bit  drain_req      = 1'b0;

    bit     file_loaded = 0;
    pixel_t expected_q[$];

    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // Read input image from file.
    initial begin : file_io
        string      in_file;
        int         fd_in;
        logic [7:0] bytes_in [N_PIX*3];
        int         n_read;

        if (!$value$plusargs("IN_FILE=%s", in_file)) in_file = "images/lemme_chex.raw";

        for (int i = 0; i < N_PIX; i++) begin
            img_in[i]  = '{R: 8'h00, G: 8'h00, B: 8'h00};
            img_out[i] = '{R: 8'h00, G: 8'h00, B: 8'h00};
        end

        fd_in = $fopen(in_file, "rb");
        if (fd_in == 0) $fatal(1, "Cannot open input file %s", in_file);
        n_read = $fread(bytes_in, fd_in);
        $fclose(fd_in);

        if (n_read < N_PIX*3)
            $display("WARN: input file shorter than expected (%0d < %0d), zero-filled",
                     n_read, N_PIX*3);

        for (int i = 0; i < N_PIX; i++)
            img_in[i] = '{R: bytes_in[i*3], G: bytes_in[i*3+1], B: bytes_in[i*3+2]};

        file_loaded = 1;
    end

    // Reset
    initial begin : reset
        wait (file_loaded);
        @(negedge clk);
        rstn = 0;
        repeat (10) @(negedge clk);
        rstn = 1;
    end

    initial begin : gen
        wait (rstn === 1'b1);
        for (int i = 0; i < N_PIX; i++)
            gen2drv_mbx.put(img_in[i]);
    end

    // After each handshake, draw a geometrically distributed idle gap.
    // gap=0 means tvalid stays high (back-to-back).
    initial begin : drv
        pixel_t p;
        int     gap;
        bit     have_p;
        s_tvalid = 1'b0;
        s_tdata  = '{R: 8'h00, G: 8'h00, B: 8'h00};
        wait (rstn === 1'b1);
        forever begin
            gap = 0;
            while ((rng_step(rng_src) % 100) >= GAP_END_PCT) begin
                gap++;
                if (gap >= IDLE_GAP_HARD_LIMIT)
                    $fatal(1, "Idle gap exceeded %0d cycles", IDLE_GAP_HARD_LIMIT);
            end
            if (gap > cov_s_idle_max) cov_s_idle_max = gap;
            if (gap < cov_s_idle_min) cov_s_idle_min = gap;

            if (gap == 0) begin
                have_p = gen2drv_mbx.try_get(p);
                if (!have_p) begin
                    if (s_tvalid === 1'b1) begin
                        s_tvalid <= 1'b0;
                        @(posedge clk);
                    end
                    cov_forced_idle++;
                    gen2drv_mbx.get(p);
                end else begin
                    cov_gap_0++;
                end
                s_tvalid <= 1'b1;
                s_tdata  <= p;
            end else begin
                s_tvalid <= 1'b0;
                repeat (gap) @(posedge clk);
                gen2drv_mbx.get(p);
                s_tvalid <= 1'b1;
                s_tdata  <= p;
                cov_gap_n++;
            end

            @(posedge clk);
            while (s_tready !== 1'b1) @(posedge clk);
            sent_cnt++;
        end
    end

    // Sink: random m_tready normally, forced 1 when drain_req is set.
    initial begin : sink
        wait (rstn === 1'b1);
        forever begin
            @(negedge clk);
            if (drain_req) m_tready <= 1'b1;
            else           m_tready <= rng_step(rng_sink) & 1'b1;
        end
    end

    // Sample at posedge to see the same preponed values as the DUT.
    initial begin : mon_in
        wait (rstn === 1'b1);
        forever begin
            @(posedge clk);
            if (s_tvalid === 1'b1 && s_tready === 1'b1)
                mon_in_mbx.put(s_tdata);
        end
    end

    initial begin : mon_out
        mon_trans_t t;
        wait (rstn === 1'b1);
        forever begin
            @(posedge clk);
            if (m_tvalid === 1'b1 && m_tready === 1'b1) begin
                t.data = m_tdata;
                t.last = m_tlast;
                if (mon_out_idx < N_PIX) img_out[mon_out_idx] = m_tdata;
                mon_out_idx++;
                mon_out_mbx.put(t);
            end
        end
    end

    // Expected output
    initial begin : predictor
        pixel_t row_buf [IMG_WIDTH];
        pixel_t p;
        wait (rstn === 1'b1);
        forever begin
            mon_in_mbx.get(p);
            row_buf[pred_col] = p;
            pred_col++;
            if (pred_col == IMG_WIDTH) begin
                for (int i = IMG_WIDTH-1; i >= 0; i--)
                    expected_q.push_back(row_buf[i]);
                pred_col = 0;
            end
        end
    end

    initial begin : comparator
        mon_trans_t act;
        pixel_t     exp;
        wait (rstn === 1'b1);
        forever begin
            mon_out_mbx.get(act);

            if (expected_q.size() == 0) begin
                $error("[COMP] Unexpected output #%0d: no expected value", comp_idx);
                err_cnt++;
                comp_idx++;
                continue;
            end
            exp = expected_q.pop_front();

            if (act.data.R !== exp.R || act.data.G !== exp.G || act.data.B !== exp.B) begin
                if (err_cnt < MAX_PRINT_ERR)
                    $error("[COMP] Pixel %0d mismatch: got %h/%h/%h exp %h/%h/%h",
                           comp_idx, act.data.R, act.data.G, act.data.B, exp.R, exp.G, exp.B);
                err_cnt++;
            end

            if (act.last) begin
                tlast_cnt++;
                tlast_idx = comp_idx;
            end

            comp_idx++;
            recv_cnt++;
        end
    end

    // Count cycles with idle input/output to prove the test really
    // exercised back-pressure on both sides.
    initial begin : coverage
        wait (rstn === 1'b1);
        forever begin
            @(posedge clk);
            if (s_tvalid === 1'b0) cov_s_tvalid_low++;
            if (m_tready === 1'b0) cov_m_tready_low++;
        end
    end

    initial begin : test
        string out_file;
        int    fd_out;
        int    final_errors;

        wait (rstn === 1'b1);

        while (!test_done) begin
            @(posedge clk);
            if (recv_cnt >= N_PIX) drain_req = 1'b1;

            if (sent_cnt >= N_PIX && recv_cnt >= N_PIX) begin
                test_done = 1'b1;
            end else if (sent_cnt >= N_PIX && recv_cnt == test_last_recv) begin
                test_stall_cnt++;
                if (test_stall_cnt > STALL_CYCLES) begin
                    $error("DUT stalled: sent=%0d, recv=%0d, expected %0d, expected_q=%0d",
                           sent_cnt, recv_cnt, N_PIX, expected_q.size());
                    test_done = 1'b1;
                end
            end else begin
                test_stall_cnt = 0;
                test_last_recv = recv_cnt;
            end
        end

        repeat (10) @(posedge clk);

        final_errors = err_cnt;

        if (recv_cnt != N_PIX) begin
            $error("Pixel count: got %0d, expected %0d", recv_cnt, N_PIX);
            final_errors++;
        end
        if (tlast_cnt != 1) begin
            $error("m_tlast asserted %0d times, expected 1", tlast_cnt);
            final_errors++;
        end
        if (tlast_idx != N_PIX - 1) begin
            $error("m_tlast at pixel %0d, expected %0d", tlast_idx, N_PIX - 1);
            final_errors++;
        end

        $display("INFO: SEED_SRC_INIT=%08h SEED_SINK_INIT=%08h",
                 SEED_SRC_INIT, SEED_SINK_INIT);
        $display("INFO: cov_s_tvalid_low=%0d cov_m_tready_low=%0d",
                 cov_s_tvalid_low, cov_m_tready_low);
        $display("INFO: cov_s_idle_min=%0d cov_s_idle_max=%0d cov_gap_0=%0d cov_gap_n=%0d",
                 cov_s_idle_min, cov_s_idle_max, cov_gap_0, cov_gap_n);
        $display("INFO: cov_forced_idle=%0d", cov_forced_idle);
        $display("INFO: mon_out_idx=%0d expected_q.size=%0d",
                 mon_out_idx, expected_q.size());

        if (!$value$plusargs("OUT_FILE=%s", out_file))
            out_file = "images/lemme_chex_inv.raw";
        fd_out = $fopen(out_file, "wb");
        if (fd_out == 0) begin
            $error("Cannot open output file %s", out_file);
            final_errors++;
        end else begin
            for (int i = 0; i < N_PIX; i++)
                $fwrite(fd_out, "%c%c%c", img_out[i].R, img_out[i].G, img_out[i].B);
            $fclose(fd_out);
        end

        if (final_errors == 0) $display("PASS: %0d pixels, tlast OK", N_PIX);
        else                   $error("FAIL: %0d errors", final_errors);

        $finish;
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "GLOBAL TIMEOUT: sent=%0d recv=%0d err=%0d",
               sent_cnt, recv_cnt, err_cnt);
    end

    initial begin : waves
        $dumpfile("build/wave.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
