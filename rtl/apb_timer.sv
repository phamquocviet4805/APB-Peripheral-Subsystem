module apb_timer (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB interface
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [7:0] PADDR,
    input  logic [31:0] PWDATA,

    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // Timer output
    output logic        irq
);

    // Register map
    localparam [7:0] TIMER_CTRL   = 8'h00;
    localparam [7:0] TIMER_LOAD   = 8'h04;
    localparam [7:0] TIMER_VALUE  = 8'h08;
    localparam [7:0] TIMER_STATUS = 8'h0C;

    // Internal registers
    logic        enable_reg;
    logic [31:0] load_reg;
    logic [31:0] counter_reg;

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
            enable_reg <= 1'b0;
            load_reg   <= 32'h0000_0000;
            counter_reg <= 32'h0000_0000;
            irq         <= 1'b0;
        end
        else begin
            // APB register write
            if (apb_write) begin
                case (PADDR)
                    // TIMER_CTRL
                    TIMER_CTRL: begin
                        enable_reg <= PWDATA[0];
                        // Disable timer -> clear interrupt
                        if (!PWDATA[0])
                            irq <= 1'b0;
                    end

                    // TIMER_LOAD
                    TIMER_LOAD: begin
                        load_reg    <= PWDATA;
                        counter_reg <= PWDATA;
                        irq         <= 1'b0;
                    end

                    default: begin
                        // TIMER_VALUE and TIMER_STATUS are RO
                    end
                endcase
            end

            // Timer countdown
            else if (enable_reg) begin
                if (counter_reg > 32'd1) begin
                    counter_reg <= counter_reg - 32'd1;
                end
                else if (counter_reg == 32'd1) begin
                    counter_reg <= 32'd0;

                    // Timer expired
                    irq <= 1'b1;

                    // One-shot timer
                    enable_reg <= 1'b0;
                end
            end
        end
    end

    // Read
    always_comb begin
        PRDATA = 32'h0000_0000;
        if (PSEL && !PWRITE) begin
            case (PADDR)
                TIMER_CTRL: begin
                    PRDATA = {31'h0, enable_reg};
                end

                TIMER_LOAD: begin
                    PRDATA = load_reg;
                end

                TIMER_VALUE: begin
                    PRDATA = counter_reg;
                end

                TIMER_STATUS: begin
                    PRDATA = {31'h0, irq};
                end

                default: begin
                    PRDATA = 32'h0000_0000;
                end
            endcase
        end
    end

endmodule
