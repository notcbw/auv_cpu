# AUV

(WIP)

AUV is a simple RISC-V CPU implementation written in SystemVerilog. This project is meant to be used as auxiliary processors in FPGA designs. 

## Design

- RV32E_Zicsr_Zba_Zbs ISA
- Single in-order 4-stage pipeline (IF - ID - EX/MEM - WB)
- 16-bit Wishbone 4 pipelined bus master
- Simple custom IRQ controller

## Cycles Per Instruction Performance

| Instruction               | CPI |
| ------------------------- | --- |
| branch (not taken)        |   1 |
| branch (taken)            |   3 |
| 32-bit memory load        |   3 |
| 32-bit memory store       |   3 |
| 8/16-bit memory load      |   2 |
| 8/16-bit memory store     |   2 |
| CSR operations            |   3 |
| other operations          |   1 |

## TODO

- Write a proper linker script and C runtime
- Run a RISC-V test suite
- Implement optional counters and timer
- Implement optional Zmmul extension
- Make a configurable SoC with at least a UART module and a Wishbone bus xbar
- ???

## License

This repo is licensed under the [MIT License](https://opensource.org/license/mit).