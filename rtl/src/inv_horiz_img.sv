`include "img_pkg.svh"

module inv_horiz_img 
    import img_pkg::*;
#(
    parameter IMG_HEIGHT = 480,
    parameter IMG_WIDTH = 640
)(
    input  logic        clk,
    input  logic        rstn,

    // ==========================================
    // Input interface (Slave)
    // ==========================================
    input  logic         s_tvalid,
    output logic         s_tready,
    input  pixel_t       s_tdata,
   // input  logic         s_tlast,

    // ==========================================
    // Output interface (Master)
    // ==========================================
    output logic         m_tvalid,
    input  logic         m_tready,
    output pixel_t       m_tdata,
    output logic         m_tlast
);

    typedef enum logic [1:0] {HEAD_FWD, HEAD_BACK, HEAD_STAY} direct_t;
    pixel_t line_buf [IMG_WIDTH-1:0];
    logic [$clog2(IMG_WIDTH)-1:0] line_head;
    logic [$clog2(IMG_HEIGHT+1)-1:0] rows_cnt;
    direct_t head_direct;
    logic s_thandshake;
    logic m_thandshake;
    logic out_line_ready;
    logic last_row_out;
    logic proceed_processing;
    logic do_output_pixel;
    logic flush;

    // Skid register — holds one beat when downstream stalls
    logic   skid_valid;
    pixel_t skid_data;

    logic  m_stall;

    // Upstream handshake and downstream stall
    assign m_stall = m_tvalid & ~m_tready & out_line_ready;

    assign last_row_out = (rows_cnt == IMG_HEIGHT-1); 
    assign proceed_processing = (~m_tvalid | m_tready)     &&
                                (skid_valid | 
                                 s_tvalid   | 
                                 (last_row_out & m_tready)
                                );

    assign do_output_pixel = proceed_processing && out_line_ready;

    assign flush = m_thandshake & m_tlast;

    assign s_thandshake = s_tvalid && s_tready;
    assign m_thandshake = m_tvalid && m_tready;


    // -----------------------------------------------------------------
    // Skid valid — asserts when upstream delivers a beat but downstream
    // is stalled.  Clears when downstream accepts.
    // -----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn)
            skid_valid <= 1'b0;
        else if (s_thandshake & m_stall)
            skid_valid <= 1'b1;
        else if (m_tready)
            skid_valid <= 1'b0;
    end

    // -----------------------------------------------------------------
    // Skid data — capture input payload on upstream handshake
    // -----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (s_thandshake)
            skid_data <= s_tdata;
    end

    // Ready to upstream when skid register is empty
    // ~out_line_ready added because if IMG_HEIGHT == 1, 
    // row 0 is last already and nothing will be written in pixel line
    assign s_tready = ~skid_valid && (!last_row_out | ~out_line_ready);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            rows_cnt <= '0;
        end else begin
            if (flush) begin
                rows_cnt <= '0;
            end else if (head_direct == HEAD_STAY && do_output_pixel) begin
                if (rows_cnt < IMG_HEIGHT-1)
                    rows_cnt <= rows_cnt + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            line_head <= '0;
        end else begin
            if (flush) begin
                line_head <= '0;
            end else if (proceed_processing) begin 
                if (head_direct == HEAD_FWD)
                    line_head <= line_head + 1;
                else if (head_direct == HEAD_BACK)
                    line_head <= line_head - 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            head_direct <= HEAD_FWD;
        end else begin
            if (flush) begin
                head_direct <= HEAD_FWD;
            end else if (proceed_processing) begin
                if (line_head == IMG_WIDTH-2 && head_direct == HEAD_FWD || //the second-to-last one moves forward
                    line_head == 1 && head_direct == HEAD_BACK // OR the first one goes backward
                ) begin
                    head_direct <= HEAD_STAY;
                end else if (line_head == IMG_WIDTH-1) begin
                    head_direct <= HEAD_BACK;
                end else if (~|line_head) begin // line_head == 0
                    head_direct <= HEAD_FWD;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            out_line_ready <= 1'b0;
        end else begin
            if (flush) begin
                out_line_ready <= 1'b0;
            end else if (proceed_processing) begin
                if (line_head == IMG_WIDTH-1) begin
                    out_line_ready <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn)
            m_tvalid <= 1'b0;
        else if (flush)
            m_tvalid <= 1'b0;
        else if (~m_tvalid | m_tready)
            m_tvalid <= (s_tvalid | skid_valid | last_row_out) && out_line_ready;
    end

    always_ff @(posedge clk) begin
        if (~m_tvalid | m_tready) begin
            if (skid_valid)
                line_buf[line_head] <= skid_data;
            else if (s_tvalid)
                line_buf[line_head] <= s_tdata;
        end
    end

    always_ff @(posedge clk) begin
        if (do_output_pixel) begin
            m_tdata <= line_buf[line_head];
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_tlast <= 1'b0;
        end else begin
            if (flush)
                m_tlast <= 1'b0;
            else if (m_thandshake)
                m_tlast <= (rows_cnt == IMG_HEIGHT-1) && head_direct == HEAD_STAY;
        end
    end

endmodule
