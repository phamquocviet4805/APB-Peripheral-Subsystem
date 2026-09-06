module tb_uart_tx;

    // ============================================================
    // Parameters
    // ============================================================

    localparam [15:0] BAUD_DIV = 16'd8;


    // ============================================================
    // Signals
    // ============================================================

    logic        PCLK;
    logic        PRESETn;

    logic        enable;
    logic        start;
    logic [7:0]  data_in;
    logic [15:0] baud_div;

    logic        tx;
    logic        busy;
    logic        done;


    // ============================================================
    // DUT
    // ============================================================

    uart_tx dut (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),

        .enable   (enable),
        .start    (start),
        .data_in  (data_in),
        .baud_div (baud_div),

        .tx       (tx),
        .busy     (busy),
        .done     (done)
    );


    // ============================================================
    // Clock
    // ============================================================

    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end


    // ============================================================
    // Waveform
    // ============================================================

    initial begin
        $dumpfile("waves/uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end


    // ============================================================
    // Reset
    // ============================================================

    task reset_dut;
    begin

        PRESETn = 1'b0;

        enable   = 1'b0;
        start    = 1'b0;
        data_in  = 8'h00;
        baud_div = BAUD_DIV;

        repeat (2) @(posedge PCLK);

        @(negedge PCLK);
        PRESETn = 1'b1;

        @(posedge PCLK);

    end
    endtask


    // ============================================================
    // Start transmission
    // ============================================================

    task start_tx(
        input logic [7:0] data
    );
    begin

        @(negedge PCLK);

        data_in = data;
        start   = 1'b1;

        @(negedge PCLK);

        start = 1'b0;

    end
    endtask


    // ============================================================
    // Main test
    // ============================================================

    integer i;
    logic [7:0] test_data;

    initial begin

        reset_dut();


        // ========================================================
        // TEST 1: RESET / IDLE
        // ========================================================

        if (tx !== 1'b1)
            $fatal(
                1,
                "RESET FAILED: TX should be idle-high"
            );

        if (busy !== 1'b0)
            $fatal(
                1,
                "RESET FAILED: busy should be 0"
            );

        if (done !== 1'b0)
            $fatal(
                1,
                "RESET FAILED: done should be 0"
            );

        $display("[PASS] UART TX reset");


        // ========================================================
        // TEST 2: TRANSMIT BYTE
        // ========================================================

        enable    = 1'b1;
        test_data = 8'hA5;

        start_tx(test_data);

        wait (busy == 1'b1);

        if (tx !== 1'b0)
            $fatal(
                1,
                "START BIT FAILED: expected TX=0"
            );

        $display("[PASS] Start bit");


        // ========================================================
        // Sample middle of start bit
        // ========================================================

        repeat (BAUD_DIV / 2)
            @(negedge PCLK);

        if (tx !== 1'b0)
            $fatal(
                1,
                "START BIT FAILED: TX changed too early"
            );


        // ========================================================
        // TEST DATA BITS
        //
        // UART sends LSB first
        // ========================================================

        for (i = 0; i < 8; i = i + 1) begin

            repeat (BAUD_DIV)
                @(negedge PCLK);

            if (tx !== test_data[i])
                $fatal(
                    1,
                    "DATA BIT FAILED: bit %0d expected %0b got %0b",
                    i,
                    test_data[i],
                    tx
                );

            $display(
                "[PASS] TX data bit %0d = %0b",
                i,
                tx
            );

        end


        // ========================================================
        // TEST STOP BIT
        // ========================================================

        repeat (BAUD_DIV)
            @(negedge PCLK);

        if (tx !== 1'b1)
            $fatal(
                1,
                "STOP BIT FAILED: expected TX=1"
            );

        $display("[PASS] Stop bit");


        // ========================================================
        // TEST DONE
        // ========================================================

        wait (done == 1'b1);

        if (busy !== 1'b0)
            $fatal(
                1,
                "DONE FAILED: busy should be 0"
            );

        if (tx !== 1'b1)
            $fatal(
                1,
                "DONE FAILED: TX should return idle-high"
            );

        $display("[PASS] TX done");


        // done should only be one PCLK pulse
        @(posedge PCLK);
        @(negedge PCLK);

        if (done !== 1'b0)
            $fatal(
                1,
                "DONE FAILED: done should be a one-cycle pulse"
            );

        $display("[PASS] Done pulse");


        // ========================================================
        // DONE
        // ========================================================

        $display("");
        $display("================================");
        $display("        UART TX TEST PASSED");
        $display("================================");

        $finish;

    end

endmodule
