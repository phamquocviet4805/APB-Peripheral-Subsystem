LIB = lib/NangateOpenCellLibrary_typical.lib

.PHONY: sim_gpio sim_timer sim_subsystem lint synth stdcell_map sta regression clean

sim_gpio:
	mkdir -p build waves
	iverilog -g2012 -Wall \
		-s tb_apb_gpio \
		-o build/tb_apb_gpio \
		-f sim/filelist_gpio.f
	vvp build/tb_apb_gpio

sim_timer:
	mkdir -p build waves
	iverilog -g2012 -Wall \
		-s tb_apb_timer \
		-o build/tb_apb_timer \
		-f sim/filelist_timer.f
	vvp build/tb_apb_timer

sim_subsystem:
	mkdir -p build waves
	iverilog -g2012 -Wall \
		-s tb_apb_subsystem \
		-o build/tb_apb_subsystem \
		-f sim/filelist_subsystem.f
	vvp build/tb_apb_subsystem

lint:
	verilator \
		--lint-only \
		-Wall \
		-Wno-fatal \
		--top-module apb_subsystem \
		rtl/apb_gpio.sv \
		rtl/apb_timer.sv \
		rtl/apb_subsystem.sv

synth:
	mkdir -p build
	yosys -p " \
		read_verilog -sv rtl/apb_gpio.sv rtl/apb_timer.sv rtl/apb_subsystem.sv; \
		hierarchy -check -top apb_subsystem; \
		proc; opt; check; stat; \
		write_verilog build/apb_subsystem_netlist.v \
	"

stdcell_map:
	mkdir -p build
	yosys -p " \
		read_verilog -sv rtl/apb_gpio.sv rtl/apb_timer.sv rtl/apb_subsystem.sv; \
		hierarchy -check -top apb_subsystem; \
		proc; opt; flatten; opt; techmap; opt; \
		dfflibmap -liberty $(LIB); \
		abc -liberty $(LIB); \
		clean; \
		stat -liberty $(LIB); \
		write_verilog -noattr build/apb_subsystem_mapped.v \
	"

sta: stdcell_map
	mkdir -p reports
	sta scripts/sta.tcl | tee reports/sta.log

regression:
	$(MAKE) sim_gpio
	$(MAKE) sim_timer
	$(MAKE) sim_subsystem
	$(MAKE) lint
	$(MAKE) synth
	$(MAKE) stdcell_map
	$(MAKE) sta

clean:
	rm -rf build waves reports
