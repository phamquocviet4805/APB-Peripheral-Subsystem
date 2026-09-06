module tb_uart_rx;

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
    logic        rx;
    logic [15:0] baud_div;

    logic [7:0]  data_out;
    logic        valid;
    logic        frame_error;


    // ============================================================
    // Testbench monitors
    // ============================================================

    integer valid_count;
    integer frame_error_count;

    logic [7:0] captured_data;


    // ============================================================
    // DUT
    // ============================================================

    uart_rx dut (
        .PCLK        (PCLK),
        .PRESETn     (PRESETn),

        .enable      (enable),
        .rx          (rx),
        .baud_div    (baud_div),

        .data_out    (data_out),
        .valid       (valid),
        .frame_error (frame_error)
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
        $dumpfile("waves/uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
    end


    // ============================================================
    // Monitor one-cycle pulses
    // ============================================================

    always @(posedge PCLK) begin

        if (valid) begin
            valid_count   <= valid_count + 1;
            captured_data <= data_out;
        end

        if (frame_error) begin
            frame_error_count <= frame_error_count + 1;
        end

    end


    // ============================================================
    // Reset
    // ============================================================

    task reset_dut;
    begin

        PRESETn = 1'b0;

        enable   = 1'b0;
        rx       = 1'b1;
        baud_div = BAUD_DIV;

        valid_count       = 0;
        frame_error_count = 0;
        captured_data     = 8'h00;

        repeat (2) @(posedge PCLK);

        @(negedge PCLK);
        PRESETn = 1'b1;

        @(posedge PCLK);

    end
    endtask


    // ============================================================
    // Drive one UART bit
    // ============================================================

    task drive_uart_bit(
        input logic bit_value
    );
    begin

        @(negedge PCLK);

        rx = bit_value;

        repeat (BAUD_DIV)
            @(posedge PCLK);

    end
    endtask


    // ============================================================
    // Send valid UART frame
    //
    // 8-N-1:
    // start = 0
    // data  = LSB first
    // stop  = 1
    // ============================================================

    task send_uart_byte(
        input logic [7:0] data
    );

        integer i;

    begin

        // Start bit
        drive_uart_bit(1'b0);

        // 8 data bits, LSB first
        for (i = 0; i < 8; i = i + 1)
            drive_uart_bit(data[i]);

        // Stop bit
        drive_uart_bit(1'b1);

        // Return line to idle
        rx = 1'b1;

    end
    endtask


    // ============================================================
    // Send UART frame with invalid stop bit
    // ============================================================

    task send_bad_stop_frame(
        input logic [7:0] data
    );

        integer i;

    begin

        // Start bit
        drive_uart_bit(1'b0);

        // Data bits
        for (i = 0; i < 8; i = i + 1)
            drive_uart_bit(data[i]);

        // Invalid stop bit
        drive_uart_bit(1'b0);

        // Return to idle
        @(negedge PCLK);
        rx = 1'b1;

    end
    endtask


    // ============================================================
    // Main test
    // ============================================================

    integer old_valid_count;
    integer old_error_count;

    initial begin

        reset_dut();


        // ========================================================
        // TEST 1: RESET / IDLE
        // ========================================================

        if (valid !== 1'b0)
            $fatal(
                1,
                "RESET FAILED: valid should be 0"
            );

        if (frame_error !== 1'b0)
            $fatal(
                1,
                "RESET FAILED: frame_error should be 0"
            );

        $display("[PASS] UART RX reset");


        // ========================================================
        // TEST 2: RECEIVE BYTE
        // ========================================================

        enable = 1'b1;

        old_valid_count = valid_count;

        send_uart_byte(8'hA5);

        // Give monitor time to observe valid pulse
        repeat (3)
            @(posedge PCLK);

        if (valid_count !== old_valid_count + 1)
            $fatal(
                1,
                "RX FAILED: valid pulse not generated"
            );

        if (captured_data !== 8'hA5)
            $fatal(
                1,
                "RX DATA FAILED: expected 0xA5 got 0x%02h",
                captured_data
            );

        $display(
            "[PASS] UART RX received 0x%02h",
            captured_data
        );


        // ========================================================
        // TEST 3: SECOND BYTE
        // ========================================================

        old_valid_count = valid_count;

        send_uart_byte(8'h3C);

        repeat (3)
            @(posedge PCLK);

        if (valid_count !== old_valid_count + 1)
            $fatal(
                1,
                "RX FAILED: second valid pulse not generated"
            );

        if (captured_data !== 8'h3C)
            $fatal(
                1,
                "RX DATA FAILED: expected 0x3C got 0x%02h",
                captured_data
            );

        $display(
            "[PASS] UART RX received second byte 0x%02h",
            captured_data
        );


        // ========================================================
        // TEST 4: FRAME ERROR
        // ========================================================

        old_error_count = frame_error_count;

        send_bad_stop_frame(8'h55);

        repeat (3)
            @(posedge PCLK);

        if (frame_error_count !== old_error_count + 1)
            $fatal(
                1,
                "FRAME ERROR FAILED: frame_error pulse not generated"
            );

        $display("[PASS] UART RX frame error detection");


        // ========================================================
        // TEST 5: VALID IS ONE-CYCLE PULSE
        // ========================================================

        repeat (2)
            @(posedge PCLK);

        if (valid !== 1'b0)
            $fatal(
                1,
                "VALID FAILED: valid should only pulse for one cycle"
            );

        if (frame_error !== 1'b0)
            $fatal(
                1,
                "FRAME ERROR FAILED: frame_error should only pulse for one cycle"
            );

        $display("[PASS] RX pulse behavior");


        // ========================================================
        // DONE
        // ========================================================

        $display("");
        $display("================================");
        $display("        UART RX TEST PASSED");
        $display("================================");

        $finish;

    end

endmodule
