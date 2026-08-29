# 100 MHz clock
create_clock -name PCLK -period 10.0 [get_ports PCLK]

# Giả sử clock có 0.1 ns uncertainty
set_clock_uncertainty 0.1 [get_clocks PCLK]

# Giả sử tín hiệu từ APB master tới subsystem
# có thể tới trễ tối đa 1 ns sau cạnh clock
set_input_delay 1.0 -clock PCLK \
    [get_ports {PSEL PENABLE PWRITE PADDR* PWDATA* gpio_in*}]

# Giả sử block nhận phía ngoài yêu cầu output
# valid trước 1 ns
set_output_delay 1.0 -clock PCLK \
    [get_ports {PRDATA* PREADY PSLVERR gpio_out* gpio_oe* timer_irq}]

# Reset asynchronous không check như data path bình thường
set_false_path -from [get_ports PRESETn]