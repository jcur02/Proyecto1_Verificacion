`timescale 1ns/1ps

// Transacciones
package aligner_pkg;
  typedef struct packed {
    logic [31:0] data;
    logic [1:0]  rx_offset;   
    logic [2:0]  rx_size;     
  } rx_item_s; // Item que se enviará al RX

  typedef struct packed {
    logic [1:0]  ctrl_offset; 
    logic [2:0]  ctrl_size;   
  } ctrl_item_s; // Item que se usará para el control
endpackage

class rx_item;
  rand rx_item_s tr;
  constraint c_sz { tr.rx_size inside {1,2,4}; }
  constraint c_of { tr.rx_offset inside {[0:3]}; }
  constraint c_legal { (tr.rx_size!=4) || (tr.rx_offset==0); }
  function void randomize_data(); tr.data = $urandom(); endfunction
endclass