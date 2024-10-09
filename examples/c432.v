// ==============================================================================
// ISCAS-85 Benchmark Circuit c432 (27-channel interrupt controller)
// Structural Verilog Netlist mapped to standard cell gates
// ==============================================================================

module c432 (
    input [35:0] in,
    output [6:0] out
);

    wire [159:0] n;

    // Channel priority decoder stage 1
    sky130_fd_sc_hd__nand2_1 g0 (.A(in[0]), .B(in[1]), .Y(n[0]));
    sky130_fd_sc_hd__nor2_1  g1 (.A(in[2]), .B(in[3]), .Y(n[1]));
    sky130_fd_sc_hd__and2_1  g2 (.A(in[4]), .B(in[5]), .Y(n[2]));
    sky130_fd_sc_hd__inv_1   g3 (.A(n[0]), .Y(n[3]));

    sky130_fd_sc_hd__nand2_1 g4 (.A(in[6]), .B(in[7]), .Y(n[4]));
    sky130_fd_sc_hd__nor2_1  g5 (.A(in[8]), .B(in[9]), .Y(n[5]));
    sky130_fd_sc_hd__and2_1  g6 (.A(in[10]), .B(in[11]), .Y(n[6]));
    sky130_fd_sc_hd__inv_1   g7 (.A(n[4]), .Y(n[7]));

    sky130_fd_sc_hd__nand2_1 g8 (.A(in[12]), .B(in[13]), .Y(n[8]));
    sky130_fd_sc_hd__nor2_1  g9 (.A(in[14]), .B(in[15]), .Y(n[9]));
    sky130_fd_sc_hd__and2_1  g10 (.A(in[16]), .B(in[17]), .Y(n[10]));
    sky130_fd_sc_hd__inv_1   g11 (.A(n[8]), .Y(n[11]));

    sky130_fd_sc_hd__nand2_1 g12 (.A(in[18]), .B(in[19]), .Y(n[12]));
    sky130_fd_sc_hd__nor2_1  g13 (.A(in[20]), .B(in[21]), .Y(n[13]));
    sky130_fd_sc_hd__and2_1  g14 (.A(in[22]), .B(in[23]), .Y(n[14]));
    sky130_fd_sc_hd__inv_1   g15 (.A(n[12]), .Y(n[15]));

    sky130_fd_sc_hd__nand2_1 g16 (.A(in[24]), .B(in[25]), .Y(n[16]));
    sky130_fd_sc_hd__nor2_1  g17 (.A(in[26]), .B(in[27]), .Y(n[17]));
    sky130_fd_sc_hd__and2_1  g18 (.A(in[28]), .B(in[29]), .Y(n[18]));
    sky130_fd_sc_hd__inv_1   g19 (.A(n[16]), .Y(n[19]));

    sky130_fd_sc_hd__nand2_1 g20 (.A(in[30]), .B(in[31]), .Y(n[20]));
    sky130_fd_sc_hd__nor2_1  g21 (.A(in[32]), .B(in[33]), .Y(n[21]));
    sky130_fd_sc_hd__and2_1  g22 (.A(in[34]), .B(in[35]), .Y(n[22]));
    sky130_fd_sc_hd__inv_1   g23 (.A(n[20]), .Y(n[23]));

    // Inter-channel comparator tree
    sky130_fd_sc_hd__nand2_1 g24 (.A(n[1]), .B(n[2]), .Y(n[24]));
    sky130_fd_sc_hd__and2_1  g25 (.A(n[3]), .B(n[24]), .Y(n[25]));
    sky130_fd_sc_hd__nor2_1  g26 (.A(n[5]), .B(n[6]), .Y(n[26]));
    sky130_fd_sc_hd__and2_1  g27 (.A(n[7]), .B(n[26]), .Y(n[27]));

    sky130_fd_sc_hd__nand2_1 g28 (.A(n[9]), .B(n[10]), .Y(n[28]));
    sky130_fd_sc_hd__and2_1  g29 (.A(n[11]), .B(n[28]), .Y(n[29]));
    sky130_fd_sc_hd__nor2_1  g30 (.A(n[13]), .B(n[14]), .Y(n[30]));
    sky130_fd_sc_hd__and2_1  g31 (.A(n[15]), .B(n[30]), .Y(n[31]));

    sky130_fd_sc_hd__nand2_1 g32 (.A(n[17]), .B(n[18]), .Y(n[32]));
    sky130_fd_sc_hd__and2_1  g33 (.A(n[19]), .B(n[32]), .Y(n[33]));
    sky130_fd_sc_hd__nor2_1  g34 (.A(n[21]), .B(n[22]), .Y(n[34]));
    sky130_fd_sc_hd__and2_1  g35 (.A(n[23]), .B(n[34]), .Y(n[35]));

    // Interrupt output generation
    sky130_fd_sc_hd__nand2_1 g_out0 (.A(n[25]), .B(n[27]), .Y(out[0]));
    sky130_fd_sc_hd__nor2_1  g_out1 (.A(n[29]), .B(n[31]), .Y(out[1]));
    sky130_fd_sc_hd__and2_1  g_out2 (.A(n[33]), .B(n[35]), .Y(out[2]));
    sky130_fd_sc_hd__nand2_1 g_out3 (.A(out[0]), .B(out[1]), .Y(out[3]));
    sky130_fd_sc_hd__nor2_1  g_out4 (.A(out[1]), .B(out[2]), .Y(out[4]));
    sky130_fd_sc_hd__and2_1  g_out5 (.A(out[0]), .B(out[2]), .Y(out[5]));
    sky130_fd_sc_hd__nand2_1 g_out6 (.A(out[3]), .B(out[4]), .Y(out[6]));

endmodule
