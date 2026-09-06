module uart_rx (
    input  logic        PCLK,
    input  logic        PRESETn,

    input  logic        enable,
    input  logic        rx,
    input  logic [15:0] baud_div,

    output logic [7:0]  data_out,
    output logic        valid,
    output logic        frame_error
);

    // ============================================================
    // States
    // ============================================================

    localparam [2:0] RX_IDLE  = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA  = 3'd2;
    localparam [2:0] RX_STOP  = 3'd3;

    logic [2:0] state;


    // ============================================================
    // Input synchronizer
    // ============================================================

    logic rx_sync1;
    logic rx_sync2;


    // ============================================================
    // Internal registers
    // ============================================================

    logic [7:0]  rx_shift;
    logic [2:0]  bit_index;
    logic [15:0] baud_cnt;

    logic [15:0] baud_div_eff;
    logic [15:0] half_div;

    assign baud_div_eff =
        (baud_div < 16'd2) ? 16'd2 : baud_div;

    assign half_div =
        baud_div_eff >> 1;


    // ============================================================
    // RX input synchronization
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin

        if (!PRESETn) begin

            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;

        end
        else begin

            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;

        end
    end


    // ============================================================
    // RX FSM
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin

        if (!PRESETn) begin

            state       <= RX_IDLE;
            rx_shift    <= 8'h00;
            bit_index   <= 3'd0;
            baud_cnt    <= 16'd0;

            data_out    <= 8'h00;
            valid       <= 1'b0;
            frame_error <= 1'b0;

        end
        else begin

            // One-cycle pulses
            valid       <= 1'b0;
            frame_error <= 1'b0;

            if (!enable) begin

                state     <= RX_IDLE;
                baud_cnt  <= 16'd0;
                bit_index <= 3'd0;

            end
            else begin

                case (state)

                    // ------------------------------------------------
                    // Wait for start bit
                    // ------------------------------------------------

                    RX_IDLE: begin

                        baud_cnt <= 16'd0;

                        if (rx_sync2 == 1'b0) begin

                            state <= RX_START;

                        end
                    end


                    // ------------------------------------------------
                    // Sample middle of start bit
                    // ------------------------------------------------

                    RX_START: begin

                        if (baud_cnt >= (half_div - 16'd1)) begin

                            baud_cnt <= 16'd0;

                            // Start bit must still be low
                            if (rx_sync2 == 1'b0) begin

                                bit_index <= 3'd0;
                                state     <= RX_DATA;

                            end
                            else begin

                                // False start
                                state <= RX_IDLE;

                            end
                        end
                        else begin

                            baud_cnt <= baud_cnt + 16'd1;

                        end
                    end


                    // ------------------------------------------------
                    // Receive 8 data bits
                    // ------------------------------------------------

                    RX_DATA: begin

                        if (baud_cnt >= (baud_div_eff - 16'd1)) begin

                            baud_cnt <= 16'd0;

                            rx_shift[bit_index] <= rx_sync2;

                            if (bit_index == 3'd7) begin

                                state <= RX_STOP;

                            end
                            else begin

                                bit_index <= bit_index + 3'd1;

                            end
                        end
                        else begin

                            baud_cnt <= baud_cnt + 16'd1;

                        end
                    end


                    // ------------------------------------------------
                    // Stop bit
                    // ------------------------------------------------

                    RX_STOP: begin

                        if (baud_cnt >= (baud_div_eff - 16'd1)) begin

                            baud_cnt <= 16'd0;

                            if (rx_sync2 == 1'b1) begin

                                data_out <= rx_shift;
                                valid    <= 1'b1;

                            end
                            else begin

                                frame_error <= 1'b1;

                            end

                            state <= RX_IDLE;

                        end
                        else begin

                            baud_cnt <= baud_cnt + 16'd1;

                        end
                    end


                    default: begin

                        state <= RX_IDLE;

                    end

                endcase
            end
        end
    end

endmodule
