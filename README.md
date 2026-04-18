# 🧠 Dual-Port RAM Verification Environment

> A modular, scalable **SystemVerilog UVM-style** verification environment for a 4096-depth, 64-bit wide Dual-Port RAM — featuring concurrent read/write drivers, self-checking monitors, and constrained-random stimulus generation.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Component Breakdown](#component-breakdown)
  - [DUT — ram_4096](#dut--ram_4096)
  - [Interface — ram_if](#interface--ram_if)
  - [Transaction — ram_trans](#transaction--ram_trans)
  - [Generator — ram_gen](#generator--ram_gen)
  - [Write Driver — ram_write_drv](#write-driver--ram_write_drv)
  - [Read Driver — ram_read_drv](#read-driver--ram_read_drv)
  - [Write Monitor — ram_write_mon](#write-monitor--ram_write_mon)
  - [Read Monitor — ram_read_mon](#read-monitor--ram_read_mon)
  - [Top Module — top](#top-module--top)
- [Constraints & Randomization](#constraints--randomization)
- [Simulation Flow](#simulation-flow)
- [Getting Started](#getting-started)
- [Key Design Decisions](#key-design-decisions)

---

## Overview

This project implements a complete **block-level verification environment** for a synchronous Dual-Port RAM. It is structured around industry-standard concepts — layered testbench architecture, clocking blocks, virtual interfaces, mailbox-based communication, and constrained-random test generation — making it an excellent foundation for learning or demonstrating digital verification methodology.

| Parameter     | Value                            |
|---------------|----------------------------------|
| RAM Depth     | 4096 locations                   |
| Data Width    | 64 bits                          |
| Address Width | 12 bits                          |
| Clock         | Synchronous (posedge)            |
| Port Type     | True Dual-Port (independent R/W) |

---

## Architecture

```
          ┌──────────────────────────────────────────────────────────────────────────────────────────────────────┐
          |  Testbench                                ┌─────────────┐                                            | 
          |                                           │  Generator  │                                            |
          |                                           └──────┬──────┘                                            |
          |                                                  │                                                   |
          |              gen2wr (mbox)                       |                         gen2rd (mbox)             |    
          |          ┌────────────────────────────────────────────────────────────────────────────────┐          | 
          │          |                                                                                |          |
          │   ┌──────▼─────┐     ┌────────────┐                            ┌─────────────┐     ┌──────▼─────┐    │
          │   │  Write BFM │       Wr_Monitor                                Rd_Monitor        │  Read BFM  │    │
          │   └─────┬──────┘     └──┬────┬────┘                            └────┬────┬───┘     └─────┬──────┘    │
          │         |               |    │ mbox                            mbox │    |               |           |
          │         |───────────────┘    └─────────────────────┬────────────────┘    └───────────────|           | 
          │         |                                          |                                     |           |
          │         |                                   ┌──────▼────────┐                            |           |
          │         |                                   │  Scoreboard   │                            |           |
          │         |                                   └───────────────┘                            |           | 
          └─────────\\──────────────────────────────────────────────────────────────────────────────//───────────┘
                      │                                                                            │
               Write Interface                                                               Read Interface
                      │                                                                            │
          ┌───────────▼────────────────────────────────────────────────────────────────────────────▼─────────────┐
          │                                       DUV (ram_4096)                                                 │
          └──────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
dual_port_ram_verif/
│
├── ram_4096.sv          # Design Under Verification (DUV)
├── ram_if.sv            # Interface with clocking blocks & modports
├── ram_pkg.sv           # Package (shared globals)
├── ram_trans.sv         # Transaction class with constraints
├── ram_gen.sv           # Constrained-random generator
├── ram_write_drv.sv     # Write-side BFM (driver)
├── ram_read_drv.sv      # Read-side BFM (driver)
├── ram_write_mon.sv     # Write-side monitor
├── ram_read_mon.sv      # Read-side monitor with done event
└── top.sv               # Testbench top module
```

---

## Component Breakdown

### DUT — `ram_4096`

A synchronous, true dual-port RAM with independent read and write ports, both clocked on the positive edge.

```
Ports:  clk, data_in[63:0], rd_address[11:0], wr_address[11:0], read, write, data_out[63:0]
Depth:  4096 × 64-bit words
```

- **Write Logic**: On `posedge clk`, if `write=1`, stores `data_in` at `wr_address`.
- **Read Logic**: On `posedge clk`, if `read=1`, drives `data_out` from `rd_address`; otherwise drives high-Z (`64'bz`).

---

### Interface — `ram_if`

Encapsulates all DUT signals and provides **four dedicated clocking blocks** to enforce clean signal timing:

| Clocking Block | Direction | Used By       |
|----------------|-----------|---------------|
| `wr_drv_cb`    | Output    | Write BFM     |
| `rd_drv_cb`    | Output    | Read BFM      |
| `wr_mon_cb`    | Input     | Write Monitor |
| `rd_mon_cb`    | Input     | Read Monitor  |

Each clocking block uses `#1` input/output skew to avoid race conditions. Four **modports** (`WR_DRV_MP`, `RD_DRV_MP`, `WR_MON_MP`, `RD_MON_MP`) provide role-specific, access-controlled views of the interface.

---

### Transaction — `ram_trans`

The atomic unit of stimulus and response. Fully randomizable with built-in constraints.

```systemverilog
rand bit [63:0] data;         // Stimulus data
rand bit [11:0] rd_address;   // Read address
rand bit [11:0] wr_address;   // Write address
rand bit        read;
rand bit        write;
logic   [63:0] data_out;      // Captured response
```

**Static tracking fields** accumulate across all transactions for coverage insight:

- `trans_id` — monotonically incrementing transaction counter
- `no_of_read_trans` — total pure-read transactions
- `no_of_write_trans` — total pure-write transactions
- `no_of_RW_trans` — simultaneous read+write transactions

Methods: `display()` for pretty-printing, `compare()` for scoreboard checking.

---

### Generator — `ram_gen`

Produces a configurable number of randomized `ram_trans` objects and fans them out to both the write and read BFMs via **separate mailboxes**.

```systemverilog
for (int i = 0; i < no_of_transactions; i++) {
    gen_trans.trans_id++;
    assert(gen_trans.randomize());
    gen2rd.put(data2send);
    gen2wr.put(data2send);
}
```

Uses `fork...join_none` to run non-blocking, keeping the testbench reactive.

---

### Write Driver — `ram_write_drv`

The **Write BFM** — consumes transactions from `gen2wr` and drives write-side DUT signals through the `WR_DRV_MP` modport.

- Waits for a clocking block edge before driving.
- Drives `data_in`, `wr_address`, and `write` on `write=1` transactions.
- Clears `write` signal after two additional clock edges.

---

### Read Driver — `ram_read_drv`

The **Read BFM** — mirrors the write driver for the read port via `RD_DRV_MP`.

- Drives `rd_address` and `read` signals.
- Deasserts `read` after two clock cycles, following the same protocol as the write BFM.

---

### Write Monitor — `ram_write_mon`

Passively observes the write bus through `WR_MON_MP`.

- Waits for `write=1` via `wait()`.
- Captures `write`, `wr_address`, and `data_in` on the following clock.
- Forwards a copied transaction to the **Scoreboard** via `mon2rm`.

---

### Read Monitor — `ram_read_mon`

The most feature-rich monitor — observes the read bus and drives simulation completion.

- Waits for `read=1`, then captures `read`, `rd_address`, and `data_out`.
- Forwards data to the **Scoreboard** via both `mon2rm` and `mon2sb` mailboxes.
- Tracks `rd_mon_data` count; triggers `->done` event when enough read transactions have been observed, cleanly terminating the simulation.

---

### Top Module — `top`

Instantiates and wires all components. Manages the simulation lifecycle:

```
1. Clock generation (10ns period)
2. Construct all component handles
3. Set no_of_transactions
4. Start all components (generator → BFMs → monitors)
5. Wait on rd_mon_h.done event
6. $finish
```

---

## Constraints & Randomization

| Constraint     | Rule                          | Purpose                            |
|----------------|-------------------------------|------------------------------------|
| `VALID_ADDR`   | `rd_address != wr_address`    | Prevent read/write address aliasing |
| `VALID_CNTRL`  | `{read, write} != 2'b00`      | Ensure at least one port is active |
| `VALID_DATA`   | `data inside {[1:4294]}`      | Constrain data to meaningful range |

`post_randomize()` automatically classifies each transaction and updates the static counters before driving.

---

## Simulation Flow

```
Clock Start
    │
    ▼
Generator randomizes N transactions
    │
    ├─► gen2wr ──► Write BFM ──► Drives DUT write port (Write Interface)
    │                                        │
    └─► gen2rd ──► Read BFM  ──► Drives DUT read port  (Read Interface)
                                             │
                                   ┌─────────▼──────────┐
                                   │    DUV (ram_4096)   │
                                   └────┬──────────┬─────┘
                                        │          │
                                        ▼          ▼
                                  Write Mon    Read Mon
                                        │          │
                                   mon2rm│     mon2rm + mon2sb
                                        └────┬─────┘
                                             ▼
                                       ┌──────────────────────┐
                                       │      ScoreBoard      │



                                       └──────────────────────┘
                                                   │
                                         done event triggered
                                                   │
                                              $finish
```

---

## Getting Started

### Prerequisites

Any IEEE 1800-compliant SystemVerilog simulator, such as:
- Synopsys VCS
- Cadence Xcelium / Incisive
- Mentor Questa / ModelSim
- Aldec Riviera-PRO

### Simulation

**Using VCS:**
```bash
vcs -sverilog -timescale=1ns/1ps top.sv -o simv && ./simv
```

**Using QuestaSim:**
```bash
vlog -sv top.sv
vsim -c top -do "run -all; quit"
```

### Configuring Transaction Count

In the `top` module's `initial` block, adjust:

```systemverilog
no_of_transactions = 4;  // Change this to increase stimulus coverage
```

---

## Key Design Decisions

**Clocking Blocks** — All BFM and monitor signal access happens exclusively through clocking blocks, eliminating setup/hold violations and simulation races.

**Modports** — Each component receives only the interface access it needs, enforcing role separation and preventing accidental signal corruption.


**Static Transaction Counters** — Coverage tracking lives in the transaction class itself, making it portable and independent of any external coverage collector.

**`fork...join_none`** — All component `start()` tasks spawn threads non-blocking, enabling true concurrent stimulus generation, driving, and monitoring.

**Mailbox Communication** — Typed, parameterized mailboxes (`mailbox #(ram_trans)`) provide type-safe, decoupled inter-component communication without shared-variable hazards.

**Event-Driven Termination** — The `done` event in `ram_read_mon` provides a clean, deterministic simulation end condition tied to actual DUT activity rather than a fixed time delay.

---

## 📄 License

This project is released for educational and demonstration purposes. Feel free to extend it with a full UVM base class hierarchy or functional coverage groups.

---

*Built with ❤️ using SystemVerilog — where hardware meets software verification.*
