# Logic Synthesis & Technology Mapping Architecture

This document describes the algorithms implemented in TEMPO for Boolean decomposition, And-Inverter Graph (AIG) manipulation, priority cut enumeration, and dynamic programming DAG covering technology mapping.

---

## 1. Shannon Decomposition & Boolean Analysis

For an arbitrary Boolean function $F(x_1, x_2, \dots, x_n)$, Shannon expansion with respect to variable $x_i$ is defined as:

$$F = x_i \cdot F_{x_i} + \bar{x}_i \cdot F_{\bar{x}_i}$$

where:
* $F_{x_i} = F(x_1, \dots, x_i = 1, \dots, x_n)$ is the positive cofactor.
* $F_{\bar{x}_i} = F(x_1, \dots, x_i = 0, \dots, x_n)$ is the negative cofactor.

### Boolean Difference (Observability)
The Boolean difference of $F$ with respect to $x_i$ represents the sensitivity condition under which toggling $x_i$ causes the output $F$ to toggle:

$$\frac{\partial F}{\partial x_i} = F_{x_i} \oplus F_{\bar{x}_i}$$

When $\frac{\partial F}{\partial x_i} = 1$, the logic value at input $x_i$ is observable at output $F$. This is utilized during Automatic Test Pattern Generation (ATPG) for path sensitization.

---

## 2. And-Inverter Graph (AIG) Engine

TEMPO implements an AIG representation where every combinational logic gate is decomposed into a directed acyclic graph consisting entirely of two-input AND nodes and inverted edges.

### Structural Hashing & Constant Folding
During graph construction, on-the-fly simplification rules are evaluated:

| Expression | Simplified Result | Rule |
| :--- | :--- | :--- |
| $\text{AND}(0, x)$ | $0$ | Dominance |
| $\text{AND}(1, x)$ | $x$ | Identity |
| $\text{AND}(x, x)$ | $x$ | Idempotence |
| $\text{AND}(x, \bar{x})$ | $0$ | Complement Contradiction |

Each unique AND node is hashed by canonical sorted inputs $(u, v)$ with $u < v$. If an equivalent node already exists in the structural hash table, the existing node pointer is reused, eliminating structural redundancy.

---

## 3. Priority $k$-Feasible Cut Enumeration

A cut of a node $n$ in an AIG is a set of nodes $C \subseteq V$ such that every path from the primary inputs to $n$ passes through at least one node in $C$. A cut is **$k$-feasible** if $|C| \le k$ (typically $k = 4$ or $k = 5$).

### Cut Generation Algorithm
The cuts of an internal node $n = u \wedge v$ are computed from the cuts of its child nodes:

$$\text{Cuts}(n) = \{ \{n\} \} \cup \{ c_u \cup c_v \mid c_u \in \text{Cuts}(u), c_v \in \text{Cuts}(v), |c_u \cup c_v| \le k \}$$

### Priority Pruning
To prevent exponential growth in cut space:
1. Trivial cut $\{n\}$ is always retained.
2. Dominant cuts ($c_1 \subset c_2$) are pruned.
3. Cuts are sorted by an evaluation metric (arrival time or cut area), retaining only the top $P$ priority cuts per node.

---

## 4. Dynamic Programming Technology Mapping

Given a set of standard cells in the target Liberty library (inverters, NAND, NOR, AND, OR, XOR, MUX), technology mapping covers the AIG with standard cell library instances.

### DAG Covering Algorithm
1. **Topological Traversal**: Visit AIG nodes in topological order from primary inputs to primary outputs.
2. **Cut Evaluation**: For each node $n$ and each $k$-feasible cut $C$:
   * Extract the truth table of the subgraph rooted at $n$ with leaves $C$.
   * Match the truth table signature against the library cell catalog.
   * If a match is found for cell $M$:
     $$\text{Arrival}(n, C) = \max_{l \in C} (\text{Arrival}(l)) + \text{Delay}(M)$$
     $$\text{Area}(n, C) = \sum_{l \in C} \text{Area}(l) + \text{Area}(M)$$
3. **Best Match Selection**: Record the minimum-arrival or minimum-area cut and corresponding standard cell for node $n$.
4. **Netlist Generation**: Backtrack from primary outputs along the selected cuts, instantiating standard cell instances and wiring interconnect nets.

---

## 5. Peephole Netlist Optimization

Following technology mapping, TEMPO applies local peephole graph transformations:
* **Inverter Pair Cancellation**: Chains of two consecutive inverters ($u \to \text{INV}_1 \to \text{INV}_2 \to v$) are collapsed directly into a wire when not required for hold buffering.
* **Buffer Collapsing**: Non-delay buffers are bypassed to reduce area and dynamic power.
* **Dead Gate Pruning**: Gates whose fanout count drops to zero are removed recursively.
