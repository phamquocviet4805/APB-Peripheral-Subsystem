module tb_apb_gpio;

    logic        PCLK;
    logic        PRESETn;

    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;

    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_oe;

    // DUT
    apb_gpio dut (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),

        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PADDR    (PADDR),
        .PWDATA   (PWDATA),

        .PRDATA   (PRDATA),
        .PREADY   (PREADY),
        .PSLVERR  (PSLVERR),

        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .gpio_oe  (gpio_oe)
    );

    logic [31:0] read_data;

    // 100 MHz clock
    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    // Task to reset the DUT
    task reset_dut;
        begin
            PRESETn = 0;

            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;
            PADDR   = 0;
            PWDATA  = 0;
            gpio_in = 0;

            repeat (2) @(posedge PCLK);

            PRESETn = 1;

            @(posedge PCLK);
        end
    endtask

    // Task to perform an APB write transaction
    task apb_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            // SETUP phase
            @(negedge PCLK);
            PSEL    = 1;
            PENABLE = 0;
            PWRITE  = 1;
            PADDR   = addr;
            PWDATA  = data;

            // ACCESS phase
            @(negedge PCLK);
            PENABLE = 1;

            // Slave able to write
            @(posedge PCLK);

            // Finish
            @(negedge PCLK);
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;

        end
    endtask

    // Task to perform an APB read transaction
    task apb_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            // SETUP
            @(negedge PCLK);
            PSEL    = 1;
            PENABLE = 0;
            PWRITE  = 0;
            PADDR   = addr;

            // ACCESS
            @(negedge PCLK);
            PENABLE = 1;

            @(posedge PCLK);
            data = PRDATA;

            // Finish
            @(negedge PCLK);
            PSEL    = 0;
            PENABLE = 0;

        end
    endtask

    initial begin
        reset_dut();

        // Test GPIO_DATA write
        apb_write(32'h0000_0000, 32'h0000_005A);

        if (gpio_out !== 8'h5A)
            $fatal(1, "GPIO_DATA write failed");

        // Read back GPIO_DATA
        apb_read(32'h0000_0000, read_data);

        if (read_data !== 32'h0000_005A)
            $fatal(1, "GPIO_DATA read failed");

        // Test GPIO_DIR
        apb_write(32'h0000_0004, 32'h0000_000F);

        if (gpio_oe !== 8'h0F)
            $fatal(1, "GPIO_DIR write failed");

        // Test GPIO_INPUT
        gpio_in = 8'hA5;

        apb_read(32'h0000_0008, read_data);

        if (read_data !== 32'h0000_00A5)
            $fatal(1, "GPIO_INPUT read failed");

        $display("================================");
        $display("       ALL TESTS PASSED");
        $display("================================");

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("waves/apb_gpio.vcd");
        $dumpvars(0, tb_apb_gpio);
    end 

endmodule
