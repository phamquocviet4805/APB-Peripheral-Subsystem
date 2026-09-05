# APB Peripheral Subsystem Register Map

This document describes the current RTL in `rtl/apb_gpio.sv`,
`rtl/apb_timer.sv`, and `rtl/apb_subsystem.sv`.

## Address decoding and access rules

| Canonical address range | Peripheral | PADDR[15:8] |
|---|---|---|
| 0x0000_0000–0x0000_00FF | GPIO | 0x00 |
| 0x0000_0100–0x0000_01FF | Timer | 0x01 |

The subsystem uses `PADDR[15:8]` to select a peripheral and forwards
`PADDR[7:0]` as its register offset. `PADDR[31:16]` is ignored: for example,
`0xABCD_0104` aliases `0x0000_0104`.

- Data transfers are 32 bits; there is no byte-strobe interface.
- Writes take effect on a rising PCLK edge when `PSEL && PENABLE && PWRITE && PREADY`.
- Both peripherals always return `PREADY = 1` and `PSLVERR = 0`.
- Unmapped pages return zero read data and assert `PSLVERR` during ACCESS
  (`PSEL && PENABLE`), for both reads and writes.
- Unimplemented offsets within a mapped page return zero and ignore register
  writes without an error. This includes unaligned offsets; low address bits
  are compared exactly, not rounded to a word boundary.
- Writes to RO registers do not modify those registers. Reads of WO registers
  return zero. A timer-page write still pauses timer advancement for that edge.
- Unimplemented register bits read as zero and are ignored on writes.
- All stored registers, synchronization stages, and interrupt outputs reset
  to zero when active-low asynchronous `PRESETn` is asserted.

## GPIO registers

| Address | Offset | Register | Access | Implemented bits | Description |
|---|---|---|---|---|---|
| 0x0000_0000 | 0x00 | GPIO_DATA | RW | [7:0] | Output data; directly drives gpio_out |
| 0x0000_0004 | 0x04 | GPIO_DIR | RW | [7:0] | Output enable; directly drives gpio_oe |
| 0x0000_0008 | 0x08 | GPIO_INPUT | RO | [7:0] | Input after two synchronization stages |
| 0x0000_000C | 0x0C | GPIO_INT_EN | RW | [7:0] | Per-pin IRQ mask: 1 enables contribution to gpio_irq |
| 0x0000_0010 | 0x10 | GPIO_INT_TYPE | RW | [7:0] | Per-pin edge: 1 rising, 0 falling |
| 0x0000_0014 | 0x14 | GPIO_INT_STATUS | RO | [7:0] | Sticky pending edge events |
| 0x0000_0018 | 0x18 | GPIO_INT_CLR | WO, W1C | [7:0] | Write 1 to clear the corresponding pending bit |

`GPIO_DIR` does not gate `gpio_out`, input sampling, or edge detection inside
this block. External pad logic must use `gpio_oe` to control output driving.

Input passes through `gpio_sync1` and `gpio_sync2`. A further register,
`gpio_sync2_d`, stores the previous synchronized sample for edge detection.
In RTL simulation, an input stable before a sampling edge reaches `gpio_sync2`
after two rising edges and can set interrupt status on the third.

Events are latched regardless of `GPIO_INT_EN`:

```text
gpio_irq = OR(GPIO_INT_STATUS & GPIO_INT_EN)
```

Masking a pin does not clear its pending status. Enabling a pending pin can
assert IRQ immediately. Holding an input at one level does not repeatedly
trigger an edge interrupt. Writing zero to `GPIO_INT_CLR` preserves status.
If a new event and a clear target the same bit on the same clock edge, the
event wins:

```text
next_status = (status & ~clear_mask) | interrupt_event
```

## Timer registers

| Address | Offset | Register | Access | Implemented bits | Description |
|---|---|---|---|---|---|
| 0x0000_0100 | 0x00 | TIMER_CTRL | RW | [1:0] | Bit 0 enable; bit 1 periodic mode |
| 0x0000_0104 | 0x04 | TIMER_LOAD | RW | [31:0] | Reload value; writing also replaces the current counter |
| 0x0000_0108 | 0x08 | TIMER_VALUE | RO | [31:0] | Current down-counter value |
| 0x0000_010C | 0x0C | TIMER_STATUS | RO | [0] | Sticky IRQ state |
| 0x0000_0110 | 0x10 | TIMER_PRESCALE | RW | [15:0] | Timer tick divider minus one |
| 0x0000_0114 | 0x14 | TIMER_INTCLR | WO, W1C | [0] | Write 1 to clear timer IRQ |

### Control and expiry

- `CTRL = 1` enables one-shot mode; `CTRL = 3` enables periodic mode.
- Writing CTRL with bit 0 clear disables counting and resets the internal
  prescaler count. It preserves the current counter and IRQ.
- Writing LOAD sets both LOAD and VALUE and resets the prescaler count.
  It does not change enable, mode, or IRQ.
- Writing PRESCALE stores the low 16 bits and resets the prescaler count.
- Enabling does not automatically reload VALUE. Reload via LOAD to restart
  a timer whose VALUE has reached zero.
- On a tick with VALUE greater than 1, VALUE decrements by one.
- On a tick with VALUE equal to 1, IRQ becomes 1. In periodic mode with
  nonzero LOAD, VALUE reloads from LOAD and enable stays set. Otherwise,
  VALUE becomes zero and enable clears; the periodic bit is preserved.
- An enabled timer with VALUE already zero disables itself on the next
  running edge without generating a new IRQ. An existing IRQ stays pending.
- IRQ stays asserted until reset or a write of bit 0 = 1 to INTCLR.
  Writing zero to INTCLR has no clearing effect. There is no timer IRQ mask.

### Prescaler and write priority

With no timer-page writes, each timer tick takes `PRESCALE + 1` PCLK cycles.
PRESCALE = 0 ticks every cycle; PRESCALE = 65535 ticks every 65536 cycles.
Starting from a fresh nonzero LOAD and reset prescaler count:

```text
cycles_to_expiry = LOAD * (PRESCALE + 1)
```

This counts running clock edges after the enabling write. Every completed
write to the timer page takes priority over timer advancement, including
writes to RO or unimplemented offsets and INTCLR writes that write zero.
Such an edge does not advance the prescaler, decrement VALUE, or process
expiry. Reads and GPIO-page writes do not pause the timer.

A typical start sequence is: disable CTRL, clear INTCLR with 1, program
PRESCALE, program LOAD, then write CTRL with 1 (one-shot) or 3 (periodic).
