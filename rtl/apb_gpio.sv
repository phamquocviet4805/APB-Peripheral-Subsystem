module apb_gpio (
    input  logic        PCLK,
    input  logic        PRESETn,

    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [7:0]  PADDR,
    input  logic [31:0] PWDATA,

    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // GPIO interface
    input  logic [7:0] gpio_in,
    output logic [7:0] gpio_out,
    output logic [7:0] gpio_oe,

    // GPIO interrupt
    output logic       gpio_irq
);

    // ============================================================
    // Register map
    // ============================================================

    localparam [7:0] GPIO_DATA       = 8'h00;
    localparam [7:0] GPIO_DIR        = 8'h04;
    localparam [7:0] GPIO_INPUT      = 8'h08;

    localparam [7:0] GPIO_INT_EN     = 8'h0C;
    localparam [7:0] GPIO_INT_TYPE   = 8'h10;
    localparam [7:0] GPIO_INT_STATUS = 8'h14;
    localparam [7:0] GPIO_INT_CLR    = 8'h18;


    // ============================================================
    // GPIO registers
    // ============================================================

    logic [7:0] data_reg;
    logic [7:0] dir_reg;


    // ============================================================
    // Interrupt registers
    // ============================================================

    logic [7:0] int_en_reg;
    logic [7:0] int_type_reg;
    logic [7:0] int_status_reg;


    // ============================================================
    // GPIO input synchronizer
    // ============================================================

    logic [7:0] gpio_sync1;
    logic [7:0] gpio_sync2;
    logic [7:0] gpio_sync2_d;


    // ============================================================
    // Edge detection
    // ============================================================

    logic [7:0] rising_edge;
    logic [7:0] falling_edge;
    logic [7:0] interrupt_event;


    // ============================================================
    // APB control
    // ============================================================

    logic apb_write;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    assign apb_write =
        PSEL &&
        PENABLE &&
        PWRITE &&
        PREADY;


    // ============================================================
    // GPIO outputs
    // ============================================================

    assign gpio_out = data_reg;
    assign gpio_oe  = dir_reg;


    // ============================================================
    // GPIO input synchronization
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_sync1   <= 8'h00;
            gpio_sync2   <= 8'h00;
            gpio_sync2_d <= 8'h00;
        end
        else begin
            gpio_sync1   <= gpio_in;
            gpio_sync2   <= gpio_sync1;
            gpio_sync2_d <= gpio_sync2;
        end
    end


    // ============================================================
    // Edge detection
    //
    // INT_TYPE bit:
    // 1 = rising-edge interrupt
    // 0 = falling-edge interrupt
    // ============================================================

    assign rising_edge =
        gpio_sync2 & ~gpio_sync2_d;

    assign falling_edge =
        ~gpio_sync2 & gpio_sync2_d;

    assign interrupt_event =
        (rising_edge  &  int_type_reg) |
        (falling_edge & ~int_type_reg);


    // ============================================================
    // GPIO interrupt output
    // ============================================================

    assign gpio_irq =
        |(int_status_reg & int_en_reg);


    // ============================================================
    // DATA / DIR register writes
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            data_reg <= 8'h00;
            dir_reg  <= 8'h00;
        end
        else if (apb_write) begin
            case (PADDR)

                GPIO_DATA:
                    data_reg <= PWDATA[7:0];

                GPIO_DIR:
                    dir_reg <= PWDATA[7:0];

                default:
                    ;

            endcase
        end
    end


    // ============================================================
    // Interrupt registers
    // ============================================================

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            int_en_reg     <= 8'h00;
            int_type_reg   <= 8'h00;
            int_status_reg <= 8'h00;
        end
        else begin

            // Latch detected interrupt events
            int_status_reg <=
                int_status_reg | interrupt_event;

            if (apb_write) begin
                case (PADDR)

                    GPIO_INT_EN:
                        int_en_reg <= PWDATA[7:0];

                    GPIO_INT_TYPE:
                        int_type_reg <= PWDATA[7:0];

                    GPIO_INT_CLR:
                        int_status_reg <=
                            (int_status_reg & ~PWDATA[7:0])
                            | interrupt_event;

                    default:
                        ;

                endcase
            end
        end
    end


    // ============================================================
    // APB read
    // ============================================================

    always_comb begin

        PRDATA = 32'h0000_0000;

        if (PSEL && !PWRITE) begin
            case (PADDR)

                GPIO_DATA:
                    PRDATA = {24'h0, data_reg};

                GPIO_DIR:
                    PRDATA = {24'h0, dir_reg};

                // Read synchronized GPIO input
                GPIO_INPUT:
                    PRDATA = {24'h0, gpio_sync2};

                GPIO_INT_EN:
                    PRDATA = {24'h0, int_en_reg};

                GPIO_INT_TYPE:
                    PRDATA = {24'h0, int_type_reg};

                GPIO_INT_STATUS:
                    PRDATA = {24'h0, int_status_reg};

                default:
                    PRDATA = 32'h0000_0000;

            endcase
        end
    end

endmodule
