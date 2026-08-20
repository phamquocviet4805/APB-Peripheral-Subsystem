module tb_apb_subsystem;

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

    logic        timer_irq;

    logic [31:0] read_data;

    // DUT
    apb_subsystem dut (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),

        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR),
        .PWDATA    (PWDATA),

        .PRDATA    (PRDATA),
        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR),

        .gpio_in   (gpio_in),
        .gpio_out  (gpio_out),
        .gpio_oe   (gpio_oe),

        .timer_irq (timer_irq)
    );

    // Clock
    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    // Waveform
    initial begin
        $dumpfile("waves/apb_subsystem.vcd");
        $dumpvars(0, tb_apb_subsystem);
    end

    // Reset
    task reset_dut;
    begin
        PRESETn = 1'b0;

        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 32'h0;
        PWDATA  = 32'h0;
        gpio_in = 8'h0;

        repeat (2) @(posedge PCLK);

        PRESETn = 1'b1;

        @(posedge PCLK);
    end
    endtask

    // APB WRITE
    task apb_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
    begin
        @(negedge PCLK);

        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = addr;
        PWDATA  = data;

        @(negedge PCLK);

        PENABLE = 1'b1;

        @(posedge PCLK);

        while (!PREADY)
            @(posedge PCLK);

        @(negedge PCLK);

        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 32'h0;
        PWDATA  = 32'h0;
    end
    endtask

    // APB READ
    task apb_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
    begin
        @(negedge PCLK);

        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = addr;

        @(negedge PCLK);

        PENABLE = 1'b1;

        @(posedge PCLK);

        while (!PREADY)
            @(posedge PCLK);

        data = PRDATA;

        @(negedge PCLK);

        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PADDR   = 32'h0;
    end
    endtask

    // Test
    initial begin

        reset_dut();

        // GPIO DATA
        apb_write(32'h0000_0000, 32'h0000_005A);

        if (gpio_out !== 8'h5A)
            $fatal(1, "GPIO_DATA write failed");

        apb_read(32'h0000_0000, read_data);

        if (read_data !== 32'h0000_005A)
            $fatal(1, "GPIO_DATA read failed");

        $display("[PASS] GPIO_DATA");


        // GPIO DIR
        apb_write(32'h0000_0004, 32'h0000_000F);

        if (gpio_oe !== 8'h0F)
            $fatal(1, "GPIO_DIR write failed");

        $display("[PASS] GPIO_DIR");


        // GPIO INPUT
        gpio_in = 8'hA5;

        apb_read(32'h0000_0008, read_data);

        if (read_data !== 32'h0000_00A5)
            $fatal(1, "GPIO_INPUT read failed");

        $display("[PASS] GPIO_INPUT");


        // TIMER LOAD
        apb_write(32'h0000_0104, 32'd5);

        apb_read(32'h0000_0104, read_data);

        if (read_data !== 32'd5)
            $fatal(1, "TIMER_LOAD failed");

        $display("[PASS] TIMER_LOAD");


        // Check GPIO not affected by Timer access
        if (gpio_out !== 8'h5A)
            $fatal(1, "Timer access corrupted GPIO");

        if (gpio_oe !== 8'h0F)
            $fatal(1, "Timer access corrupted GPIO_DIR");

        $display("[PASS] Address isolation");


        // Enable Timer
        apb_write(32'h0000_0100, 32'd1);

        wait (timer_irq == 1'b1);

        apb_read(32'h0000_0108, read_data);

        if (read_data !== 32'd0)
            $fatal(1, "Timer did not reach zero");

        $display("[PASS] Timer countdown");


        // Timer STATUS
        apb_read(32'h0000_010C, read_data);

        if (read_data[0] !== 1'b1)
            $fatal(1, "Timer IRQ status failed");

        $display("[PASS] TIMER_STATUS");


        $display("");
        $display("================================");
        $display("     SUBSYSTEM TEST PASSED");
        $display("================================");

        $finish;
    end

endmodule
