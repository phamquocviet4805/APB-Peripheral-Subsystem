module apb_subsystem (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB interface
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,

    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // GPIO interface
    input  logic [7:0]  gpio_in,
    output logic [7:0]  gpio_out,
    output logic [7:0]  gpio_oe,

    // UART interface
    input  logic        uart_rx,
    output logic        uart_tx,

    // Interrupt outputs
    output logic        gpio_irq,
    output logic        timer_irq,
    output logic        uart_irq
);

    // ============================================================
    // Address map
    //
    // GPIO:
    //   0x0000_0000 - 0x0000_00FF
    //
    // Timer:
    //   0x0000_0100 - 0x0000_01FF
    // ============================================================

    // UART: 0x0000_0200 - 0x0000_02FF
    localparam [7:0] UART_PAGE  = 8'h02;
    localparam [7:0] GPIO_PAGE  = 8'h00;
    localparam [7:0] TIMER_PAGE = 8'h01;


    // ============================================================
    // Slave select
    // ============================================================

    logic gpio_psel;
    logic timer_psel;
    logic uart_psel;

    assign uart_psel = PSEL && (PADDR[15:8] == UART_PAGE);

    assign gpio_psel =
        PSEL && (PADDR[15:8] == GPIO_PAGE);

    assign timer_psel =
        PSEL && (PADDR[15:8] == TIMER_PAGE);


    // ============================================================
    // GPIO response
    // ============================================================

    logic [31:0] gpio_prdata;
    logic        gpio_pready;
    logic        gpio_pslverr;


    // ============================================================
    // Timer response
    // ============================================================

    logic [31:0] timer_prdata;
    logic        timer_pready;
    logic        timer_pslverr;


    // ============================================================
    // GPIO peripheral
    // ============================================================

    apb_gpio u_apb_gpio (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),

        .PSEL      (gpio_psel),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR[7:0]),
        .PWDATA    (PWDATA),

        .PRDATA    (gpio_prdata),
        .PREADY    (gpio_pready),
        .PSLVERR   (gpio_pslverr),

        .gpio_in   (gpio_in),
        .gpio_out  (gpio_out),
        .gpio_oe   (gpio_oe),

        .gpio_irq  (gpio_irq)
    );


    // ============================================================
    // Timer peripheral
    // ============================================================

    apb_timer u_apb_timer (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),

        .PSEL      (timer_psel),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR[7:0]),
        .PWDATA    (PWDATA),

        .PRDATA    (timer_prdata),
        .PREADY    (timer_pready),
        .PSLVERR   (timer_pslverr),

        .irq       (timer_irq)
    );


    logic [31:0] uart_prdata;
    logic        uart_pready;
    logic        uart_pslverr;

    apb_uart u_apb_uart (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .PSEL      (uart_psel),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR[7:0]),
        .PWDATA    (PWDATA),
        .PRDATA    (uart_prdata),
        .PREADY    (uart_pready),
        .PSLVERR   (uart_pslverr),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .uart_irq  (uart_irq)
    );


    // ============================================================
    // APB response mux
    // ============================================================

    always_comb begin

        PRDATA  = 32'h0000_0000;
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        if (gpio_psel) begin

            PRDATA  = gpio_prdata;
            PREADY  = gpio_pready;
            PSLVERR = gpio_pslverr;

        end

        else if (timer_psel) begin

            PRDATA  = timer_prdata;
            PREADY  = timer_pready;
            PSLVERR = timer_pslverr;

        end

        else if (uart_psel) begin
            PRDATA  = uart_prdata;
            PREADY  = uart_pready;
            PSLVERR = uart_pslverr;
        end

        // Invalid APB address
        else if (PSEL && PENABLE) begin

            PRDATA  = 32'h0000_0000;
            PREADY  = 1'b1;
            PSLVERR = 1'b1;

        end

    end

endmodule
