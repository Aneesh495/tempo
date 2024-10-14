# TEMPO Architecture Specification

TEMPO is an open-source Electronic Design Automation (EDA) framework implementing Static Timing Analysis (STA), logic synthesis, technology mapping, design rule checking (DRC), gate-level 4-state digital simulation, and manufacturing fault testing (ATPG).

```
                      +-----------------------------------+
                      | Structural Verilog Netlist (.v)   |
                      | Liberty Timing Models (.lib)      |
                      | SDC 2.1 Constraints (.sdc)        |
                      | SPEF Parasitics (.spef)           |
                      +-----------------+-----------------+
                                        |
                                        v
                            [ Lexer & Parser Subsystem ]
                                        |
                 +----------------------+----------------------+
                 |                                             |
                 v                                             v
     [ Logic Synthesis & TechMap ]               [ Bipartite Timing Graph ]
     * Shannon Decomposition                     * Cell Arcs & Net Arcs
     * And-Inverter Graph (AIG)                  * Pin Capacitance Aggregation
     * Priority Cut Enumeration                  * Clock Tree Analyzer
     * Dynamic Programming DAG Covering          * Elmore RC Wire Delay
                 |                                             |
                 v                                             v
     [ Netlist Transformations ]                 [ Topological STA Engine ]
     * Peephole Inverter Collapse                * Forward Arrival & Slew Prop
     * Dead Gate Removal                         * Backward Required Time Prop
     * Van Ginneken Buffer Trees                 * Setup & Hold Slack Calc
     * Drive Strength Sizing                     * Critical Path Backtracking
                 |                                             |
                 +----------------------+----------------------+
                                        |
                 +----------------------+----------------------+
                 |                                             |
                 v                                             v
     [ Simulation & Fault Testing ]              [ Power & Physical Metrics ]
     * Discrete Event Priority Queue             * Subthreshold Static Leakage
     * IEEE 1364 4-State Simulator               * Dynamic Capacitive Switching
     * VCD Waveform Dumper                       * Internal Short-Circuit Power
     * Static/Dynamic Hazard Detector            * Silicon Area & Gate Counts
     * PODEM ATPG & Fault Simulator              * Electrical DRC Auditor
```

---

## Subsystem Architecture

### 1. Core Foundations (`src/core/`)
* **Dimensional Units (`types.tcl`)**: Explicit dimensional quantities with automatic unit conversions across seconds, milliseconds, microseconds, nanoseconds, picoseconds, and femtoseconds; Farads, microfarads, nanofarads, picofarads, and femtofarads; and power units (Watts, milliwatts, microwatts).
* **Multi-Valued Logic (`bitvector.tcl`)**: Strict IEEE 1364 4-state logic (`0`, `1`, `X`, `Z`) and Roth 5-state D-calculus (`0`, `1`, `X`, `D`, `D_BAR`) with bitvector operations and literal parsers (`4'b1010`, `8'hFF`).
* **Directed Hypergraph (`graph.tcl`)**: High-performance graph engine supporting Kahn topological sorting, Tarjan strongly connected component (SCC) cycle detection, and DAG longest-path calculation.
* **Structural Netlist (`netlist.tcl`)**: Hierarchical port, net, and cell instance model with electrical sanity checking (floating inputs, undriven wires, driver contention) and deep netlist cloning.
* **C Acceleration Bridge (`accel.tcl`)**: Dynamic loader that inspects native compiled extensions (`tempo_accel.dylib` / `.so`) and replaces inner loops with compiled C routines, while providing seamless 100% pure-Tcl fallback when uncompiled.

### 2. Industry-Standard Parsers (`src/parsers/`)
* **Liberty NLDM Parser (`liberty_*.tcl`)**: Lexer, recursive-descent parser, and object model for Synopsys Liberty (`.lib`) timing libraries. Supports 2D Non-Linear Delay Model (NLDM) lookup tables with bilinear interpolation, pin capacitances, setup/hold sequential timing arcs, and cell leakage power.
* **Structural Verilog-2005 Parser (`verilog_*.tcl`)**: Tokenizer and parser for structural Verilog netlists. Handles module declarations, bus ranges (`[MSB:LSB]`), standard cell instantiations with named port bindings, primitive gates (`nand`, `and`, `nor`, `or`, `xor`, `not`, `buf`), and continuous assignments.
* **SDC 2.1 Constraint Evaluator (`sdc_*.tcl`)**: Safe Tcl evaluation sandbox implementing Synopsys Design Constraints (SDC 2.1). Supports `create_clock`, `set_clock_uncertainty`, `set_clock_latency`, `set_input_delay`, `set_output_delay`, `set_load`, `set_input_transition`, `set_false_path`, and `set_multicycle_path`.
* **IEEE 1481 SPEF Parasitic Parser (`spef_parser.tcl`)**: Parses post-layout Standard Parasitic Exchange Format (SPEF) files, building distributed RC interconnect trees with lump capacitances, cross-coupling capacitances, and resistor segments.

