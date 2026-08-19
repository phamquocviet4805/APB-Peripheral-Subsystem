module apb_gpio (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output reg         PREADY,
    output reg         PSLVERR,

    // GPIO interface
    input  wire [7:0] gpio_in,
    output reg  [7:0] gpio_out,
    output reg  [7:0] gpio_oe
);

    localparam logic [7:0] GPIO_DATA    = 8'h00;
    localparam logic [7:0] GPIO_DIR     = 8'h04;
    localparam logic [7:0] GPIO_INPUT   = 8'h08;

    logic [7:0] data_reg;
    logic [7:0] dir_reg;

    logic apb_write;

    //Note: PSEL and PENABLE are used to determine if the APB transaction is valid
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    assign gpio_out = data_reg;
    assign gpio_oe  = dir_reg;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            data_reg <= 8'h00;
            dir_reg <= 8'h00;
        end
        else if (apb_write) begin
            case (PADDR[7:0])
                GPIO_DATA:
                    data_reg <= PWDATA[7:0];
                GPIO_DIR:
                    dir_reg <= PWDATA[7:0];
                default: begin
                end
            endcase
        end
    end

    always_comb begin
        PRDATA = 32'h0;

        if (PSEL && !PWRITE) begin
            case (PADDR[7:0])
                GPIO_DATA:
                    PRDATA = {24'h0, data_reg};

                GPIO_DIR:
                    PRDATA = {24'h0, dir_reg};

                GPIO_INPUT:
                    PRDATA = {24'h0, gpio_in};

                default:
                    PRDATA = 32'h0;
            endcase
        end
    end    

endmodule