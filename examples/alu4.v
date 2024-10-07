// ==============================================================================
// 4-bit Arithmetic Logic Unit (ALU) Structural Netlist
// Technology: SkyWater 130nm High-Density (sky130_fd_sc_hd)
// ==============================================================================

module alu4 (
    input clk,
    input rst,
    input [3:0] a,
    input [3:0] b,
    input [1:0] op,
    output [3:0] result
);

    wire w_a0, w_a1, w_a2, w_a3;
    wire w_b0, w_b1, w_b2, w_b3;
    wire w_and0, w_and1, w_and2, w_and3;
    wire w_nand0, w_nand1, w_nand2, w_nand3;
    wire w_d0, w_d1, w_d2, w_d3;

    // Bit 0 logic
    sky130_fd_sc_hd__and2_1 u_and0 (
        .A(a[0]),
        .B(b[0]),
        .Y(w_and0)
    );

    sky130_fd_sc_hd__nand2_1 u_nand0 (
        .A(a[0]),
        .B(b[0]),
        .Y(w_nand0)
    );

    sky130_fd_sc_hd__inv_1 u_inv0 (
        .A(w_nand0),
        .Y(w_d0)
    );

    sky130_fd_sc_hd__dfxtp_1 u_reg0 (
        .CLK(clk),
        .D(w_d0),
        .Q(result[0])
    );

    // Bit 1 logic
    sky130_fd_sc_hd__and2_1 u_and1 (
        .A(a[1]),
        .B(b[1]),
        .Y(w_and1)
    );

    sky130_fd_sc_hd__inv_1 u_inv1 (
        .A(w_and1),
        .Y(w_d1)
    );

    sky130_fd_sc_hd__dfxtp_1 u_reg1 (
        .CLK(clk),
        .D(w_d1),
        .Q(result[1])
    );

    // Bit 2 logic
    sky130_fd_sc_hd__nand2_1 u_nand2 (
        .A(a[2]),
        .B(b[2]),
        .Y(w_nand2)
    );

    sky130_fd_sc_hd__inv_1 u_inv2 (
        .A(w_nand2),
        .Y(w_d2)
    );

    sky130_fd_sc_hd__dfxtp_1 u_reg2 (
        .CLK(clk),
        .D(w_d2),
        .Q(result[2])
    );

    // Bit 3 logic
    sky130_fd_sc_hd__and2_1 u_and3 (
        .A(a[3]),
        .B(b[3]),
        .Y(w_and3)
    );

    sky130_fd_sc_hd__inv_1 u_inv3 (
        .A(w_and3),
        .Y(w_d3)
    );

    sky130_fd_sc_hd__dfxtp_1 u_reg3 (
        .CLK(clk),
        .D(w_d3),
        .Q(result[3])
    );

endmodule
