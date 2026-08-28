module apb_assertions (
    input logic        PCLK,
    input logic        PRESETn,

    input logic        PSEL,
    input logic        PENABLE,
    input logic        PWRITE,
    input logic [31:0] PADDR,
    input logic [31:0] PWDATA,

    input logic        PREADY,
    input logic        PSLVERR
);

    logic        prev_psel;
    logic        prev_penable;
    logic        prev_pwrite;
    logic        prev_pready;
    logic [31:0] prev_paddr;
    logic [31:0] prev_pwdata;


    always @(posedge PCLK or negedge PRESETn) begin

        if (!PRESETn) begin
            prev_psel    <= 1'b0;
            prev_penable <= 1'b0;
            prev_pwrite  <= 1'b0;
            prev_pready  <= 1'b0;
            prev_paddr   <= 32'h0;
            prev_pwdata  <= 32'h0;
        end

        else begin

            // PENABLE can only be high when PSEL is high
            if (PENABLE && !PSEL)
                $fatal(
                    1,
                    "APB ERROR: PENABLE=1 while PSEL=0"
                );


            // SETUP must be followed by ACCESS
            if (prev_psel && !prev_penable) begin

                if (!(PSEL && PENABLE))
                    $fatal(
                        1,
                        "APB ERROR: SETUP not followed by ACCESS"
                    );

            end


            // Address/control must stay stable from SETUP to ACCESS
            if (prev_psel && !prev_penable &&
                PSEL && PENABLE) begin

                if (PADDR !== prev_paddr)
                    $fatal(
                        1,
                        "APB ERROR: PADDR changed from SETUP to ACCESS"
                    );

                if (PWRITE !== prev_pwrite)
                    $fatal(
                        1,
                        "APB ERROR: PWRITE changed from SETUP to ACCESS"
                    );

                if (PWRITE && (PWDATA !== prev_pwdata))
                    $fatal(
                        1,
                        "APB ERROR: PWDATA changed from SETUP to ACCESS"
                    );

            end


            // During wait state, transfer signals must remain stable
            if (prev_psel &&
                prev_penable &&
                !prev_pready) begin

                if (!(PSEL && PENABLE))
                    $fatal(
                        1,
                        "APB ERROR: ACCESS terminated while PREADY=0"
                    );

                if (PADDR !== prev_paddr)
                    $fatal(
                        1,
                        "APB ERROR: PADDR changed during wait state"
                    );

                if (PWRITE !== prev_pwrite)
                    $fatal(
                        1,
                        "APB ERROR: PWRITE changed during wait state"
                    );

                if (prev_pwrite &&
                    (PWDATA !== prev_pwdata))
                    $fatal(
                        1,
                        "APB ERROR: PWDATA changed during wait state"
                    );

            end


            // PSLVERR is only meaningful when transfer completes
            if (PSLVERR) begin

                if (!(PSEL && PENABLE && PREADY))
                    $fatal(
                        1,
                        "APB ERROR: PSLVERR asserted outside transfer completion"
                    );

            end


            prev_psel    <= PSEL;
            prev_penable <= PENABLE;
            prev_pwrite  <= PWRITE;
            prev_pready  <= PREADY;
            prev_paddr   <= PADDR;
            prev_pwdata  <= PWDATA;

        end
    end

endmodule
