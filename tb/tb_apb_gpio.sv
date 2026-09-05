module tb_apb_gpio;

    logic        PCLK;
    logic        PRESETn;

    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [7:0]  PADDR;
    logic [31:0] PWDATA;

    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_oe;

    logic        gpio_irq;

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
        .gpio_oe  (gpio_oe),
        .gpio_irq (gpio_irq)
    );

    logic [31:0] read_data;

    // Clock (period = 10 simulation time units)
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

            @(negedge PCLK);
            PRESETn = 1;

            @(posedge PCLK);
        end
    endtask

    // Task to perform an APB write transaction
    task apb_write(
        input logic [7:0] addr,
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

            if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
                $fatal(1, "APB response failed at address %h", addr);

            // Finish
            @(negedge PCLK);
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;

        end
    endtask

    // Task to perform an APB read transaction
    task apb_read(
        input  logic [7:0] addr,
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

            if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
                $fatal(1, "APB response failed at address %h", addr);

            // Finish
            @(negedge PCLK);
            PSEL    = 0;
            PENABLE = 0;

        end
    endtask

    task check_reg(input logic [7:0] addr, input logic [31:0] expected);
        logic [31:0] actual;
        begin
            apb_read(addr, actual);
            if (actual !== expected)
                $fatal(1, "Register %h: expected %h, got %h", addr, expected, actual);
        end
    endtask

    // Allow both synchronizer stages and the interrupt latch to update.
    task drive_input(input logic [7:0] value);
        begin
            @(negedge PCLK);
            gpio_in = value;
            repeat (3) @(posedge PCLK);
            @(negedge PCLK);
        end
    endtask

    initial begin
        repeat (1000) @(posedge PCLK);
        $fatal(1, "TIMEOUT: GPIO test did not complete");
    end

    initial begin
        reset_dut();
        if (gpio_out !== 8'h00 || gpio_oe !== 8'h00 || gpio_irq !== 1'b0)
            $fatal(1, "Reset outputs failed");
        check_reg(8'h00, 32'd0);
        check_reg(8'h04, 32'd0);
        check_reg(8'h08, 32'd0);
        check_reg(8'h0C, 32'd0);
        check_reg(8'h10, 32'd0);
        check_reg(8'h14, 32'd0);
        $display("[PASS] Reset");

        // Test GPIO_DATA write
        apb_write(8'h00, 32'h0000_005A);

        if (gpio_out !== 8'h5A)
            $fatal(1, "GPIO_DATA write failed");

        // Read back GPIO_DATA
        apb_read(8'h00, read_data);

        if (read_data !== 32'h0000_005A)
            $fatal(1, "GPIO_DATA read failed");

        // Test GPIO_DIR
        apb_write(8'h04, 32'h0000_000F);

        if (gpio_oe !== 8'h0F)
            $fatal(1, "GPIO_DIR write failed");

        // Test GPIO_INPUT
        drive_input(8'hA5);

        apb_read(8'h08, read_data);

        if (read_data !== 32'h0000_00A5)
            $fatal(1, "GPIO_INPUT read failed");

        check_reg(8'h04, 32'h0000_000F);

        // Only the low eight write-data bits are implemented.
        apb_write(8'h00, 32'hFFFF_FFA6);
        check_reg(8'h00, 32'h0000_00A6);
        apb_write(8'h04, 32'hFFFF_FF3C);
        check_reg(8'h04, 32'h0000_003C);
        if (gpio_out !== 8'hA6 || gpio_oe !== 8'h3C)
            $fatal(1, "DATA/DIR output mapping failed");
        $display("[PASS] DATA, DIR and synchronized INPUT");

        // Establish a clean baseline after input testing.
        drive_input(8'h00);
        apb_write(8'h18, 32'hFF);
        apb_write(8'h10, 32'hFFFF_FFFF); // All rising edges.
        check_reg(8'h10, 32'hFF);
        drive_input(8'h03);
        check_reg(8'h14, 32'h03);
        if (gpio_irq !== 1'b0)
            $fatal(1, "Masked events must not assert IRQ");

        apb_write(8'h0C, 32'hFFFF_FF03);
        check_reg(8'h0C, 32'h03);
        if (gpio_irq !== 1'b1)
            $fatal(1, "Enabling pending events must assert IRQ");
        apb_write(8'h0C, 32'd0);
        if (gpio_irq !== 1'b0)
            $fatal(1, "Masking IRQ failed");
        check_reg(8'h14, 32'h03);
        apb_write(8'h0C, 32'h03);
        $display("[PASS] Rising edges and IRQ masking");

        apb_write(8'h18, 32'd0);
        check_reg(8'h14, 32'h03);
        apb_write(8'h18, 32'h01);
        check_reg(8'h14, 32'h02);
        if (gpio_irq !== 1'b1)
            $fatal(1, "Clearing bit 0 must preserve pending bit 1");
        apb_write(8'h18, 32'h02);
        check_reg(8'h14, 32'd0);
        if (gpio_irq !== 1'b0)
            $fatal(1, "IRQ clear failed");
        // Inputs remain high: edge interrupts must not retrigger.
        repeat (4) @(negedge PCLK);
        check_reg(8'h14, 32'd0);
        drive_input(8'h00); // Falling edges ignored in rising mode.
        check_reg(8'h14, 32'd0);
        $display("[PASS] Selective write-one-to-clear and edge filtering");

        apb_write(8'h10, 32'd0); // All falling edges.
        drive_input(8'h03);
        check_reg(8'h14, 32'd0); // Rising edges ignored.
        drive_input(8'h00);
        check_reg(8'h14, 32'h03);
        if (gpio_irq !== 1'b1)
            $fatal(1, "Falling-edge IRQ failed");
        apb_write(8'h18, 32'h03);
        check_reg(8'h14, 32'd0);
        if (gpio_irq !== 1'b0)
            $fatal(1, "Falling-edge IRQ clear failed");
        $display("[PASS] Falling edges");

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
