module tb_apb_timer;

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

    logic        irq;

    logic [31:0] read_data;


    // DUT
    apb_timer dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),

        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),

        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR),

        .irq     (irq)
    );


    // Clock
    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end


    // Waveform
    initial begin
        $dumpfile("waves/apb_timer.vcd");
        $dumpvars(0, tb_apb_timer);
    end


    // Reset
    task reset_dut;
    begin
        PRESETn = 1'b0;

        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 8'h00;
        PWDATA  = 32'h0;

        repeat (2) @(posedge PCLK);

        @(negedge PCLK);
        PRESETn = 1'b1;

        @(posedge PCLK);
    end
    endtask


    // APB WRITE
    task apb_write(
        input logic [7:0] addr,
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
        PADDR   = 8'h00;
        PWDATA  = 32'h0;
    end
    endtask


    // APB READ
    task apb_read(
        input  logic [7:0] addr,
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
        PADDR   = 8'h00;
    end
    endtask


    // Bound the simulation if an APB transfer or IRQ wait never completes.
    initial begin
        repeat (1000) @(posedge PCLK);
        $fatal(1, "TIMEOUT: timer test did not complete");
    end


    // Test
    initial begin

        reset_dut();

        // Test reset
        if (irq !== 1'b0)
            $fatal(1, "RESET FAILED: irq is not 0");

        $display("[PASS] Reset");


        // Test TIMER_LOAD
        apb_write(
            8'h04,
            32'd5
        );

        apb_read(
            8'h04,
            read_data
        );

        if (read_data !== 32'd5)
            $fatal(
                1,
                "TIMER_LOAD FAILED: expected 5, got %0d",
                read_data
            );

        $display("[PASS] TIMER_LOAD");


        // Test TIMER_CTRL
        apb_write(
            8'h00,
            32'd1
        );

        apb_read(
            8'h00,
            read_data
        );

        if (read_data[0] !== 1'b1)
            $fatal(
                1,
                "TIMER_CTRL FAILED: enable bit not set"
            );

        $display("[PASS] TIMER_CTRL");


        // Test countdown
        @(posedge PCLK);

        apb_read(
            8'h08,
            read_data
        );

        $display(
            "[INFO] TIMER_VALUE = %0d",
            read_data
        );

        if (read_data >= 32'd5)
            $fatal(
                1,
                "COUNTDOWN FAILED: counter did not decrement"
            );

        $display("[PASS] Counter countdown");


        // Wait for timer expiration
        wait (irq == 1'b1);

        $display("[INFO] Timer expired");


        // Check counter reached zero
        apb_read(
            8'h08,
            read_data
        );

        if (read_data !== 32'd0)
            $fatal(
                1,
                "TIMER_VALUE FAILED: expected 0, got %0d",
                read_data
            );

        $display("[PASS] TIMER_VALUE reached 0");


        // Test TIMER_STATUS
        apb_read(
            8'h0C,
            read_data
        );

        if (read_data[0] !== 1'b1)
            $fatal(
                1,
                "TIMER_STATUS FAILED: irq status not set"
            );

        $display("[PASS] TIMER_STATUS");


        // One-shot expiration must disable the timer.
        apb_read(8'h00, read_data);
        if (read_data[0] !== 1'b0)
            $fatal(1, "ONE-SHOT FAILED: enable bit still set");

        // Disabling CTRL does not clear the sticky IRQ.
        apb_write(
            8'h00,
            32'd0
        );

        if (irq !== 1'b1)
            $fatal(1, "CTRL FAILED: disabling timer cleared irq");

        // INTCLR is write-one-to-clear; writing zero must preserve IRQ.
        apb_write(8'h14, 32'd0);
        if (irq !== 1'b1)
            $fatal(1, "INTCLR FAILED: writing zero cleared irq");

        apb_write(8'h14, 32'd1);
        if (irq !== 1'b0)
            $fatal(
                1,
                "IRQ CLEAR FAILED"
            );

        apb_read(8'h0C, read_data);
        if (read_data !== 32'd0)
            $fatal(1, "TIMER_STATUS FAILED: status not cleared");

        $display("[PASS] IRQ clear");


        $display("");
        $display("================================");
        $display("       TIMER TEST PASSED");
        $display("================================");

        $finish;
    end

endmodule
