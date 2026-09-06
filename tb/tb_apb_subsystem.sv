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

    // GPIO
    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_oe;

    // UART loopback exercises the subsystem RX/TX ports.
    wire uart_tx;
    wire uart_rx = uart_tx;
    wire uart_irq;

    // Interrupts
    logic        gpio_irq;
    logic        timer_irq;

    logic [31:0] read_data;

    // Scoreboard && randomization
    logic [7:0]  model_gpio_data;
    logic [7:0]  model_gpio_dir;
    logic [31:0] model_timer_load;

    logic [31:0] rand_data;

    integer i;
    integer reg_sel;
    integer operation;

    // Coverage
    integer cov_gpio_data_rd;
    integer cov_gpio_data_wr;

    integer cov_gpio_dir_rd;
    integer cov_gpio_dir_wr;

    integer cov_gpio_input_rd;
    integer cov_gpio_input_wr;

    integer cov_timer_load_rd;
    integer cov_timer_load_wr;

    integer cov_timer_value_rd;
    integer cov_timer_value_wr;

    integer cov_timer_status_rd;
    integer cov_timer_status_wr;

    integer cov_invalid_addr;

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

        .gpio_irq  (gpio_irq),
        .timer_irq (timer_irq),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .uart_irq  (uart_irq)
    );

    // APB protocol checker
    apb_assertions apb_checker (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),

        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PADDR    (PADDR),
        .PWDATA   (PWDATA),

        .PREADY   (PREADY),
        .PSLVERR  (PSLVERR)
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

        @(negedge PCLK);
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

        if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
            $fatal(1, "Unexpected APB response at %h", addr);

        sample_coverage(addr, 1'b1);

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

        if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
            $fatal(1, "Unexpected APB response at %h", addr);

        sample_coverage(addr, 1'b0);

        @(negedge PCLK);

        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PADDR   = 32'h0;
    end
    endtask

    // APB READ ERROR
    task apb_read_error(
        input logic [31:0] addr
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

        if (PREADY !== 1'b1)
            $fatal(1, "Expected PREADY for invalid address");

        if (PSLVERR !== 1'b1)
            $fatal(1, "Expected PSLVERR for invalid address");
        if (PRDATA !== 32'd0)
            $fatal(1, "Invalid read must return zero");
        sample_coverage(addr, 1'b0);

        @(negedge PCLK);

        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PADDR   = 32'h0;
    end
    endtask

    // Randomized test
    task random_test;
    begin

        $display("");
        $display("Starting randomized verification...");

        // Start from known state
        reset_dut();

        model_gpio_data = 8'h00;
        model_gpio_dir  = 8'h00;
        model_timer_load = 32'h0000_0000;

        gpio_in = 8'h00;

        for (i = 0; i < 100; i = i + 1) begin

            operation = $urandom_range(0, 1);
            reg_sel   = $urandom_range(0, 5);
            rand_data = $urandom;

            // Randomize external GPIO input
            @(negedge PCLK);
            gpio_in = $urandom;
            repeat (3) @(negedge PCLK);


            // WRITE
            if (operation == 1) begin

                case (reg_sel)

                    // GPIO_DATA
                    0: begin
                        apb_write(
                            32'h0000_0000,
                            rand_data
                        );

                        model_gpio_data = rand_data[7:0];

                        if (gpio_out !== model_gpio_data)
                            $fatal(
                                1,
                                "Random GPIO_DATA mismatch"
                            );
                    end


                    // GPIO_DIR
                    1: begin
                        apb_write(
                            32'h0000_0004,
                            rand_data
                        );

                        model_gpio_dir = rand_data[7:0];

                        if (gpio_oe !== model_gpio_dir)
                            $fatal(
                                1,
                                "Random GPIO_DIR mismatch"
                            );
                    end


                    // GPIO_INPUT is read-only
                    2: begin
                        apb_write(
                            32'h0000_0008,
                            rand_data
                        );

                        apb_read(
                            32'h0000_0008,
                            read_data
                        );

                        if (read_data !== {24'h0, gpio_in})
                            $fatal(
                                1,
                                "GPIO_INPUT modified by random write"
                            );
                    end


                    // TIMER_LOAD
                    3: begin
                        apb_write(
                            32'h0000_0104,
                            rand_data
                        );

                        model_timer_load = rand_data;
                    end


                    // TIMER_VALUE is read-only
                    4: begin
                        apb_write(
                            32'h0000_0108,
                            rand_data
                        );

                        apb_read(
                            32'h0000_0108,
                            read_data
                        );

                        if (read_data !== model_timer_load)
                            $fatal(
                                1,
                                "TIMER_VALUE modified by random write"
                            );
                    end


                    // TIMER_STATUS is read-only
                    5: begin
                        apb_write(
                            32'h0000_010C,
                            rand_data
                        );

                        apb_read(
                            32'h0000_010C,
                            read_data
                        );

                        if (read_data[0] !== 1'b0)
                            $fatal(
                                1,
                                "TIMER_STATUS modified by random write"
                            );
                    end

                endcase

            end


            // READ
            else begin

                case (reg_sel)

                    0: begin
                        apb_read(
                            32'h0000_0000,
                            read_data
                        );

                        if (read_data !== {24'h0, model_gpio_data})
                            $fatal(
                                1,
                                "Random GPIO_DATA read mismatch"
                            );
                    end


                    1: begin
                        apb_read(
                            32'h0000_0004,
                            read_data
                        );

                        if (read_data !== {24'h0, model_gpio_dir})
                            $fatal(
                                1,
                                "Random GPIO_DIR read mismatch"
                            );
                    end


                    2: begin
                        apb_read(
                            32'h0000_0008,
                            read_data
                        );

                        if (read_data !== {24'h0, gpio_in})
                            $fatal(
                                1,
                                "Random GPIO_INPUT read mismatch"
                            );
                    end


                    3: begin
                        apb_read(
                            32'h0000_0104,
                            read_data
                        );

                        if (read_data !== model_timer_load)
                            $fatal(
                                1,
                                "Random TIMER_LOAD read mismatch"
                            );
                    end


                    4: begin
                        apb_read(
                            32'h0000_0108,
                            read_data
                        );

                        if (read_data !== model_timer_load)
                            $fatal(
                                1,
                                "Random TIMER_VALUE read mismatch"
                            );
                    end


                    5: begin
                        apb_read(
                            32'h0000_010C,
                            read_data
                        );

                        if (read_data[0] !== 1'b0)
                            $fatal(
                                1,
                                "Random TIMER_STATUS mismatch"
                            );
                    end

                endcase

            end
        end

        $display("[PASS] 100 randomized APB transactions");

    end
    endtask

    // Functional coverage
    task sample_coverage(
        input logic [31:0] addr,
        input logic        write
    );
    begin

        case (addr)

            32'h0000_0000: begin
                if (write)
                    cov_gpio_data_wr++;
                else
                    cov_gpio_data_rd++;
            end

            32'h0000_0004: begin
                if (write)
                    cov_gpio_dir_wr++;
                else
                    cov_gpio_dir_rd++;
            end

            32'h0000_0008: begin
                if (write)
                    cov_gpio_input_wr++;
                else
                    cov_gpio_input_rd++;
            end

            32'h0000_0104: begin
                if (write)
                    cov_timer_load_wr++;
                else
                    cov_timer_load_rd++;
            end

            32'h0000_0108: begin
                if (write)
                    cov_timer_value_wr++;
                else
                    cov_timer_value_rd++;
            end

            32'h0000_010C: begin
                if (write)
                    cov_timer_status_wr++;
                else
                    cov_timer_status_rd++;
            end

            default: begin
                if (addr[15:8] != 8'h00 && addr[15:8] != 8'h01 && addr[15:8] != 8'h02)
                    cov_invalid_addr++;
            end

        endcase

    end
    endtask

    task reset_coverage;
    begin
        cov_gpio_data_rd    = 0;
        cov_gpio_data_wr    = 0;

        cov_gpio_dir_rd     = 0;
        cov_gpio_dir_wr     = 0;

        cov_gpio_input_rd   = 0;
        cov_gpio_input_wr   = 0;

        cov_timer_load_rd   = 0;
        cov_timer_load_wr   = 0;

        cov_timer_value_rd  = 0;
        cov_timer_value_wr  = 0;

        cov_timer_status_rd = 0;
        cov_timer_status_wr = 0;

        cov_invalid_addr    = 0;
    end
    endtask

    // Coverage report
    task report_coverage;

        integer hit_bins;
        integer total_bins;

    begin

        hit_bins   = 0;
        total_bins = 12;

        if (cov_gpio_data_rd    > 0) hit_bins++;
        if (cov_gpio_data_wr    > 0) hit_bins++;

        if (cov_gpio_dir_rd     > 0) hit_bins++;
        if (cov_gpio_dir_wr     > 0) hit_bins++;

        if (cov_gpio_input_rd   > 0) hit_bins++;
        if (cov_gpio_input_wr   > 0) hit_bins++;

        if (cov_timer_load_rd   > 0) hit_bins++;
        if (cov_timer_load_wr   > 0) hit_bins++;

        if (cov_timer_value_rd  > 0) hit_bins++;
        if (cov_timer_value_wr  > 0) hit_bins++;

        if (cov_timer_status_rd > 0) hit_bins++;
        if (cov_timer_status_wr > 0) hit_bins++;


        $display("");
        $display("===== ACCESS COVERAGE (6 REGISTERS) =====");

        $display("GPIO_DATA   RD=%0d WR=%0d",
                cov_gpio_data_rd,
                cov_gpio_data_wr);

        $display("GPIO_DIR    RD=%0d WR=%0d",
                cov_gpio_dir_rd,
                cov_gpio_dir_wr);

        $display("GPIO_INPUT  RD=%0d WR=%0d",
                cov_gpio_input_rd,
                cov_gpio_input_wr);

        $display("TIMER_LOAD  RD=%0d WR=%0d",
                cov_timer_load_rd,
                cov_timer_load_wr);

        $display("TIMER_VALUE RD=%0d WR=%0d",
                cov_timer_value_rd,
                cov_timer_value_wr);

        $display("TIMER_STATUS RD=%0d WR=%0d",
                cov_timer_status_rd,
                cov_timer_status_wr);

        $display("Invalid address accesses = %0d",
                cov_invalid_addr);

        $display(
            "Register access coverage = %0d/%0d bins",
            hit_bins,
            total_bins
        );

        $display("=======================================");

    end
    endtask

    task check_reg(input logic [31:0] addr, input logic [31:0] expected);
        logic [31:0] actual;
        begin
            apb_read(addr, actual);
            if (actual !== expected)
                $fatal(1, "Register %h: expected %h, got %h", addr, expected, actual);
        end
    endtask

    task apb_write_error(input logic [31:0] addr);
        begin
            @(negedge PCLK);
            PSEL = 1;
            PENABLE = 0;
            PWRITE = 1;
            PADDR = addr;
            PWDATA = 32'hFFFF_FFFF;
            @(negedge PCLK);
            PENABLE = 1;
            @(posedge PCLK);
            if (PREADY !== 1'b1 || PSLVERR !== 1'b1)
                $fatal(1, "Expected write error at %h", addr);
            sample_coverage(addr, 1'b1);
            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
            PWRITE = 0;
            PADDR = 0;
            PWDATA = 0;
        end
    endtask

    task directed_test;
        begin
            if (gpio_out !== 8'd0 || gpio_oe !== 8'd0 ||
                gpio_irq !== 1'b0 || timer_irq !== 1'b0 || uart_irq !== 1'b0 || uart_tx !== 1'b1)
                $fatal(1, "Subsystem reset failed");
            check_reg(32'h0000, 32'd0);
            check_reg(32'h0100, 32'd0);

            apb_write(32'h0000, 32'h5A);
            apb_write(32'h0004, 32'h0F);
            apb_write(32'h0104, 32'd8);
            apb_write(32'h0110, 32'd3);
            check_reg(32'h0000, 32'h5A);
            check_reg(32'h0004, 32'h0F);
            check_reg(32'h0104, 32'd8);
            check_reg(32'h0108, 32'd8);
            check_reg(32'h0110, 32'd3);
            if (gpio_out !== 8'h5A || gpio_oe !== 8'h0F)
                $fatal(1, "Timer writes corrupted GPIO outputs");
            $display("[PASS] Register routing and peripheral isolation");

            // GPIO event remains pending while the timer runs.
            apb_write(32'h0010, 32'd1);
            apb_write(32'h000C, 32'd1);
            @(negedge PCLK);
            gpio_in = 8'h01;
            repeat (3) @(negedge PCLK);
            check_reg(32'h0008, 32'd1);
            check_reg(32'h0014, 32'd1);
            if (gpio_irq !== 1'b1 || timer_irq !== 1'b0)
                $fatal(1, "GPIO IRQ routing failed");

            apb_write(32'h0100, 32'd1);
            wait (timer_irq === 1'b1);
            check_reg(32'h0108, 32'd0);
            check_reg(32'h0100, 32'd0);
            check_reg(32'h010C, 32'd1);
            if (gpio_irq !== 1'b1)
                $fatal(1, "Timer operation changed GPIO IRQ");

            apb_write(32'h0114, 32'd1);
            if (timer_irq !== 1'b0 || gpio_irq !== 1'b1)
                $fatal(1, "Timer IRQ clear isolation failed");
            check_reg(32'h010C, 32'd0);
            check_reg(32'h0014, 32'd1);
            apb_write(32'h0018, 32'd1);
            if (gpio_irq !== 1'b0 || timer_irq !== 1'b0)
                $fatal(1, "GPIO IRQ clear routing failed");
            check_reg(32'h0014, 32'd0);
            $display("[PASS] Timer expiration and independent IRQ routing/clear");

            // UART page routing, full frame loopback and independent IRQs.
            check_reg(32'h020C, 0);
            check_reg(32'h0210, 868);
            check_reg(32'h0214, 0);
            apb_write(32'h0210, 16);
            apb_write(32'h020C, 15);
            check_reg(32'h020C, 15);
            check_reg(32'hABCD_0210, 16);
            check_reg(32'h0010, 1); // UART BAUD must not overwrite GPIO type.
            check_reg(32'h0110, 3); // Nor TIMER_PRESCALE.

            // Keep GPIO and timer IRQs pending during UART activity.
            @(negedge PCLK);
            gpio_in = 0;
            repeat (4) @(negedge PCLK);
            gpio_in = 1;
            apb_write(32'h0104, 8);
            apb_write(32'h0100, 1);
            apb_write(32'h0200, 8'hA6);
            repeat (180) @(negedge PCLK);
            check_reg(32'h0214, 3); // RX valid and TX done.
            if (uart_irq !== 1 || gpio_irq !== 1 || timer_irq !== 1)
                $fatal(1, "Three independent IRQs must be asserted");
            apb_write(32'h0218, 2);
            check_reg(32'h0214, 1);
            if (uart_irq !== 1)
                $fatal(1, "RX pending must keep UART IRQ asserted");
            check_reg(32'h0204, 8'hA6);
            check_reg(32'h0214, 0);
            if (uart_irq !== 0 || gpio_irq !== 1 || timer_irq !== 1)
                $fatal(1, "UART IRQ clear isolation failed");
            apb_write(32'h0018, 1);
            apb_write(32'h0114, 1);
            if (gpio_irq !== 0 || timer_irq !== 0)
                $fatal(1, "GPIO/timer clear after UART activity failed");
            check_reg(32'h0000, 32'h5A);
            check_reg(32'h0004, 32'h0F);
            check_reg(32'h0104, 8);
            apb_write(32'h02FC, 32'hFFFFFFFF);
            check_reg(32'h02FC, 0);
            check_reg(32'h020C, 15);
            $display("[PASS] UART loopback, page isolation and independent IRQ clear");

            apb_read_error(32'h0300);
            apb_write_error(32'h0304);
            apb_read_error(32'hFFFF_FF00);
            apb_write_error(32'hFFFF_FF00);
            check_reg(32'h0000, 32'h5A);
            check_reg(32'h0004, 32'h0F);
            check_reg(32'h0104, 32'd8);
            $display("[PASS] Invalid page read/write errors and isolation");

            // Unimplemented offsets inside a valid page return zero, no error.
            apb_write(32'h00FC, 32'hFFFF_FFFF);
            apb_write(32'h01FC, 32'hFFFF_FFFF);
            check_reg(32'h00FC, 32'd0);
            check_reg(32'h01FC, 32'd0);
            check_reg(32'h0000, 32'h5A);
            check_reg(32'h0104, 32'd8);

            // Current decoder ignores PADDR[31:16]. Document that behavior.
            check_reg(32'hABCD_0000, 32'h5A);
            check_reg(32'hABCD_0104, 32'd8);
            $display("[PASS] Unimplemented offsets and upper-address aliases");

            @(posedge PCLK);
            if (PRDATA !== 32'd0 || PREADY !== 1'b1 || PSLVERR !== 1'b0)
                $fatal(1, "Idle APB response failed");
        end
    endtask

    initial begin
        repeat (10000) @(posedge PCLK);
        $fatal(1, "TIMEOUT: subsystem test did not complete");
    end

    // Test
    initial begin

        reset_dut();

        reset_coverage();

        directed_test();

        random_test();

        report_coverage();

        $display("");
        $display("================================");
        $display("     SUBSYSTEM TEST PASSED");
        $display("================================");

        $finish;
    end

endmodule
