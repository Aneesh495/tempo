// ==============================================================================
// ISCAS-89 Benchmark Circuit s27
// Sequential Test Benchmark with 4 inputs, 1 output, 3 flip-flops
// ==============================================================================

module s27 (
    input CK,
    input G0,
    input G1,
    input G2,
    input G3,
    output G17
);

    wire G5, G6, G7;
    wire G8, G9, G10, G11, G12, G13, G14, G15, G16;

    // Flip-flops
    sky130_fd_sc_hd__dfxtp_1 DFF_0 (
        .CLK(CK),
        .D(G10),
        .Q(G5)
    );

    sky130_fd_sc_hd__dfxtp_1 DFF_1 (
        .CLK(CK),
        .D(G11),
        .Q(G6)
    );

    sky130_fd_sc_hd__dfxtp_1 DFF_2 (
        .CLK(CK),
        .D(G13),
        .Q(G7)
    );

    // Combinational logic gates
    sky130_fd_sc_hd__inv_1 G8_gate (
        .A(G0),
        .Y(G14)
    );

    sky130_fd_sc_hd__nand2_1 G9_gate (
        .A(G14),
        .B(G6),
        .Y(G8)
    );

    sky130_fd_sc_hd__nor2_1 G10_gate (
        .A(G0),
        .B(G7),
        .Y(G10)
    );

    sky130_fd_sc_hd__nor2_1 G11_gate (
        .A(G1),
        .B(G5),
        .Y(G11)
    );

    sky130_fd_sc_hd__nand2_1 G12_gate (
        .A(G2),
        .B(G8),
        .Y(G12)
    );

    sky130_fd_sc_hd__nor2_1 G13_gate (
        .A(G11),
        .B(G12),
        .Y(G13)
    );

    sky130_fd_sc_hd__nand2_1 G17_gate (
        .A(G3),
        .B(G13),
        .Y(G17)
    );

endmodule
