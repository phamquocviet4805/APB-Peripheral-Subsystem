module apb_uart (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB interface
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [7:0]  PADDR,
    input  logic [31:0] PWDATA,

    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // UART pins
    input  logic        uart_rx,
    output logic        uart_tx,

    // Interrupt
    output logic        uart_irq
);

    // ============================================================
    // Register map
    // ============================================================

    localparam [7:0] UART_TXDATA     = 8'h00;
    localparam [7:0] UART_RXDATA     = 8'h04;
    localparam [7:0] UART_STATUS     = 8'h08;
    localparam [7:0] UART_CTRL       = 8'h0C;
    localparam [7:0] UART_BAUD       = 8'h10;
    localparam [7:0] UART_INT_STATUS = 8'h14;
    localparam [7:0] UART_INT_CLR    = 8'h18;


    // ============================================================
    // APB control
    // ============================================================

    logic apb_write;
    logic apb_read;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    assign apb_write =
        PSEL &&
        PENABLE &&
        PWRITE &&
        PREADY;

    assign apb_read =
        PSEL &&
        PENABLE &&
        !PWRITE &&
        PREADY;


    // ============================================================
    // Control registers
    // ============================================================

    logic tx_enable_reg;
    logic rx_enable_reg;

    logic rx_irq_en_reg;
    logic tx_irq_en_reg;

    logic [15:0] baud_div_reg;


    // ============================================================
    // TX signals
    // ============================================================

    logic [7:0] tx_data_reg;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_done;


    // ============================================================
    // RX signals
    // ============================================================

    logic [7:0] rx_data_wire;
    logic       rx_valid_pulse;
    logic       rx_frame_error_pulse;

    logic [7:0] rx_data_reg;
    logic       rx_valid_reg;
    logic       rx_overrun_reg;
    logic       rx_frame_error_reg;


    // ============================================================
    // Interrupt status
    // ============================================================

    logic tx_done_pending;


    // ============================================================
    // UART TX
    // ============================================================

    uart_tx u_uart_tx (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),

        .enable    (tx_enable_reg),
        .start     (tx_start),
        .data_in   (tx_data_reg),
        .baud_div  (baud_div_reg),

        .tx        (uart_tx),
        .busy      (tx_busy),
        .done      (tx_done)
    );


    // ============================================================
    // UART RX
    // ============================================================

    uart_rx u_uart_rx (
        .PCLK        (PCLK),
        .PRESETn     (PRESETn),

        .enable      (rx_enable_reg),
        .rx          (uart_rx),
        .baud_div    (baud_div_reg),

        .data_out    (rx_data_wire),
        .valid       (rx_valid_pulse),
        .frame_error (rx_frame_error_pulse)
    );


    // ============================================================
    // Register / status update
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin

        if (!PRESETn) begin

            tx_enable_reg      <= 1'b0;
            rx_enable_reg      <= 1'b0;

            rx_irq_en_reg      <= 1'b0;
            tx_irq_en_reg      <= 1'b0;

            // 100 MHz / 115200 baud ≈ 868 clocks per bit
            baud_div_reg       <= 16'd868;

            tx_data_reg        <= 8'h00;
            tx_start           <= 1'b0;

            rx_data_reg        <= 8'h00;
            rx_valid_reg       <= 1'b0;
            rx_overrun_reg     <= 1'b0;
            rx_frame_error_reg <= 1'b0;

            tx_done_pending    <= 1'b0;

        end
        else begin

            // TX start is only a one-cycle pulse
            tx_start <= 1'b0;


            // ====================================================
            // APB writes
            // ====================================================

            if (apb_write) begin

                case (PADDR)

                    // --------------------------------------------
                    // TX data
                    // --------------------------------------------

                    UART_TXDATA: begin

                        if (tx_enable_reg && !tx_busy) begin

                            tx_data_reg <= PWDATA[7:0];
                            tx_start    <= 1'b1;

                        end
                    end


                    // --------------------------------------------
                    // Control
                    // --------------------------------------------

                    UART_CTRL: begin

                        tx_enable_reg <= PWDATA[0];
                        rx_enable_reg <= PWDATA[1];

                        rx_irq_en_reg <= PWDATA[2];
                        tx_irq_en_reg <= PWDATA[3];

                    end


                    // --------------------------------------------
                    // Baud divider
                    // --------------------------------------------

                    UART_BAUD: begin

                        baud_div_reg <= PWDATA[15:0];

                    end


                    // --------------------------------------------
                    // Interrupt clear
                    //
                    // bit[0] clear RX valid
                    // bit[1] clear TX done
                    // bit[2] clear RX overrun
                    // bit[3] clear frame error
                    // --------------------------------------------

                    UART_INT_CLR: begin

                        if (PWDATA[0])
                            rx_valid_reg <= 1'b0;

                        if (PWDATA[1])
                            tx_done_pending <= 1'b0;

                        if (PWDATA[2])
                            rx_overrun_reg <= 1'b0;

                        if (PWDATA[3])
                            rx_frame_error_reg <= 1'b0;

                    end


                    default:
                        ;

                endcase
            end


            // ====================================================
            // Reading RXDATA consumes current byte
            // ====================================================

            if (
                apb_read &&
                (PADDR == UART_RXDATA)
            ) begin

                rx_valid_reg <= 1'b0;

            end


            // ====================================================
            // TX completion
            // ====================================================

            if (tx_done) begin

                tx_done_pending <= 1'b1;

            end


            // ====================================================
            // RX byte received
            // ====================================================

            if (rx_valid_pulse) begin

                if (!rx_valid_reg) begin

                    rx_data_reg  <= rx_data_wire;
                    rx_valid_reg <= 1'b1;

                end
                else begin

                    // Previous byte was not consumed
                    rx_overrun_reg <= 1'b1;

                end
            end


            // ====================================================
            // RX frame error
            // ====================================================

            if (rx_frame_error_pulse) begin

                rx_frame_error_reg <= 1'b1;

            end
        end
    end


    // ============================================================
    // IRQ generation
    // ============================================================

    assign uart_irq =
        (
            rx_irq_en_reg &&
            (
                rx_valid_reg       ||
                rx_overrun_reg     ||
                rx_frame_error_reg
            )
        )
        ||
        (
            tx_irq_en_reg &&
            tx_done_pending
        );


    // ============================================================
    // APB read
    // ============================================================

    always_comb begin

        PRDATA = 32'h0000_0000;

        if (PSEL && !PWRITE) begin

            case (PADDR)

                UART_TXDATA:
                    PRDATA = 32'h0000_0000;


                UART_RXDATA:
                    PRDATA = {
                        24'h000000,
                        rx_data_reg
                    };


                UART_STATUS:
                    PRDATA = {
                        28'h0000000,
                        rx_frame_error_reg,
                        rx_overrun_reg,
                        rx_valid_reg,
                        tx_busy
                    };


                UART_CTRL:
                    PRDATA = {
                        28'h0000000,
                        tx_irq_en_reg,
                        rx_irq_en_reg,
                        rx_enable_reg,
                        tx_enable_reg
                    };


                UART_BAUD:
                    PRDATA = {
                        16'h0000,
                        baud_div_reg
                    };


                UART_INT_STATUS:
                    PRDATA = {
                        28'h0000000,
                        rx_frame_error_reg,
                        rx_overrun_reg,
                        tx_done_pending,
                        rx_valid_reg
                    };


                UART_INT_CLR:
                    PRDATA = 32'h0000_0000;


                default:
                    PRDATA = 32'h0000_0000;

            endcase
        end
    end

endmodule
