# Synopsys Design Constraints (SDC 2.1) Reference Manual

This document details the Synopsys Design Constraints (SDC) subsystem in Tempo. SDC serves as the industry-standard timing specification language for defining clock waveforms, input/output boundary delays, external loads, transition slews, and timing exceptions.

Tempo implements an SDC 2.1 compliant execution engine utilizing a sandboxed Tcl safe interpreter (`interp create -safe`) to execute constraints safely and reproducibly.

---

## 1. Architectural Model and Safe Execution

Because SDC scripts are natively expressed in Tcl syntax, Tempo leverages Tcl's native meta-circular capability to parse SDC scripts. However, raw evaluation poses risks of variable contamination or unauthorized file system operations.

Tempo isolates constraint evaluation in a dedicated safe slave interpreter:

```
+-------------------------------------------------------------+
|                   Tempo Master Process                      |
|                                                             |
|  [ SDC File / String ]                                      |
|           |                                                 |
|           v                                                 |
|  +-------------------------------------------------------+  |
|  |           Sandboxed Safe Slave Interpreter            |  |
|  |             (interp create -safe)                     |  |
|  |                                                       |  |
|  |   Aliases: create_clock, set_input_delay, get_ports   |  |
|  +-------------------------------------------------------+  |
|           |                                                 |
|           v Populates                                       |
|  [ ::tempo::sdc::Constraints Model ]                        |
|    - Clocks & Waveforms                                     |
|    - Port Input/Output Delays                               |
|    - Clock Latency & Uncertainty Budgets                    |
|    - Capacitive Port Loads & Driving Cells                  |
|    - False Paths & Multicycle Timing Exceptions             |
+-------------------------------------------------------------+
```

1. **Sandboxing**: File I/O, process execution, and global variable leakage are completely blocked.
2. **Collection Aliases**: SDC collection commands (`get_ports`, `get_pins`, `get_clocks`) resolve against the linked structural netlist.
3. **Unit Normalization**: Timing units are automatically scaled to internal base units (picoseconds and femtofarads).

---

## 2. Collection and Query Commands

SDC uses collection commands to bind timing assertions to specific ports, pins, or clock objects.

### `get_ports`
Returns a list of primary input/output port names matching a glob pattern.

```tcl
get_ports <pattern>
```

- **Example**: `get_ports clk` or `get_ports data[*]`
- If evaluated with a linked netlist, patterns match actual netlist port identifiers.

### `get_pins`
Returns a list of hierarchical instance pin names matching a pattern.

```tcl
get_pins <pattern>
```

- **Example**: `get_pins u_reg/D`

### `get_clocks`
Returns a list of defined clock objects matching a pattern.

```tcl
get_clocks <pattern>
```

- **Example**: `get_clocks sys_clk`

### `all_inputs`
Returns all primary input ports of the design (excluding clock ports if specified).

```tcl
all_inputs [-no_clocks]
```

### `all_outputs`
Returns all primary output ports of the design.

```tcl
all_outputs
```

### `all_clocks`
Returns all clock objects currently defined in the constraints container.

```tcl
all_clocks
```

---

## 3. Clock Definitions and Characteristics

Clocks establish the temporal reference grid for all synchronous launch and capture events.

### `create_clock`
Defines an ideal or propagated clock waveform.

```tcl
create_clock -period <val> [-name <clk_name>] [-waveform {edge_rise edge_fall}] [port_or_pin_list]
```

- `-period <val>`: Clock period in nanoseconds or picoseconds (e.g., `10.0` or `10000ps`).
- `-name <clk_name>`: Explicit name of the clock. If omitted, defaults to the name of the target port.
- `-waveform {rise fall}`: Rise and fall edge times within the cycle. Defaults to `{0.0 [expr period / 2.0]}` (50% duty cycle).
- `port_or_pin_list`: The primary port or instance pin where the clock enters the design.

```tcl
# 100 MHz clock (10 ns period) with 50% duty cycle on port 'clk'
create_clock -name core_clk -period 10.0 [get_ports clk]

# Asymmetric clock waveform (rise at 1.0 ns, fall at 4.0 ns, period 8.0 ns)
create_clock -name strobe -period 8.0 -waveform {1.0 4.0} [get_ports strobe_in]
```

### `set_clock_uncertainty`
Specifies the timing uncertainty budget, encompassing clock jitter, PLL phase variation, and intra-die clock network skew.

```tcl
set_clock_uncertainty [-setup | -hold] <val> [get_clocks <clk>]
```

- `-setup`: Subtracts uncertainty from required arrival time in setup checks ($T_{skew} - T_{uncertainty}$).
- `-hold`: Adds uncertainty to required arrival time in hold checks ($T_{hold} + T_{uncertainty}$).
- If neither flag is passed, the uncertainty value applies symmetrically to both setup and hold.

```tcl
# 150 ps setup uncertainty and 80 ps hold uncertainty
set_clock_uncertainty -setup 0.150 [get_clocks core_clk]
set_clock_uncertainty -hold 0.080 [get_clocks core_clk]
```

### `set_clock_latency`
Models clock network insertion delay before clock tree synthesis (ideal clock mode) or external source latency.

```tcl
set_clock_latency [-source] [-early | -late] <val> [get_clocks <clk>]
```

- `-source`: Latency from the off-chip source oscillator to the chip clock input pin.
- `-early`: Minimum insertion delay (used in minimum-path hold checks).
- `-late`: Maximum insertion delay (used in maximum-path setup checks).

```tcl
# 500 ps late source latency, 400 ps early source latency
set_clock_latency -source -late 0.500 [get_clocks core_clk]
set_clock_latency -source -early 0.400 [get_clocks core_clk]
```

---

## 4. Input and Output Boundary Delays

