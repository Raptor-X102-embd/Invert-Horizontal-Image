`timescale 1ns/1ps
`include "img_pkg.svh"

// vibe-coded testbench =)
module tb_top();

    import img_pkg::*;

    localparam int IMG_WIDTH   = 640;
    localparam int IMG_HEIGHT  = 480;
    localparam int N_PIX       = IMG_WIDTH * IMG_HEIGHT;

    localparam pixel_t PIXEL_ZERO = '{R: 8'h00, G: 8'h00, B: 8'h00};

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

    initial begin clk = 0; forever #5 clk = ~clk; end

    int seed_src  = 32'hDEAD_BEEF;
    int seed_sink = 32'hCAFE_BABE;

    // ============================================================
    // File I/O
    // ============================================================
    string      in_file, out_file;
    int         fd_in, fd_out;
    logic [7:0] r_byte, g_byte, b_byte;

    pixel_t img_in  [N_PIX];
    pixel_t img_out [N_PIX];
    int     out_cnt;
    bit     file_loaded = 0;

    initial begin
        if (!$value$plusargs("IN_FILE=%s",  in_file))  in_file  = "images/lemme_chex.raw";
        if (!$value$plusargs("OUT_FILE=%s", out_file)) out_file = "images/lemme_chex_inv.raw";

        fd_in = $fopen(in_file, "rb");
        if (fd_in == 0) begin $display("ERROR: cannot open %s", in_file); $finish; end
        fd_out = $fopen(out_file, "wb");
        if (fd_out == 0) begin $display("ERROR: cannot open %s", out_file); $finish; end

        for (int i = 0; i < N_PIX; i++) begin
            if ($fread(r_byte, fd_in) == 0 ||
                $fread(g_byte, fd_in) == 0 ||
                $fread(b_byte, fd_in) == 0) begin
                $display("WARN: input file too short at pixel %0d, zero-fill", i);
                img_in[i] = PIXEL_ZERO;
                break;
            end
            img_in[i] = '{R: r_byte, G: g_byte, B: b_byte};
            img_out[i] = PIXEL_ZERO;
        end
        $fclose(fd_in);
        file_loaded = 1;
    end

    // ============================================================
    // Source: случайный s_tvalid, s_tdata держится, пока не принят
    // (при s_tvalid=0 пиксель не теряется — он «ждёт» следующего s_tvalid=1)
    // ============================================================
    int in_idx;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s_tvalid <= 1'b0;
            s_tdata  <= img_in[0];
            in_idx   <= 0;
        end else begin
            if (s_tvalid && s_tready && in_idx < N_PIX) begin
                if (in_idx + 1 < N_PIX) s_tdata <= img_in[in_idx + 1];
                in_idx <= in_idx + 1;
            end

            if (in_idx >= N_PIX)
                s_tvalid <= 1'b0;                       // все пиксели отправлены
            else
                s_tvalid <= $urandom(seed_src) & 1'b1;  // свободный рандом
        end
    end

    // ============================================================
    // Sink: случайный m_tready
    // ============================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) m_tready <= 1'b1;
        else       m_tready <= $urandom(seed_sink) & 1'b1;
    end

    // ============================================================
    // Захват
    // ============================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) out_cnt <= 0;
        else if (m_tvalid && m_tready) begin
            if (out_cnt < N_PIX) begin
                img_out[out_cnt] <= m_tdata;
                $fwrite(fd_out, "%c", m_tdata.R);
                $fwrite(fd_out, "%c", m_tdata.G);
                $fwrite(fd_out, "%c", m_tdata.B);
            end
            out_cnt <= out_cnt + 1;
        end
    end

    int tlast_cnt, tlast_idx;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tlast_cnt <= 0; tlast_idx <= -1;
        end else if (m_tvalid && m_tready && m_tlast) begin
            tlast_cnt <= tlast_cnt + 1;
            tlast_idx <= out_cnt;
        end
    end

    // ============================================================
    // Reset после загрузки файла
    // ============================================================
    initial begin
        wait (file_loaded);
        #1;
        rstn = 0;
        repeat (10) @(posedge clk);
        #1 rstn = 1;
    end

    // ============================================================
    // Проверка
    // ============================================================
    initial begin : chk
        int errors = 0;
        int last, quiet_cnt;

        wait (file_loaded);
        wait (rstn == 1'b1);

        // Phase 1: ждём первый выходной пиксель (или таймаут)
        fork
            begin wait (out_cnt > 0); end
            begin #(5_000_000);       end       // 5 ms guard
        join_any
        disable fork;

        // Phase 2: ждём, пока out_cnt перестанет меняться
        // (5000 тактов без изменений = 50 us — при рандоме такого зазора не бывает)
        last = -1; quiet_cnt = 0;
        while (quiet_cnt < 5000) begin
            @(posedge clk);
            if (out_cnt == last) quiet_cnt++;
            else begin quiet_cnt = 0; last = out_cnt; end
        end

        // Phase 3: проверки
        $display("INFO: out_cnt=%0d, N_PIX=%0d", out_cnt, N_PIX);
        if (out_cnt != N_PIX) begin
            $display("FAIL: pixel count (%0d vs %0d)", out_cnt, N_PIX);
            errors++;
        end

        $display("INFO: tlast_cnt=%0d, tlast_idx=%0d", tlast_cnt, tlast_idx);
        if (tlast_cnt != 1 || tlast_idx != N_PIX-1) begin
            $display("FAIL: m_tlast cnt=%0d idx=%0d (expected 1, %0d)",
                     tlast_cnt, tlast_idx, N_PIX-1);
            errors++;
        end

        for (int y = 0; y < IMG_HEIGHT && errors < 20; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                pixel_t exp = img_in[y*IMG_WIDTH + (IMG_WIDTH-1-x)];
                pixel_t got = img_out[y*IMG_WIDTH + x];
                if (got.R !== exp.R || got.G !== exp.G || got.B !== exp.B) begin
                    if (errors < 10)
                        $display("MISMATCH [%0d][%0d] got %h/%h/%h exp %h/%h/%h",
                                 y, x, got.R, got.G, got.B, exp.R, exp.G, exp.B);
                    errors++;
                end
            end
        end

        if (errors == 0) $display("PASS: %0d pixels OK, m_tlast OK", N_PIX);
        else             $display("FAIL: %0d errors", errors);

        $fclose(fd_out);
        $finish;
    end

    initial begin
        #(200_000_000);
        $display("TIMEOUT: out_cnt=%0d", out_cnt);
        if (fd_out != 0) $fclose(fd_out);
        $finish;
    end

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
