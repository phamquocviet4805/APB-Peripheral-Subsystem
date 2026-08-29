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

    // Reg
    logic        timer_irq;

    logic [31:0] read_data;

    logic [31:0] value_before;

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

        .timer_irq (timer_irq)
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

        if (!PREADY)
            $fatal(1, "Expected PREADY for invalid address");

        if (!PSLVERR)
            $fatal(1, "Expected PSLVERR for invalid address");

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
            gpio_in = $urandom;


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

            default:
                cov_invalid_addr++;

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
        $display("========= FUNCTIONAL COVERAGE =========");

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

    // Test
    initial begin

        reset_dut();

        reset_coverage();

        // // GPIO DATA
        // apb_write(32'h0000_0000, 32'h0000_005A);

        // if (gpio_out !== 8'h5A)
        //     $fatal(1, "GPIO_DATA write failed");

        // apb_read(32'h0000_0000, read_data);

        // if (read_data !== 32'h0000_005A)
        //     $fatal(1, "GPIO_DATA read failed");

        // $display("[PASS] GPIO_DATA");


        // // GPIO DIR
        // apb_write(32'h0000_0004, 32'h0000_000F);

        // if (gpio_oe !== 8'h0F)
        //     $fatal(1, "GPIO_DIR write failed");

        // $display("[PASS] GPIO_DIR");


        // // GPIO INPUT
        // gpio_in = 8'hA5;

        // apb_read(32'h0000_0008, read_data);

        // if (read_data !== 32'h0000_00A5)
        //     $fatal(1, "GPIO_INPUT read failed");

        // $display("[PASS] GPIO_INPUT");


        // // TIMER LOAD
        // apb_write(32'h0000_0104, 32'd5);

        // apb_read(32'h0000_0104, read_data);

        // if (read_data !== 32'd5)
        //     $fatal(1, "TIMER_LOAD failed");

        // $display("[PASS] TIMER_LOAD");


        // // Check GPIO not affected by Timer access
        // if (gpio_out !== 8'h5A)
        //     $fatal(1, "Timer access corrupted GPIO");

        // if (gpio_oe !== 8'h0F)
        //     $fatal(1, "Timer access corrupted GPIO_DIR");

        // $display("[PASS] Address isolation");


        // // Enable Timer
        // apb_write(32'h0000_0100, 32'd1);

        // wait (timer_irq == 1'b1);

        // apb_read(32'h0000_0108, read_data);

        // if (read_data !== 32'd0)
        //     $fatal(1, "Timer did not reach zero");

        // $display("[PASS] Timer countdown");


        // // Timer STATUS
        // apb_read(32'h0000_010C, read_data);

        // if (read_data[0] !== 1'b1)
        //     $fatal(1, "Timer IRQ status failed");

        // $display("[PASS] TIMER_STATUS");

        // // Invalid address
        // apb_read_error(32'h0000_0200);

        // $display("[PASS] Invalid address PSLVERR");

        // // GPIO_INPUT is read-only
        // apb_write(32'h0000_0008, 32'h0000_0055);
        // apb_read(32'h0000_0008, read_data);

        // if (read_data !== 32'h0000_00A5)
        //     $fatal(1, "GPIO_INPUT RO register was modified");

        // $display("[PASS] GPIO_INPUT is read-only");

        // TIMER_VALUE is read-only
        // apb_read(32'h0000_0108, read_data);
        // value_before = read_data;

        // apb_write(
        //     32'h0000_0108,
        //     32'hDEAD_BEEF
        // );

        // apb_read(
        //     32'h0000_0108,
        //     read_data
        // );

        // if (read_data !== value_before)
        //     $fatal(1, "TIMER_VALUE RO register was modified");

        // $display("[PASS] TIMER_VALUE is read-only");

        // apb_write(32'h0000_0104, 32'd10);

        // apb_write(
        //     32'h0000_0000,
        //     32'h0000_00AA
        // );

        // apb_read(
        //     32'h0000_0104,
        //     read_data
        // );

        // if (read_data !== 32'd10)
        //     $fatal(1, "GPIO access corrupted TIMER_LOAD");

        // $display("[PASS] Peripheral isolation");

        random_test();

        report_coverage();

        $display("");
        $display("================================");
        $display("     SUBSYSTEM TEST PASSED");
        $display("================================");

        $finish;
    end

endmodule
