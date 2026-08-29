# APB Peripheral Subsystem Register Map

## Address Map

| Address Range | Peripheral |
|---|---|
| 0x0000_0000 - 0x0000_00FF | GPIO |
| 0x0000_0100 - 0x0000_01FF | Timer |

## GPIO Registers

| Address | Register | Access | Description |
|---|---|---|---|
| 0x0000_0000 | GPIO_DATA | RW | GPIO output data |
| 0x0000_0004 | GPIO_DIR | RW | GPIO output enable |
| 0x0000_0008 | GPIO_INPUT | RO | GPIO input value |

## Timer Registers

| Address | Register | Access | Description |
|---|---|---|---|
| 0x0000_0100 | TIMER_CTRL | RW | bit[0] = enable |
| 0x0000_0104 | TIMER_LOAD | RW | Timer load value |
| 0x0000_0108 | TIMER_VALUE | RO | Current counter value |
| 0x0000_010C | TIMER_STATUS | RO | bit[0] = IRQ |