### 3. Logic Synthesis & Technology Mapping (`src/synth/`)
* **Boolean Engine (`boolean.tcl`)**: Computes Shannon positive/negative cofactors, Boolean differences ($dF/dx$) for fault observability, truth tables, and canonical NPN equivalence signatures.
* **And-Inverter Graph (`aig.tcl`)**: Structural AIG engine with two-level hash-consing, on-the-fly constant folding, and multi-input logic gate decomposition.
* **Cut Enumerator (`cut.tcl`)**: Priority $k$-feasible cut enumeration discovering all subgraphs with at most $k$ inputs for standard cell mapping.
* **Technology Mapper (`techmap.tcl`)**: Dynamic programming DAG covering algorithm that matches enumerated cuts against standard cell library patterns to minimize arrival time or silicon area.
* **Netlist Optimizer (`optimize.tcl`)**: Peephole transformation engine that removes double-inverter chains, collapses non-delay buffers, and prunes dead gates.

### 4. Static Timing Analysis Engine (`src/sta/`)
* **Bipartite Timing Graph (`timing_graph.tcl`)**: Constructs bipartite graphs where nodes represent pins and ports, connected by cell timing arcs and net interconnect arcs. Classifies timing startpoints (primary inputs, register Q pins) and endpoints (primary outputs, register D pins).
* **Delay Calculator (`delay_calc.tcl`)**: Evaluates NLDM 2D tables via bilinear interpolation over input transition and output capacitive load.
* **Elmore Delay Calculator (`elmore.tcl`)**: Calculates distributed RC interconnect propagation delay and output slew degradation for SPEF networks.
* **Clock Tree Analyzer (`clock_tree.tcl`)**: Evaluates clock domains, source latency, network insertion delay, clock skew between launch and capture registers, and uncertainty margins.
* **Forward Propagator (`forward_prop.tcl`)**: Computes early and late arrival times along with rise and fall transition slews across topological node orders.
* **Backward Propagator (`backward_prop.tcl`)**: Propagates required arrival times backwards from endpoints to startpoints.
* **Slack & Critical Path (`slack_calc.tcl`, `critical_path.tcl`)**: Computes setup slack ($T_{req} - T_{arr}$) and hold slack ($T_{arr} - T_{req}$), extracting worst negative slack (WNS), total negative slack (TNS), and formatting OpenSTA-style ASCII timing reports.
* **Multi-Corner PVT (`corner.tcl`)**: Scales delays across Process, Voltage, and Temperature operating corners (Slow, Typical, Fast).

### 5. Timing-Driven Physical Optimization (`src/opt/`)
* **Design Rule Checker (`drc.tcl`)**: Audits electrical design rules: maximum transition time (max slew), maximum load capacitance, and maximum fanout limits.
* **Gate Sizer (`gate_sizing.tcl`)**: Identifies standard cell drive-strength families (e.g. `INV_X1`, `INV_X2`, `INV_X4`), up-sizing critical path gates to fix setup violations and down-sizing non-critical gates to recover silicon area.
* **Buffer Inserter (`buffer_insert.tcl`)**: Automatically splits high-fanout nets into balanced repeater trees to restore signal transitions.
* **Hold Remediator (`hold_fix.tcl`)**: Detects negative hold slack endpoints and inserts delay buffers without violating setup timing constraints.

### 6. Power & Physical Area Subsystem (`src/power/`)
* **Static Leakage Analyzer (`leakage.tcl`)**: Computes subthreshold and gate tunneling leakage power across standard cell instances.
* **Dynamic Power Analyzer (`dynamic.tcl`)**: Computes capacitive switching power ($P_{switch} = 0.5 \cdot \alpha \cdot C_L \cdot V_{DD}^2 \cdot f$) and internal cell short-circuit power.
* **Physical Area Analyzer (`area.tcl`)**: Sums combinational and sequential standard cell silicon area (in $\mu\text{m}^2$) and computes NAND2-equivalent gate counts.

### 7. Simulation & Fault Testing (`src/sim/`, `src/fault/`, `src/formal/`)
* **Event-Driven Simulator (`simulator.tcl`, `event.tcl`)**: Min-priority discrete event queue simulating 4-state logic with inertial delay glitch filtering and sequential clock edge evaluation.
* **VCD Writer (`vcd.tcl`)**: Generates IEEE 1364 Value Change Dump waveform files for viewing in GTKWave.
* **Hazard Detector (`hazard.tcl`)**: Scans transition histories to identify static-1, static-0, and dynamic glitch hazards.
* **Formal Equivalence Checker (`cec.tcl`)**: Builds miter circuits to formally verify equivalence between Golden and Revised netlists, extracting counter-example input vectors upon discrepancy.
* **Fault Collapsing (`fault_model.tcl`)**: Generates single stuck-at-0 and stuck-at-1 faults, applying structural equivalence collapsing.
* **PODEM ATPG (`podem.tcl`)**: Goel's Path-Oriented Decision Making algorithm making assignments strictly at primary inputs with Roth 5-state D-calculus backtracing.
* **Fault Simulator (`fault_sim.tcl`)**: Simulates test vectors with parallel fault dropping to compute manufacturing fault coverage percentages.

### 8. Interactive CLI Shell (`src/shell/`, `bin/tempo`)
* Command palette implementing Synopsys PrimeTime and OpenSTA syntax (`read_liberty`, `read_verilog`, `read_sdc`, `read_spef`, `link_design`, `report_timing`, `report_drc`, `report_power`, `report_area`, `run_atpg`).
* Supports both interactive command-line REPL and batch script execution (`./bin/tempo script.tcl`).
