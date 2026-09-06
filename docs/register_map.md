# Register reference

[README](../README.md) · [Architecture](architecture.md)

[Address decoding](#address-decoding-and-access-rules) · [GPIO](#gpio-registers) · [Timer](#timer-registers) · [UART](#uart-registers)

Register addresses are **peripheral base + offset**. Transfers are 32 bits.

| Access | Meaning |
|---|---|
| RW | Read/write |
| RO | Read-only; writes do not modify the register |
| WO | Write-only; reads return zero |
| W1C | Write 1 to clear a bit; write 0 to preserve it |

## Address decoding and access rules

| Canonical address range | Peripheral | PADDR[15:8] |
|---|---|---|
| 0x0000_0000–0x0000_00FF | GPIO | 0x00 |
| 0x0000_0100–0x0000_01FF | Timer | 0x01 |
| 0x0000_0200–0x0000_02FF | UART | 0x02 |

The subsystem uses `PADDR[15:8]` to select a peripheral and forwards
`PADDR[7:0]` as its register offset. `PADDR[31:16]` is ignored: for example,
`0xABCD_0104` aliases `0x0000_0104`.

- Data transfers are 32 bits; there is no byte-strobe interface.
- Writes take effect on a rising PCLK edge when `PSEL && PENABLE && PWRITE && PREADY`.
- All peripherals always return `PREADY = 1` and `PSLVERR = 0`.
- Unmapped pages return zero read data and assert `PSLVERR` during ACCESS
  (`PSEL && PENABLE`), for both reads and writes.
- Unimplemented offsets within a mapped page return zero and ignore register
  writes without an error. This includes unaligned offsets; low address bits
  are compared exactly, not rounded to a word boundary.
- Writes to RO registers do not modify those registers. Reads of WO registers
  return zero. A timer-page write still pauses timer advancement for that edge.
- Unimplemented register bits read as zero and are ignored on writes.
- Active-low asynchronous `PRESETn` clears GPIO/timer registers and interrupt
  outputs. UART BAUD resets to 868, TX idles high, and the RX synchronizer
  resets high; other UART stored registers reset to zero.

## GPIO registers

**Base:** `0x0000_0000` · **Reset:** all registers zero

| Offset | Register | Access | Implemented bits | Description |
|---|---|---|---|---|
| 0x00 | GPIO_DATA | RW | [7:0] | Output data; directly drives gpio_out |
| 0x04 | GPIO_DIR | RW | [7:0] | Output enable; directly drives gpio_oe |
| 0x08 | GPIO_INPUT | RO | [7:0] | Input after two synchronization stages |
| 0x0C | GPIO_INT_EN | RW | [7:0] | Per-pin IRQ mask: 1 enables contribution to gpio_irq |
| 0x10 | GPIO_INT_TYPE | RW | [7:0] | Per-pin edge: 1 rising, 0 falling |
| 0x14 | GPIO_INT_STATUS | RO | [7:0] | Sticky pending edge events |
| 0x18 | GPIO_INT_CLR | WO, W1C | [7:0] | Write 1 to clear the corresponding pending bit |

### Input and output behavior

`GPIO_DIR` does not gate `gpio_out`, input sampling, or edge detection inside
this block. External pad logic must use `gpio_oe` to control output driving.

Input passes through `gpio_sync1` and `gpio_sync2`. A further register,
`gpio_sync2_d`, stores the previous synchronized sample for edge detection.
In RTL simulation, an input stable before a sampling edge reaches `gpio_sync2`
after two rising edges and can set interrupt status on the third.

### Interrupt behavior

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

**Base:** `0x0000_0100` · **Reset:** all registers zero

| Offset | Register | Access | Implemented bits | Description |
|---|---|---|---|---|
| 0x00 | TIMER_CTRL | RW | [1:0] | Bit 0 enable; bit 1 periodic mode |
| 0x04 | TIMER_LOAD | RW | [31:0] | Reload value; writing also replaces the current counter |
| 0x08 | TIMER_VALUE | RO | [31:0] | Current down-counter value |
| 0x0C | TIMER_STATUS | RO | [0] | Sticky IRQ state |
| 0x10 | TIMER_PRESCALE | RW | [15:0] | Timer tick divider minus one |
| 0x14 | TIMER_INTCLR | WO, W1C | [0] | Write 1 to clear timer IRQ |

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
expiry. Reads and writes to GPIO or UART pages do not pause the timer.

### Starting the timer

1. Write `CTRL = 0` to disable counting.
2. Write `INTCLR = 1` to clear any pending interrupt.
3. Program `PRESCALE`.
4. Program `LOAD` to set the initial count.
5. Write `CTRL = 1` for one-shot mode or `CTRL = 3` for periodic mode.


## UART registers

**Base:** `0x0000_0200` · **Reset:** all registers zero except BAUD (`868`)

UART uses 8N1 frames, LSB first.

| Offset | Register | Access | Meaning |
|---|---|---|---|
| 0x00 | UART_TXDATA | WO | [7:0] byte; ignored when disabled or busy; reads zero |
| 0x04 | UART_RXDATA | RO | [7:0] received byte; completed read clears RX valid |
| 0x08 | UART_STATUS | RO | Current TX state and sticky RX flags |
| 0x0C | UART_CTRL | RW | TX/RX enables and interrupt masks |
| 0x10 | UART_BAUD | RW | [15:0] clocks per bit; effective minimum 2 |
| 0x14 | UART_INT_STATUS | RO | Pending interrupt flags |
| 0x18 | UART_INT_CLR | WO, W1C | Clear corresponding INT_STATUS bits; reads zero |

### Control and status bits

| Bit | UART_CTRL | UART_STATUS | UART_INT_STATUS / UART_INT_CLR |
|---|---|---|---|
| 0 | TX enable | TX busy | RX valid |
| 1 | RX enable | RX valid | TX done pending |
| 2 | RX IRQ enable | RX overrun | RX overrun |
| 3 | TX IRQ enable | RX frame error | RX frame error |

### Transmit and receive

- Configure `BAUD` while idle. The effective divider is at least 2 clocks per bit.
- Write `TXDATA` only when TX is enabled and not busy. There is no TX queue.
- Read `RXDATA` to consume the buffered byte and clear RX valid.
- If another byte arrives before the buffer is consumed, the old byte is
  preserved, the new byte is dropped, and overrun is set. This also applies
  when the old byte is consumed on the same clock as the new arrival.
- Disabling TX aborts an active transmission.

### Interrupt behavior

RX valid, overrun, or frame error asserts `uart_irq` when `CTRL[2]` is set.
TX done pending asserts it when `CTRL[3]` is set. Pending flags are recorded
even when their interrupt masks are disabled.

Write a mask to `INT_CLR` to clear the corresponding pending flags. New
TX-done and frame-error events take priority over simultaneous clears.
Reading `RXDATA` clears RX valid but does not clear overrun or frame error.
