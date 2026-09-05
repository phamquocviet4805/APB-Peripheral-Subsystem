module apb_timer (
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

    // Timer output
    output logic        irq
);

    // Register map
    localparam [7:0] TIMER_CTRL     = 8'h00;
    localparam [7:0] TIMER_LOAD     = 8'h04;
    localparam [7:0] TIMER_VALUE    = 8'h08;
    localparam [7:0] TIMER_STATUS   = 8'h0C;
    localparam [7:0] TIMER_PRESCALE = 8'h10;
    localparam [7:0] TIMER_INTCLR   = 8'h14;

    // Internal registers
    logic        enable_reg;
    logic        periodic_reg;
    logic [31:0] load_reg;
    logic [31:0] counter_reg;

    logic [15:0] prescale_reg;
    logic [15:0] prescale_cnt;

    logic        apb_write;

    // APB transfer detection
    assign apb_write = PSEL &&
                       PENABLE &&
                       PWRITE &&
                       PREADY;

    // APB response
    // Zero-wait-state slave
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;


    // Timer registers + counter logic
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            enable_reg   <= 1'b0;
            periodic_reg <= 1'b0;

            load_reg     <= 32'd0;
            counter_reg  <= 32'd0;

            prescale_reg <= 16'd0;
            prescale_cnt <= 16'd0;

            irq           <= 1'b0;
        end
        else begin

            // APB write has highest priority
            if (apb_write) begin
                case (PADDR)

                    TIMER_CTRL: begin
                        enable_reg   <= PWDATA[0];
                        periodic_reg <= PWDATA[1];

                        if (!PWDATA[0])
                            prescale_cnt <= 16'd0;
                    end

                    TIMER_LOAD: begin
                        load_reg     <= PWDATA;
                        counter_reg  <= PWDATA;
                        prescale_cnt <= 16'd0;
                    end

                    TIMER_PRESCALE: begin
                        prescale_reg <= PWDATA[15:0];
                        prescale_cnt <= 16'd0;
                    end

                    TIMER_INTCLR: begin
                        if (PWDATA[0])
                            irq <= 1'b0;
                    end

                    default: ;
                endcase
            end

            // Timer running
            else if (enable_reg) begin

                // Prevent LOAD=0 corner case
                if (counter_reg == 32'd0) begin
                    enable_reg   <= 1'b0;
                    prescale_cnt <= 16'd0;
                end

                else if (prescale_cnt >= prescale_reg) begin
                    prescale_cnt <= 16'd0;

                    if (counter_reg > 32'd1) begin
                        counter_reg <= counter_reg - 32'd1;
                    end

                    else begin
                        // Timer expired
                        irq <= 1'b1;

                        if (periodic_reg && (load_reg != 32'd0)) begin
                            counter_reg <= load_reg;
                        end
                        else begin
                            counter_reg <= 32'd0;
                            enable_reg  <= 1'b0;
                        end
                    end
                end

                else begin
                    prescale_cnt <= prescale_cnt + 16'd1;
                end
            end
        end
    end

    // Read
    always_comb begin
        PRDATA = 32'd0;

        if (PSEL && !PWRITE) begin
            case (PADDR)

                TIMER_CTRL:
                    PRDATA = {30'd0, periodic_reg, enable_reg};

                TIMER_LOAD:
                    PRDATA = load_reg;

                TIMER_VALUE:
                    PRDATA = counter_reg;

                TIMER_STATUS:
                    PRDATA = {31'd0, irq};

                TIMER_PRESCALE:
                    PRDATA = {16'd0, prescale_reg};

                default:
                    PRDATA = 32'd0;

            endcase
        end
    end

endmodule
