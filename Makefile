.PHONY: compile_gpio sim_gpio compile_timer sim_timer clean

compile_gpio:
	mkdir -p build
	iverilog \
		-g2012 \
		-Wall \
		-s apb_gpio \
		-o build/apb_gpio_check \
		rtl/apb_gpio.sv

sim_gpio:
	mkdir -p build waves
	iverilog \
		-g2012 \
		-Wall \
		-s tb_apb_gpio \
		-o build/tb_apb_gpio \
		-f sim/filelist_gpio.f
	vvp build/tb_apb_gpio


compile_timer:
	mkdir -p build
	iverilog \
		-g2012 \
		-Wall \
		-s apb_timer \
		-o build/apb_timer_check \
		rtl/apb_timer.sv

sim_timer:
	mkdir -p build waves
	iverilog \
		-g2012 \
		-Wall \
		-s tb_apb_timer \
		-o build/tb_apb_timer \
		-f sim/filelist_timer.f
	vvp build/tb_apb_timer

compile_subsystem:
	mkdir -p build
	iverilog \
		-g2012 \
		-Wall \
		-s apb_subsystem \
		-o build/apb_subsystem_check \
		rtl/apb_gpio.sv \
		rtl/apb_timer.sv \
		rtl/apb_subsystem.sv

sim_subsystem:
	mkdir -p build waves
	iverilog \
		-g2012 \
		-Wall \
		-s tb_apb_subsystem \
		-o build/tb_apb_subsystem \
		-f sim/filelist_subsystem.f
	vvp build/tb_apb_subsystem

clean:
	rm -rf build waves
