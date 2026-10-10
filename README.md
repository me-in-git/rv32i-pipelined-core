# rv32i-pipelined-core

[![simulation](https://github.com/me-in-git/rv32i-pipelined-core/actions/workflows/sim.yml/badge.svg)](https://github.com/me-in-git/rv32i-pipelined-core/actions/workflows/sim.yml)

5-stage pipelined RV32I core in SystemVerilog, plus a single-cycle version of the same core used as a reference.

- IF / ID / EX / MEM / WB
- forwarding from MEM and WB into EX
- load-use stall (1 bubble)
- branches resolved in EX, predict not-taken, 2-cycle penalty when taken
- ECALL halts the core

## Tests

```
make test      # needs icarus verilog 12+
```

| testbench | what it checks |
|---|---|
| `tb_rv32i_top` | forwarding, load-use stall, loads/stores |
| `tb_branch` | taken branch flushes the wrong-path instruction |
| `tb_rv32i_seq` | single-cycle core vs a golden model after every instruction |
| `tb_sort` | 8-element bubble sort on the pipeline |

```
PASS: core halted at ECALL after 526 cycles
=== SORT_TEST: ALL PASS (8-element bubble sort) ===
```

## Not done yet

- synthesis (`scripts/run_synth.tcl` is a starting point, no numbers yet)
- riscv-tests compliance suite
- branch prediction
