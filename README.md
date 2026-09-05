# APB Peripheral Subsystem

A synthesizable SystemVerilog APB peripheral subsystem containing GPIO
and Timer peripherals.

## Features

- AMBA APB slave interface
- 8-bit GPIO peripheral
- Per-pin GPIO edge interrupts with masking and write-one-to-clear status
- Two-stage GPIO input synchronization
- 32-bit one-shot/periodic timer with a 16-bit prescaler
- Independent GPIO and timer interrupt outputs
- Address decoding
- Read-data and response multiplexing
- Unmapped page detection with PSLVERR
- Self-checking testbench
- Directed and randomized verification
- APB protocol checker
- Register access coverage for six registers
- Verilator lint
- Yosys synthesis
- Nangate45 standard-cell mapping
- OpenSTA setup/hold analysis

## Architecture

See [Architecture](docs/architecture.md) for APB routing, GPIO synchronization,
timer operation, and interrupt integration.

## Address Map

| Range | Peripheral |
|---|---|
| 0x0000_0000 - 0x0000_00FF | GPIO |
| 0x0000_0100 - 0x0000_01FF | Timer |

The decoder uses `PADDR[15:8]`; upper address bits `[31:16]` are ignored.
Unmapped pages return `PSLVERR` during ACCESS. Unimplemented offsets within
valid pages return zero without an error.

See [Register map](docs/register_map.md) for all registers and side effects.

## Run checks

```sh
make sim_gpio
make sim_timer
make sim_subsystem
make regression
```

`regression` runs simulations, lint, synthesis, standard-cell mapping, and
STA. Waveforms are written to `waves/`, netlists to `build/`, and the timing
report to `reports/sta.log`.

STA currently reports violations without failing the Make target. Inspect
both SETUP CHECK and HOLD CHECK; a successful command exit or zero default
WNS/TNS does not establish that hold timing passes. This flow analyzes a
mapped netlist before physical implementation, not a routed design.

## Tools

- Icarus Verilog
- GTKWave
- Verilator
- Yosys
- Nangate45 Open Cell Library
- OpenSTA
- GNU Make
- Git

