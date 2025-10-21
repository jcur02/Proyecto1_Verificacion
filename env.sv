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

// Interfaces
// Interfaz APB para la comunicacion con los registros
interface apb_if #(parameter AW=16, DW=32) (input logic clk);
  logic [AW-1:0] paddr;  
  logic          pwrite, psel, penable;
  logic [DW-1:0] pwdata;
  logic          pready;
  logic [DW-1:0] prdata;
  logic          pslverr;

  task automatic write(input logic [AW-1:0] addr, input logic [DW-1:0] data);
    @(negedge clk);
    paddr<=addr; pwdata<=data; pwrite<=1; psel<=1; penable<=0;
    @(negedge clk);
    penable<=1; while(!pready) @(negedge clk);
    @(negedge clk);
    psel<=0; penable<=0; pwrite<=0; paddr<='0; pwdata<='0;
  endtask

  task automatic read(input logic [AW-1:0] addr, output logic [DW-1:0] data);
    @(negedge clk);
    paddr<=addr; pwrite<=0; psel<=1; penable<=0;
    @(negedge clk);
    penable<=1; while(!pready) @(negedge clk);
    data = prdata;
    @(negedge clk);
    psel<=0; penable<=0; paddr<='0;
  endtask
endinterface

// Interfaz MD para RX
interface md_rx_if #(parameter DW=32, OW=$clog2(DW/8), SW=$clog2(DW/8)+1) (input logic clk);
  logic                    valid;
  logic [DW-1:0]          data;
  logic [OW-1:0]          offset;
  logic [SW-1:0]          size;
  logic                    ready;
  logic                    err;
endinterface

// Interfaz MD para TX
interface md_tx_if #(parameter DW=32, OW=$clog2(DW/8), SW=$clog2(DW/8)+1) (input logic clk);
  logic                    valid;
  logic [DW-1:0]          data;
  logic [OW-1:0]          offset;
  logic [SW-1:0]          size;
  logic                    ready;
  logic                    err;
endinterface