# APB Peripheral Subsystem

A synthesizable SystemVerilog APB peripheral subsystem containing GPIO
and Timer peripherals.

## Features

- AMBA APB slave interface
- 8-bit GPIO peripheral
- 32-bit one-shot timer
- Address decoding
- Read-data and response multiplexing
- Invalid address detection with PSLVERR
- Self-checking testbench
- Directed and randomized verification
- APB protocol checker
- Functional coverage
- Verilator lint
- Yosys synthesis
- Nangate45 standard-cell mapping
- OpenSTA setup/hold analysis

## Architecture

APB Master
    |
    v
Address Decoder
    |
    +---- GPIO
    |
    +---- Timer
    |
Response MUX
    |
    v
PRDATA / PREADY / PSLVERR

## Address Map

| Range | Peripheral |
|---|---|
| 0x0000_0000 - 0x0000_00FF | GPIO |
| 0x0000_0100 - 0x0000_01FF | Timer |

See `docs/register_map.md`.

## Tools

- Icarus Verilog
- GTKWave
- Verilator
- Yosys
- Nangate45 Open Cell Library
- OpenSTA
- GNU Make
- Git

## Run

Subsystem simulation:

```bash
make sim_subsystem
