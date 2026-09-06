`timescale 1ns/1ps

module tb_apb_uart;
    localparam [7:0] TXDATA = 8'h00, RXDATA = 8'h04,
        STATUS = 8'h08, CTRL = 8'h0c, BAUD = 8'h10,
        INT_STATUS = 8'h14, INT_CLR = 8'h18;
    localparam integer DIV = 16;
    localparam integer BIT_NS = DIV * 10;

    logic PCLK = 0;
    logic PRESETn = 0;
    logic PSEL = 0, PENABLE = 0, PWRITE = 0;
    logic [7:0] PADDR = 0;
    logic [31:0] PWDATA = 0;
    wire [31:0] PRDATA;
    wire PREADY, PSLVERR, uart_tx, uart_irq;
    logic uart_rx = 1;
    integer checks = 0;

    apb_uart dut (.*);
    always #5 PCLK = ~PCLK;

    initial begin
        $dumpfile("waves/apb_uart.vcd");
        $dumpvars(0, tb_apb_uart);
    end

    // A broken DUT must fail instead of hanging the simulation.
    initial begin
        #1000000;
        $fatal(1, "TIMEOUT: tb_apb_uart");
    end

    task automatic check(input logic ok, input string message);
        if (ok !== 1'b1)
            $fatal(1, "%s at %0t", message, $time);
        checks++;
    endtask

    // Drive on falling edges; sample read data before the access clock
    // updates the DUT (RXDATA reads have a side effect).
    task automatic apb_transfer(input logic wr, input logic [7:0] addr,
                                input logic [31:0] data,
                                output logic [31:0] result);
        @(negedge PCLK);
        PSEL = 1; PENABLE = 0; PWRITE = wr;
        PADDR = addr; PWDATA = data;
        @(negedge PCLK);
        PENABLE = 1;
        @(posedge PCLK);
        check(PREADY === 1'b1, "APB must complete without wait states");
        check(PSLVERR === 1'b0, "Unexpected APB error");
        result = PRDATA;
        @(negedge PCLK);
        PSEL = 0; PENABLE = 0; PWRITE = 0;
    endtask

    task automatic write_reg(input logic [7:0] addr,
                             input logic [31:0] data);
        logic [31:0] unused;
        apb_transfer(1, addr, data, unused);
    endtask

    task automatic expect_reg(input logic [7:0] addr,
                              input logic [31:0] expected);
        logic [31:0] actual;
        apb_transfer(0, addr, 0, actual);
        check(actual === expected,
              $sformatf("Register %02h: expected %08h, got %08h",
                        addr, expected, actual));
    endtask

    // External UART source: 8N1, least significant bit first.
    task automatic send_rx(input logic [7:0] data, input logic good_stop);
        @(negedge PCLK);
        uart_rx = 0;
        #(BIT_NS);
        for (integer i = 0; i < 8; i++) begin
            uart_rx = data[i];
            #(BIT_NS);
        end
        uart_rx = good_stop;
        #(BIT_NS);
        uart_rx = 1;
        #(2 * BIT_NS);
    endtask

    // Decode the real TX pin, independently of the DUT's internal state.
    task automatic expect_tx(input logic [7:0] expected);
        @(negedge uart_tx);
        #(BIT_NS / 2);
        check(uart_tx === 0, "TX start bit");
        for (integer i = 0; i < 8; i++) begin
            #(BIT_NS);
            check(uart_tx === expected[i],
                  $sformatf("TX data bit %0d of %02h", i, expected));
        end
        #(BIT_NS);
        check(uart_tx === 1, "TX stop bit");
        #(BIT_NS);
    endtask

    initial begin
        repeat (4) @(negedge PCLK);
        PRESETn = 1;

        $display("[TEST] Reset and register map");
        expect_reg(CTRL, 0);
        expect_reg(BAUD, 868);
        expect_reg(STATUS, 0);
        expect_reg(INT_STATUS, 0);
        expect_reg(RXDATA, 0);
        expect_reg(TXDATA, 0);
        expect_reg(INT_CLR, 0);
        expect_reg(8'hfc, 0);
        check(uart_tx === 1 && uart_irq === 0, "Reset outputs");
        write_reg(BAUD, 32'hffff0010);
        expect_reg(BAUD, DIV);
        write_reg(CTRL, 32'hfffffff0);
        expect_reg(CTRL, 0);
        write_reg(STATUS, 32'hffffffff);
        write_reg(INT_STATUS, 32'hffffffff);
        expect_reg(STATUS, 0);
        expect_reg(INT_STATUS, 0);

        $display("[TEST] Disabled TX/RX ignore traffic");
        write_reg(TXDATA, 8'ha5);
        send_rx(8'h96, 1);
        expect_reg(STATUS, 0);
        expect_reg(INT_STATUS, 0);
        check(uart_tx === 1, "Disabled TX stays idle");

        $display("[TEST] TX frame, busy write ignored, sticky completion and IRQ mask");
        write_reg(CTRL, 1);
        fork
            expect_tx(8'ha5);
            begin
                write_reg(TXDATA, 32'h123456a5);
                expect_reg(STATUS, 1);
                write_reg(TXDATA, 8'h3c); // No TX queue: ignored while busy.
            end
        join
        expect_reg(STATUS, 0);
        expect_reg(INT_STATUS, 2);
        check(uart_irq === 0, "TX pending masked");
        // No delayed second frame may be emitted by the busy write.
        repeat (12 * DIV) begin
            @(negedge PCLK);
            check(uart_tx === 1, "Busy write must not queue another frame");
        end
        write_reg(CTRL, 9);
        check(uart_irq === 1, "Enabling TX IRQ exposes pending completion");
        write_reg(INT_CLR, 0);
        expect_reg(INT_STATUS, 2);
        write_reg(INT_CLR, 2);
        expect_reg(INT_STATUS, 0);
        check(uart_irq === 0, "TX IRQ clear");
        fork
            expect_tx(8'h3c);
            write_reg(TXDATA, 8'h3c);
        join
        check(uart_irq === 1, "Next TX completion raises IRQ again");
        write_reg(INT_CLR, 2);

        $display("[TEST] RX data, IRQ mask and consume-on-read");
        write_reg(CTRL, 2);
        send_rx(8'h96, 1);
        expect_reg(STATUS, 2);
        expect_reg(INT_STATUS, 1);
        check(uart_irq === 0, "RX pending masked");
        write_reg(CTRL, 6);
        check(uart_irq === 1, "RX pending unmasked");
        expect_reg(RXDATA, 8'h96);
        expect_reg(INT_STATUS, 0);
        check(uart_irq === 0, "Reading RXDATA consumes valid byte");

        $display("[TEST] RX overrun preserves the unread byte");
        send_rx(8'h12, 1);
        send_rx(8'h34, 1);
        expect_reg(STATUS, 6);
        expect_reg(INT_STATUS, 5);
        expect_reg(RXDATA, 8'h12);
        expect_reg(INT_STATUS, 4);
        check(uart_irq === 1, "Overrun keeps IRQ asserted after RXDATA read");
        write_reg(INT_CLR, 1); // Clearing valid must preserve overrun.
        expect_reg(INT_STATUS, 4);
        write_reg(INT_CLR, 4);
        check(uart_irq === 0, "Overrun cleared");

        $display("[TEST] Bad stop bit and recovery");
        send_rx(8'hff, 0);
        expect_reg(STATUS, 8);
        expect_reg(INT_STATUS, 8);
        check(uart_irq === 1, "Frame error raises RX IRQ");
        write_reg(INT_CLR, 8);
        expect_reg(INT_STATUS, 0);
        check(uart_irq === 0, "Frame error cleared");
        send_rx(8'h5a, 1);
        expect_reg(RXDATA, 8'h5a);
        expect_reg(STATUS, 0);
        send_rx(8'h00, 1);
        write_reg(INT_CLR, 1);
        expect_reg(INT_STATUS, 0);
        check(uart_irq === 0, "RX valid can also be cleared through INT_CLR");

        $display("[TEST] Full duplex with both interrupt sources pending");
        write_reg(CTRL, 15);
        fork
            expect_tx(8'h81);
            write_reg(TXDATA, 8'h81);
            send_rx(8'h7e, 1);
        join
        expect_reg(INT_STATUS, 3);
        write_reg(INT_CLR, 2);
        expect_reg(INT_STATUS, 1);
        check(uart_irq === 1, "RX keeps shared IRQ high after TX clear");
        expect_reg(RXDATA, 8'h7e);
        check(uart_irq === 0, "Both sources cleared");

        $display("[TEST] Reset clears pending data and configuration");
        send_rx(8'h55, 1);
        check(uart_irq === 1, "Pending RX before reset");
        @(negedge PCLK);
        PRESETn = 0;
        repeat (3) @(negedge PCLK);
        PRESETn = 1;
        expect_reg(CTRL, 0);
        expect_reg(BAUD, 868);
        expect_reg(STATUS, 0);
        expect_reg(INT_STATUS, 0);
        check(uart_irq === 0 && uart_tx === 1, "Outputs after reset");

        $display("PASS: tb_apb_uart (%0d checks)", checks);
        $finish;
    end
endmodule
