module uart_tx (
    input  logic        PCLK,
    input  logic        PRESETn,

    input  logic        enable,
    input  logic        start,
    input  logic [7:0]  data_in,
    input  logic [15:0] baud_div,

    output logic        tx,
    output logic        busy,
    output logic        done
);

    // ============================================================
    // States
    // ============================================================

    localparam [2:0] TX_IDLE  = 3'd0;
    localparam [2:0] TX_START = 3'd1;
    localparam [2:0] TX_DATA  = 3'd2;
    localparam [2:0] TX_STOP  = 3'd3;

    logic [2:0] state;

    // ============================================================
    // Internal registers
    // ============================================================

    logic [7:0]  tx_shift;
    logic [2:0]  bit_index;
    logic [15:0] baud_cnt;

    logic [15:0] baud_div_eff;

    // Prevent invalid very-small divider
    assign baud_div_eff =
        (baud_div < 16'd2) ? 16'd2 : baud_div;


    // ============================================================
    // TX FSM
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin

        if (!PRESETn) begin

            state     <= TX_IDLE;
            tx_shift  <= 8'h00;
            bit_index <= 3'd0;
            baud_cnt  <= 16'd0;

            tx         <= 1'b1;
            busy       <= 1'b0;
            done       <= 1'b0;

        end
        else begin

            // done is a one-cycle pulse
            done <= 1'b0;

            // Disable aborts current transmission
            if (!enable) begin

                state     <= TX_IDLE;
                baud_cnt  <= 16'd0;
                bit_index <= 3'd0;

                tx   <= 1'b1;
                busy <= 1'b0;

            end
            else begin

                case (state)

                    // ------------------------------------------------
                    // IDLE
                    // ------------------------------------------------

                    TX_IDLE: begin

                        tx       <= 1'b1;
                        busy     <= 1'b0;
                        baud_cnt <= 16'd0;

                        if (start) begin

                            tx_shift  <= data_in;
                            bit_index <= 3'd0;

                            tx   <= 1'b0;
                            busy <= 1'b1;

                            state <= TX_START;

                        end
                    end


                    // ------------------------------------------------
                    // START BIT
                    // ------------------------------------------------

                    TX_START: begin

                        if (baud_cnt >= (baud_div_eff - 16'd1)) begin

                            baud_cnt <= 16'd0;

                            tx <= tx_shift[0];

                            bit_index <= 3'd0;
                            state     <= TX_DATA;

                        end
                        else begin

                            baud_cnt <= baud_cnt + 16'd1;

                        end
                    end


                    // ------------------------------------------------
                    // DATA BITS
                    // ------------------------------------------------

                    TX_DATA: begin

                        if (baud_cnt >= (baud_div_eff - 16'd1)) begin

                            baud_cnt <= 16'd0;

                            if (bit_index == 3'd7) begin

                                tx    <= 1'b1;
                                state <= TX_STOP;

                            end
                            else begin

                                bit_index <= bit_index + 3'd1;

                                tx <= tx_shift[bit_index + 3'd1];

                            end
                        end
                        else begin

                            baud_cnt <= baud_cnt + 16'd1;

                        end
                    end


                    // ------------------------------------------------
                    // STOP BIT
                    // ------------------------------------------------

                    TX_STOP: begin

                        if (baud_cnt >= (baud_div_eff - 16'd1)) begin

                            baud_cnt <= 16'd0;

                            tx   <= 1'b1;
                            busy <= 1'b0;
                            done <= 1'b1;

                            state <= TX_IDLE;

                        end
                        else begin

                            baud_cnt <= baud_cnt + 16'd1;

                        end
                    end


                    default: begin

                        state <= TX_IDLE;
                        tx    <= 1'b1;
                        busy  <= 1'b0;

                    end

                endcase
            end
        end
    end

endmodule
