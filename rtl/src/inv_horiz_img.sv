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
    //input  logic         s_tlast,

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
    logic out_line_ready;
    logic last_row_out;
    logic flush;

    assign s_thandshake = s_tvalid && s_tready;
    assign s_tready = m_tready && !flush;
    assign last_row_out = (rows_cnt == IMG_HEIGHT); 

    always_ff @(posedge clk) begin
        if (!rstn) begin
            flush <= 1'b0;
        end else begin
            flush <= last_row_out && m_tready && m_tvalid && (head_direct == HEAD_STAY);
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            rows_cnt <= '0;
            m_tlast <= 1'b0;
        end else begin
            m_tlast <= 1'b0;
            if (head_direct == HEAD_STAY) begin
                if (s_thandshake) begin
                    rows_cnt <= rows_cnt + 1;
                end else if (m_tready) begin
                    m_tlast <= 1'b1;
                    rows_cnt <= '0;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            line_head <= '0;
            head_direct <= HEAD_FWD;
            out_line_ready <= 1'b0;
            m_tvalid <= 1'b0;
        end else begin
            if (s_thandshake || (last_row_out & m_tready)) begin

                // output when 0 line is saved
                if (out_line_ready) begin
                    m_tdata <= line_buf[line_head];
                    m_tvalid <= 1'b1;
                end

                // head move
                if (head_direct == HEAD_FWD)
                    line_head <= line_head + 1;
                else if (head_direct == HEAD_BACK)
                    line_head <= line_head - 1;

                // head direction change
                if (line_head == IMG_WIDTH-2 && head_direct == HEAD_FWD || //the second-to-last one moves forward
                    line_head == 1 && head_direct == HEAD_BACK // OR the first one goes backward
                ) begin
                    head_direct <= HEAD_STAY;
                end else if (line_head == IMG_WIDTH-1) begin
                    head_direct <= HEAD_BACK;
                    out_line_ready <= 1'b1;
                end else if (~|line_head) begin // line_head == 0
                    head_direct <= HEAD_FWD;
                end
            end else if (m_tready) begin
                m_tvalid <= 1'b0;
            end

            if (flush) begin
                out_line_ready <= 1'b0;
                head_direct <= HEAD_FWD;
                line_head <= '0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
        end else begin
            if (s_thandshake) begin
                // save input pixels in line
                line_buf[line_head] <= s_tdata;
            end
        end
    end

endmodule