Primary I/O boundaries communicate with off-chip components governed by the external clock.

### `set_input_delay`
Asserts the arrival time of an input signal relative to an external clock edge. This models off-chip flight time plus the external transmitter clock-to-out delay ($T_{co}$).

```tcl
set_input_delay -clock <clk> [-max | -min] <val> <port_list>
```

- `-clock <clk>`: Reference launch clock.
- `-max`: Maximum delay used for setup timing analysis.
- `-min`: Minimum delay used for hold timing analysis.
- If neither `-max` nor `-min` is specified, the value applies to both.

```tcl
# Data inputs arrive up to 2.5 ns after clock edge (setup), minimum 0.8 ns (hold)
set_input_delay -clock core_clk -max 2.5 [get_ports {data_in[*] reset_n}]
set_input_delay -clock core_clk -min 0.8 [get_ports {data_in[*] reset_n}]
```

### `set_output_delay`
Asserts the required external board flight time and receiver setup time relative to an external capture clock edge.

```tcl
set_output_delay -clock <clk> [-max | -min] <val> <port_list>
```

- `-clock <clk>`: Reference capture clock.
- `-max`: Maximum required external delay (subtracted from setup capture target).
- `-min`: Minimum external delay required for hold check ($T_{hold,ext}$).

```tcl
# Output data must be stable 2.0 ns before capture edge
set_output_delay -clock core_clk -max 2.0 [get_ports {data_out[*] valid}]
set_output_delay -clock core_clk -min -0.2 [get_ports {data_out[*] valid}]
```

---

## 5. Electrical Boundary Assertions

Accurate cell delay calculation in NLDM tables requires driving cell slews and primary output capacitive loads.

### `set_load`
Attaches an external lumped capacitive load to primary output ports.

```tcl
set_load <val> <port_list>
```

- `<val>`: Capacitance in picofarads or femtofarads (e.g., `0.02` for 20 fF, or `20fF`).

```tcl
# 25 fF load on all primary outputs
set_load 0.025 [all_outputs]
```

### `set_input_transition`
Defines an explicit input signal slew on primary inputs (used when driving cells are not specified).

```tcl
set_input_transition [-rise | -fall] <val> <port_list>
```

- `<val>`: Transition time (e.g., `0.05` for 50 ps).

```tcl
set_input_transition 0.050 [all_inputs]
```

### `set_driving_cell`
Models realistic input slews by specifying the standard cell driving the primary input port.

```tcl
set_driving_cell -lib_cell <cell_name> [-pin <pin_name>] <port_list>
```

- `-lib_cell <cell_name>`: Liberty cell name (e.g., `sky130_fd_sc_hd__inv_2`).
- `-pin <pin_name>`: Output pin of the driving cell (defaults to `Y` or `X`).

```tcl
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 [get_ports data_in[*]]
```

---

## 6. Timing Exceptions

Timing exceptions override the default single-cycle synchronous timing relationships between startpoints and endpoints.

### `set_false_path`
Disables timing analysis along specified paths. False paths are ignored during both setup and hold slack calculations, as well as critical path extraction.

```tcl
set_false_path [-from <startpoint>] [-to <endpoint>] [-through <intermediate_pin>]
```

- `-from`: Primary input port, clock, or register clock pin.
- `-to`: Primary output port, clock, or register data pin.
- `-through`: Intermediate net or pin along the path.

```tcl
# Asynchronous reset path is not constrained synchronously
set_false_path -from [get_ports rst_n]

# Ignore paths across asynchronous clock domains
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
```

### `set_multicycle_path`
Alters the number of clock cycles allocated for data propagation from launch to capture.

```tcl
set_multicycle_path <multiplier> [-setup | -hold] [-from <startpoint>] [-to <endpoint>]
```

- `<multiplier>`: Number of clock periods (integer $\ge 1$).
- `-setup`: Multiplies the setup check target:
  $$T_{capture, setup} = multiplier \cdot T_{period}$$
- `-hold`: Shifts the hold check baseline (defaults to $multiplier - 1$).

```tcl
# Path takes 2 clock cycles to settle
set_multicycle_path 2 -setup -from [get_pins u_mult/clk] -to [get_pins u_acc/D]
set_multicycle_path 1 -hold  -from [get_pins u_mult/clk] -to [get_pins u_acc/D]
```

---

## 7. Complete SDC Example

Below is a complete, production-grade SDC 2.1 script for an ASIC IP block:

```tcl
###############################################################################
# SDC Constraints for IP Block
# Target Frequency: 200 MHz (5.0 ns period)
###############################################################################

# 1. Primary Clock Definition
create_clock -name core_clk -period 5.0 -waveform {0.0 2.5} [get_ports clk]

# 2. Clock Jitter and Network Insertion Latency
set_clock_uncertainty -setup 0.120 [get_clocks core_clk]
set_clock_uncertainty -hold 0.050 [get_clocks core_clk]
set_clock_latency -source -late 0.350 [get_clocks core_clk]
set_clock_latency -source -early 0.280 [get_clocks core_clk]

# 3. Input Port Constraints
set_input_delay -clock core_clk -max 1.2 [get_ports {operand_a[*] operand_b[*] opcode[*]}]
set_input_delay -clock core_clk -min 0.3 [get_ports {operand_a[*] operand_b[*] opcode[*]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 [get_ports {operand_a[*] operand_b[*] opcode[*]}]

# 4. Output Port Constraints
set_output_delay -clock core_clk -max 1.5 [get_ports {result[*] flag_zero flag_overflow}]
set_output_delay -clock core_clk -min -0.1 [get_ports {result[*] flag_zero flag_overflow}]
set_load 0.020 [get_ports {result[*] flag_zero flag_overflow}]

# 5. Timing Exceptions
set_false_path -from [get_ports reset_n]
```
