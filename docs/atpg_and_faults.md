# Automatic Test Pattern Generation (ATPG) & Fault Testing

This document details the single stuck-at fault models, fault collapsing techniques, Goel's PODEM deterministic test generation algorithm, and parallel fault simulation implemented in TEMPO.

---

## 1. Single Stuck-At (SSA) Fault Model

Under the classical Single Stuck-At fault model, manufacturing physical defects in semiconductor interconnects are abstracted as a wire permanently clamped to:
* **Stuck-At-0 (SA0)**: Net permanently tied to ground (logic 0).
* **Stuck-At-1 (SA1)**: Net permanently tied to supply voltage (logic 1).

For a circuit with $N$ signal nets, there are $2N$ uncollapsed candidate faults.

---

## 2. Structural Fault Collapsing

Fault collapsing reduces the number of target faults while preserving 100% test coverage capability:

### Equivalence Collapsing
Two faults $f_1$ and $f_2$ are functionally equivalent if any test vector that detects $f_1$ also detects $f_2$, and vice versa. Equivalent faults can be collapsed into a single representative fault:

* **Inverter (NOT Gate)**:
  * Input SA0 is equivalent to Output SA1.
  * Input SA1 is equivalent to Output SA0.
  * Collapses 4 faults to 2 faults (50% reduction).

* **2-Input NAND Gate**:
  * Any input SA0 forces output to 1, identical to Output SA1.
  * Input A SA0, Input B SA0, and Output SA1 collapse into 1 fault.

* **2-Input NOR Gate**:
  * Any input SA1 forces output to 0, identical to Output SA0.
  * Input A SA1, Input B SA1, and Output SA0 collapse into 1 fault.

---

## 3. Roth 5-State D-Calculus

To represent both the fault-free (good) circuit and the faulty circuit simultaneously, TEMPO utilizes Roth 5-state logic:

| State | Good Value | Faulty Value | Meaning |
| :---: | :---: | :---: | :--- |
| **0** | 0 | 0 | Unaffected logic 0 |
| **1** | 1 | 1 | Unaffected logic 1 |
| **X** | Unknown | Unknown | Don't care / unassigned |
| **D** | 1 | 0 | Discrepancy (Good=1, Fault=0) |
| **D_BAR** | 0 | 1 | Discrepancy (Good=0, Fault=1) |

### 5-State Truth Tables

#### Inverter (NOT)
$$\text{NOT}(0) = 1, \quad \text{NOT}(1) = 0, \quad \text{NOT}(D) = \bar{D}, \quad \text{NOT}(\bar{D}) = D, \quad \text{NOT}(X) = X$$

#### 2-Input AND Gate
$$\text{AND}(0, \text{any}) = 0$$
$$\text{AND}(1, v) = v$$
$$\text{AND}(D, D) = D, \quad \text{AND}(\bar{D}, \bar{D}) = \bar{D}$$
$$\text{AND}(D, \bar{D}) = 0, \quad \text{AND}(\bar{D}, D) = 0$$
$$\text{AND}(D, 1) = D, \quad \text{AND}(\bar{D}, 1) = \bar{D}$$

---

## 4. Goel's PODEM Algorithm

The Path-Oriented Decision Making (PODEM) algorithm resolves the exponential backtracking bottleneck of the classic D-algorithm by making all search decisions strictly at Primary Inputs (PIs).

```
                      +-----------------------------+
                      |   Target Stuck-At Fault     |
                      +--------------+--------------+
                                     |
                                     v
                       [ Check: Discrepancy at PO? ]
                       * If D or D_BAR at PO -> SUCCESS
                                     | (No)
                                     v
                        [ Determine Next Objective ]
                        * If net unactivated: Activate (0/1)
                        * If net activated: Propagate D-frontier
                                     |
                                     v
                        [ Backtrace to Primary Input ]
                        * Trace backwards to unassigned PI
                                     |
                                     v
                        [ Assign Chosen Value to PI ]
                                     |
                                     v
                        [ Recursive Forward Search ]
                        * Simulate 5-state implications
                        * If success -> Return vector
                                     | (Failure)
                                     v
                        [ Backtrack: Invert PI Value ]
                        * Try complement value
                        * If failure -> Mark unassigned (X)
```

### Objective Selection
1. **Fault Activation**: If the target net does not have $D$ or $\bar{D}$, the objective is to place a $1$ on the net (if SA0) or a $0$ on the net (if SA1).
2. **D-Frontier Propagation**: Once activated, locate a gate with $D$ or $\bar{D}$ on an input and $X$ on its output. Set the objective to drive the other gate inputs to their non-controlling values ($1$ for AND/NAND, $0$ for OR/NOR).

### Backtracing
Recursively traverses backwards from the objective net through driving gates to an unassigned primary input, inverting the requested logic polarity whenever an inverting gate (INV, NAND, NOR) is crossed.

---

## 5. Parallel Fault Simulation & Fault Dropping

Once a test vector is generated:
1. **Golden Simulation**: Simulate the fault-free circuit and record all primary output values.
2. **Fault Injection**: For each active fault in the list, clamp the target net to the stuck-at value.
3. **Faulty Simulation**: Propagate signals to primary outputs.
4. **Detection Condition**: If any primary output differs between the golden and faulty circuit ($v_{good} \ne v_{faulty}$ with both values in $\{0, 1\}$), the fault is detected.
5. **Fault Dropping**: Detected faults are removed from the active fault list, accelerating subsequent vector evaluations.
6. **Manufacturing Test Coverage**:
   $$\text{Fault Coverage} = \frac{\text{Detected Faults}}{\text{Total Targeted Faults}} \times 100\%$$
