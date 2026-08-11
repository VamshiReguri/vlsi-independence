// Day 5 PDK experiment: the smallest possible netlist.
//
// One sky130hd inverter (drive strength 2) wrapped in a top module so OpenSTA
// can link it against the liberty and we can drive exactly one timing arc
// (A -> Y) by hand. The cell's power pins (VPWR/VGND/VPB/VNB) are intentionally
// left unconnected: OpenSTA links leaf cells by name against the .lib and needs
// only the signal pins for delay calculation.
module tiny_inv (A, Y);
  input  A;
  output Y;

  sky130_fd_sc_hd__inv_2 u0 (
    .A(A),
    .Y(Y)
  );
endmodule
