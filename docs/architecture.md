# Architecture

APB Peripheral Subsystem contains:

- APB address decoder
- APB GPIO peripheral
- APB Timer peripheral
- Read-data / response multiplexer

## Block Diagram

APB Master
    |
    v
APB Subsystem
    |
    +---- Address Decoder
    |
    +---- APB GPIO
    |
    +---- APB Timer
    |
    +---- Response MUX
    