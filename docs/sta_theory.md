# Static Timing Analysis Theory & Formulation

This document details the mathematical formulations and algorithms implemented in the TEMPO Static Timing Analysis (STA) engine.

---

## 1. Non-Linear Delay Model (NLDM) Bilinear Interpolation

Standard cell propagation delay and output transition time (slew) are characterized in Liberty libraries as two-dimensional lookup tables indexed by input transition ($S_{in}$) and total output capacitive load ($C_L$).

Given a 2D grid with bounding coordinates $(x_0, y_0), (x_1, y_0), (x_0, y_1), (x_1, y_1)$ and corresponding characterization values $q_{00}, q_{10}, q_{01}, q_{11}$:

$$\Delta x = x_1 - x_0, \quad \Delta y = y_1 - y_0$$

The interpolated delay $f(x, y)$ is computed via bilinear interpolation:

$$f(x, y) = \frac{1}{\Delta x \cdot \Delta y} \left[ q_{00}(x_1 - x)(y_1 - y) + q_{10}(x - x_0)(y_1 - y) + q_{01}(x_1 - x)(y - y_0) + q_{11}(x - x_0)(y - y_0) \right]$$

### Boundary and Extrapolation Rules
1. If $x < x_{min}$ or $x > x_{max}$, linear extrapolation is applied using the boundary interval slope.
2. If $\Delta x = 0$ or $\Delta y = 0$ (degenerate boundary slice), the formulation reduces to single-variable linear interpolation.
3. If both $\Delta x = 0$ and $\Delta y = 0$, the single grid value $q_{00}$ is returned.

---

## 2. Distributed Interconnect Modeling (Elmore Delay)

Post-route wire parasitics are extracted from IEEE 1481 SPEF files as distributed RC tree networks.

For an RC tree driven at root node $0$, the Elmore delay to sink node $i$ is:

$$\tau_{Elmore, i} = \sum_{k \in \text{nodes}} R_{ik} \cdot C_k$$

where $R_{ik}$ is the shared resistance from the driver root to the common ancestor of node $i$ and node $k$, and $C_k$ is the lumped ground capacitance at node $k$.

For a segment chain with series resistance $R_{wire}$ and lump capacitance $C_{wire}$ driving load pin capacitance $C_{pin}$:

$$D_{wire} = R_{wire} \cdot \left( \frac{1}{2} C_{wire} + C_{pin} \right)$$

### Interconnect Slew Degradation
Interconnect resistance degrades the signal transition slew:

$$S_{out} = \sqrt{S_{in}^2 + (D_{wire} \cdot \ln(9))^2} \approx \sqrt{S_{in}^2 + (2.197 \cdot D_{wire})^2}$$

---

## 3. Clock Tree Analysis

A clock network delivers synchronous clock edges from the clock source port to sequential register clock pins.

### Clock Latency
* **Source Latency ($T_{source}$)**: Delay from the oscillator/PLL source to the chip clock input port.
* **Network Insertion Delay ($T_{network}$)**: Propagation delay through the on-chip clock distribution tree (clock buffers and inverters) to register clock pins.
* **Total Latency**:
  $$T_{clk\_latency} = T_{source} + T_{network}$$

### Clock Skew
Between launch register $R_{launch}$ and capture register $R_{capture}$:

$$T_{skew} = T_{latency}(R_{capture}) - T_{latency}(R_{launch})$$

A positive clock skew increases available setup time but degrades hold margins.

---

## 4. Setup Timing Constraint (Max Delay)

The setup constraint ensures that data launched by $R_{launch}$ stabilizes at the input of $R_{capture}$ before the capturing clock edge:

$$T_{launch\_clk} + T_{clk\_to\_q, max} + T_{comb, max} \le T_{capture\_clk} + T_{cycle} - T_{setup} - T_{uncertainty}$$

### Data Arrival Time (Late)
$$T_{arrival, late} = T_{launch\_clk, late} + T_{clk\_to\_q, late} + \sum_{gate \in path} D_{gate, late} + \sum_{net \in path} D_{wire, late}$$

### Data Required Time (Setup)
$$T_{required, setup} = T_{capture\_clk, early} + T_{period} - T_{setup} - T_{uncertainty, setup}$$

### Setup Slack
$$Slack_{setup} = T_{required, setup} - T_{arrival, late}$$

Timing is met if $Slack_{setup} \ge 0$.

---

## 5. Hold Timing Constraint (Min Delay)

The hold constraint ensures that data launched by $R_{launch}$ does not propagate so fast that it corrupts data being captured by $R_{capture}$ on the current clock edge:

$$T_{launch\_clk} + T_{clk\_to\_q, min} + T_{comb, min} \ge T_{capture\_clk} + T_{hold} + T_{uncertainty, hold}$$

### Data Arrival Time (Early)
$$T_{arrival, early} = T_{launch\_clk, early} + T_{clk\_to\_q, early} + \sum_{gate \in path} D_{gate, early} + \sum_{net \in path} D_{wire, early}$$

### Data Required Time (Hold)
$$T_{required, hold} = T_{capture\_clk, late} + T_{hold} + T_{uncertainty, hold}$$

### Hold Slack
$$Slack_{hold} = T_{arrival, early} - T_{required, hold}$$

Timing is met if $Slack_{hold} \ge 0$. Hold violations cannot be fixed by lowering clock frequency; they represent fatal race conditions remediated via delay buffer insertion.

---

## 6. Topological Propagation Algorithm

TEMPO executes Static Timing Analysis in two linear-time topological passes over the Directed Acyclic Graph (DAG):

### Forward Topological Pass (Arrival Times & Slews)
1. Initialize primary inputs with input delay and transition constraints.
2. Traverse nodes in Kahn topological sort order:
   $$T_{arr}(v) = \max_{u \in \text{fanin}(v)} \left( T_{arr}(u) + D(u, v) \right)$$
   $$Slew(v) = \text{lookup\_slew}(u, v, Slew(u), C_L(v))$$

### Backward Topological Pass (Required Arrival Times)
1. Initialize primary outputs and register D pins with required times from clock constraints.
2. Traverse nodes in reverse topological order:
   $$T_{req}(u) = \min_{v \in \text{fanout}(u)} \left( T_{req}(v) - D(u, v) \right)$$

### Slack Calculation
For every timing node $n$:
$$Slack(n) = T_{req}(n) - T_{arr}(n)$$
Worst Negative Slack (WNS) and Total Negative Slack (TNS) are aggregated across all timing endpoints.
