# APB Peripheral Subsystem

A synthesizable SystemVerilog subsystem with GPIO, a timer, and an 8N1 UART
on a shared APB interface.

[Architecture and block diagram](docs/architecture.md) · [Register reference](docs/register_map.md)

## Overview

| Peripheral | Main capabilities | Address range |
|---|---|---|
| GPIO | 8 pins, synchronized inputs, configurable edge interrupts | `0x0000–0x00FF` |
| Timer | 32-bit counter, 16-bit prescaler, one-shot and periodic modes | `0x0100–0x01FF` |
| UART | TX/RX, programmable baud divider, overrun and frame-error status | `0x0200–0x02FF` |

The APB interface uses 32-bit addresses and data with zero wait states.
Each peripheral has an independent interrupt output. The decoder uses
`PADDR[15:8]`; bits `[31:16]` are ignored. Unmapped pages return `PSLVERR`
during ACCESS.

## Quick start

With GNU Make and Icarus Verilog installed, run the subsystem test:

```sh
make sim_subsystem
```

The test checks peripheral routing, UART loopback, independent interrupts,
invalid addresses, and randomized GPIO/timer accesses. View the waveform
with GTKWave:

```sh
gtkwave waves/apb_subsystem.vcd
```

## Build and verification

| Command | Purpose | Required tools |
|---|---|---|
| `make sim_gpio` | GPIO simulation | Icarus Verilog |
| `make sim_timer` | Timer simulation | Icarus Verilog |
| `make sim_uart` | UART simulation | Icarus Verilog |
| `make sim_subsystem` | Subsystem simulation with APB protocol checks | Icarus Verilog |
| `make lint` | RTL lint | Verilator |
| `make synth` | Synthesize the subsystem | Yosys |
| `make stdcell_map` | Map to Nangate45 standard cells | Yosys, Nangate45 library |
| `make sta` | Map and report setup/hold timing | Mapping tools, OpenSTA |
| `make regression` | Run all simulations and the implementation flow | All tools above |

All commands use GNU Make. GTKWave is optional for waveform inspection.

| Output directory | Contents |
|---|---|
| `waves/` | Simulation waveforms (`.vcd`) |
| `build/` | Simulation executables and generated netlists |
| `reports/` | Timing report (`sta.log`) |

**Timing scope:** STA analyzes a mapped netlist before physical implementation.
The target does not fail on negative slack. Inspect both setup and hold
reports; a successful command exit does not establish timing closure.

## Repository guide

| Path | Contents |
|---|---|
| `rtl/` | Peripheral RTL and subsystem integration |
| `tb/` | Testbenches and APB protocol checker |
| `sim/` | Simulation filelists |
| `constraints/` | Subsystem timing constraints |
| `scripts/` | STA script |
| [docs/architecture.md](docs/architecture.md) | Block diagram, interfaces, and operating behavior |
| [docs/register_map.md](docs/register_map.md) | Register offsets, bit fields, and software side effects |
