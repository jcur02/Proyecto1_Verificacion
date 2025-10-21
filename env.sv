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

// RX Driver
class rx_driver;
  virtual md_rx_if vif;
  function new(virtual md_rx_if vif); 
    this.vif=vif; 
  endfunction

  task send(rx_item item);
    @(negedge vif.clk);
    vif.data   <= item.tr.data;
    vif.size   <= item.tr.rx_size;
    vif.offset <= item.tr.rx_offset;
    vif.valid  <= 1'b1;
    while(!vif.ready) @(negedge vif.clk);
    vif.valid <= 1'b0;
  endtask
endclass

// TX Monitor
class tx_monitor;
  virtual md_tx_if vif;
  mailbox #(logic [31:0]) m_data;
  mailbox #(int)          m_size, m_off;
  function new(virtual md_tx_if vif);
    this.vif=vif; m_data=new(); m_size=new(); m_off=new();
  endfunction
  task run();
    bit fired_d;
    forever begin
      @(posedge vif.clk);
      fired_d = vif.valid && vif.ready;
      if (fired_d) begin
        m_data.put(vif.data);
        m_size.put(vif.size);
        m_off.put(vif.offset);
      end
    end
  endtask
endclass

// APB Driver/Monitor
class apb_agent;
  virtual apb_if vif;
  function new(virtual apb_if vif); 
    this.vif = vif; 
  endfunction
  task write(int unsigned addr, int unsigned data); 
    vif.write(addr, data);
  endtask
  task read (int unsigned addr, output int unsigned data); 
    vif.read(addr, data); 
  endtask
endclass

// Logger
class csv_logger;
  integer fd;
  function void open(string path="report.csv");
    fd = $fopen(path, "w");
    $fdisplay(fd, "time,phase,rx_data,rx_size,rx_offset,tx_data,tx_size,tx_offset,status,irq");
  endfunction
  function void log(string phase,
                    logic [31:0] rx_d, int rx_sz, int rx_of,
                    logic [31:0] tx_d, int tx_sz, int tx_of,
                    logic [31:0] status, logic [31:0] irq);
    $fdisplay(fd, "%0t,%s,0x%08x,%0d,%0d,0x%08x,%0d,%0d,0x%08x,0x%08x",
              $time, phase, rx_d, rx_sz, rx_of, tx_d, tx_sz, tx_of, status, irq);
  endfunction
endclass

// Coverage group
class coverage_cov;
  int csz, cof, rsz, rof;
  covergroup cg;
    coverpoint csz { bins s1={1}; bins s2={2}; bins s4={4}; } // control size
    coverpoint cof { bins o[]={[0:3]}; } // control offset
    coverpoint rsz { bins r1={1}; bins r2={2}; bins r4={4}; } // rx size
    coverpoint rof { bins ro[]={[0:3]}; } // rx offset
    cross csz, cof, rsz, rof;
  endgroup
  function new(); cg=new; endfunction
  function void sample(int c_sz, int c_of, int r_sz, int r_of);
    csz=c_sz; cof=c_of; rsz=r_sz; rof=r_of; cg.sample();
  endfunction
endclass

// Scoreboard
class scoreboard;
  apb_agent   apb;
  csv_logger  logger;
  coverage_cov cov;
  int unsigned ADDR_STATUS=32'h000C, ADDR_IRQ=32'h00F4, ADDR_CTRL=32'h0000, ADDR_IRQEN=32'h00F0;

  function new(apb_agent apb);
    this.apb=apb; logger=new; cov=new;
  endfunction

  task configure_ctrl(ctrl_item_s ctrl);
    int unsigned ctrl_val;
    ctrl_val = (ctrl.ctrl_offset<<8) | ctrl.ctrl_size; 
    apb.write(ADDR_IRQEN, 32'h7);
    apb.write(ADDR_CTRL , ctrl_val);
  endtask

  task log_rx(rx_item_s rx);
    int unsigned st, iq;
    apb.read(ADDR_STATUS, st);
    apb.read(ADDR_IRQ   , iq);
    logger.log("rx", rx.data, rx.rx_size, rx.rx_offset,
               32'h0000_0000, -1, -1, st, iq);
  endtask

  task check_and_log(string phase,
                     rx_item_s rx,
                     logic [31:0] tx_d, int tx_sz, int tx_of);
    int unsigned st, iq;
    apb.read(ADDR_STATUS, st);
    apb.read(ADDR_IRQ   , iq);
    logger.log(phase, rx.data, rx.rx_size, rx.rx_offset, tx_d, tx_sz, tx_of, st, iq);
    cov.sample(tx_sz, tx_of, rx.rx_size, rx.rx_offset);
  endtask
endclass
