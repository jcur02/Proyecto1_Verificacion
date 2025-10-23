`timescale 1ns/1ps

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

// Paquetes
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

package aligner_ref;
  function automatic int compute(
      input  logic [31:0] data,
      input  int          rx_size, rx_off,
      input  int          ctrl_size, ctrl_off,
      output logic [31:0] beats [4],
      output int          tx_off_each [4],
      output int          tx_size_each [4]
  );
    logic [31:0] window, mask, piece;
    int n, remain, consumed, chunk;

    window   = data >> (8*rx_off);
    n        = 0;
    remain   = rx_size;
    consumed = 0;

    while (remain > 0) begin
      chunk = (ctrl_size <= remain) ? ctrl_size : remain;
      case (chunk)
        1: mask = 32'h000000FF;
        2: mask = 32'h0000FFFF;
        3: mask = 32'h00FFFFFF;
        default: mask = 32'hFFFFFFFF;
      endcase
      piece = (window >> (8*consumed)) & mask;
      beats[n]        = piece << (8*ctrl_off);
      tx_off_each[n]  = ctrl_off;
      tx_size_each[n] = chunk;
      n++;
      remain   -= chunk;
      consumed += chunk;
    end
    return n;
  endfunction
endpackage

import aligner_pkg::*;
import aligner_ref::*;

// -------------------- Clases --------------------
class rand_cfg;
  rand int unsigned num_rx;    
  rand int unsigned gap_min;
  rand int unsigned gap_max;
  rand ctrl_item_s  ctrl;

  constraint c_num  { num_rx inside {[2:32]}; } // cantidad de datos a entrar
  constraint c_gap1 { gap_min inside {[0:10]}; } // tiempo minimo entre envio
  constraint c_gap2 { gap_max inside {[gap_min:20]}; } // tiempo maximo entre envio
  constraint c_ctrl { ctrl.ctrl_size inside {1,2,4}; ctrl.ctrl_offset inside {[0:3]}; } // size y offset de control
  constraint c_ctrl_legal { (ctrl.ctrl_size!=4) || (ctrl.ctrl_offset==0); } // asegurarse que sea correcto

endclass

class rx_item;
  rand rx_item_s tr;
  constraint c_sz { tr.rx_size inside {1,2,4}; }
  constraint c_of { tr.rx_offset inside {[0:3]}; }

  constraint c_legal { (tr.rx_size!=4) || (tr.rx_offset==0); }
  function void randomize_data(); tr.data = $urandom(); endfunction
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

// APB Driver/Monitor
class apb_agent;
  virtual apb_if vif;
  function new(virtual apb_if vif); this.vif = vif; endfunction
  task write(int unsigned addr, int unsigned data); vif.write(addr, data); endtask
  task read (int unsigned addr, output int unsigned data); vif.read(addr, data); endtask
endclass

// RX Driver
class rx_driver;
  virtual md_rx_if vif;
  function new(virtual md_rx_if vif); this.vif=vif; endfunction
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

// env
module tb_aligner_rand;

  function automatic bit is_rx_legal(aligner_pkg::rx_item_s rx);
    bit size_ok, off_ok, fit_ok, align4_ok;
    size_ok   = (rx.rx_size==1) || (rx.rx_size==2) || (rx.rx_size==4);
    off_ok    = (rx.rx_offset>=0) && (rx.rx_offset<=3);
    fit_ok    = ((rx.rx_offset + rx.rx_size) <= 4);   
    align4_ok = !(rx.rx_size==4 && rx.rx_offset!=0);  
    return size_ok && off_ok && fit_ok && align4_ok;
  endfunction
 
  localparam int DW=32; localparam int AW=16; localparam int APBDW=32;
  localparam int OW=(DW<=8)?1:$clog2(DW/8);
  localparam int SW=$clog2(DW/8)+1;

  // Clock y reset
  logic clk=0, reset_n=0; always #5 clk=~clk; 

  // Interfaces
  apb_if   #(AW,APBDW) apb(clk);
  md_rx_if #(DW,OW,SW) md_rx(clk);
  md_tx_if #(DW,OW,SW) md_tx(clk);

  initial begin
    md_tx.ready = 1'b1; 
    md_rx.valid = 1'b0; md_rx.data='0; md_rx.size='0; md_rx.offset='0;
  end

  // DUT 
  cfs_aligner #(.ALGN_DATA_WIDTH(DW), .FIFO_DEPTH(8)) dut (
    .clk(clk), .reset_n(reset_n),
    .paddr(apb.paddr), .pwrite(apb.pwrite), .psel(apb.psel), .penable(apb.penable),
    .pwdata(apb.pwdata), .pready(apb.pready), .prdata(apb.prdata), .pslverr(apb.pslverr),
    .md_rx_valid(md_rx.valid), .md_rx_data(md_rx.data), .md_rx_offset(md_rx.offset), .md_rx_size(md_rx.size), .md_rx_ready(md_rx.ready), .md_rx_err(md_rx.err),
    .md_tx_valid(md_tx.valid), .md_tx_data(md_tx.data), .md_tx_offset(md_tx.offset), .md_tx_size(md_tx.size), .md_tx_ready(md_tx.ready), .md_tx_err(md_tx.err),
    .irq()
  );

  // VCD
  initial begin
    $dumpfile("aligner_rand.vcd");
    $dumpvars(0, tb_aligner_rand);
  end

  // Componentes
  apb_agent apb_ag = new(apb);
  rx_driver drv    = new(md_rx);
  tx_monitor mon   = new(md_tx);
  scoreboard scb   = new(apb_ag);
  rand_cfg  cfg;

  // run monitor
  initial fork mon.run(); join_none

  // Reset
  task automatic do_reset();
    begin
      repeat(5) @(negedge clk); reset_n<=0;
      repeat(5) @(negedge clk); reset_n<=1;
    end
  endtask

  function automatic int pick_size();
    int sel; sel=$urandom_range(0,2);
    return (sel==0)?1:((sel==1)?2:4);
  endfunction

  // test
  initial begin : MAIN
    int seed;
    int i, b, t;
    int gap_min, gap_max, num_rx;
    int ctrl_size, ctrl_off;
    rx_item it;
    rx_item_s rx_s;
    int beats_caught, gap;
    logic [31:0] tdata; int tsz, tof;

    // semilla
    if ($value$plusargs("seed=%d", seed)) begin void'($urandom(seed)); end
    else begin seed = $urandom(); end
    $display("[TB] seed=%0d", seed);

    // CSV
    scb.logger.open("report.csv");

    // Reset
    do_reset();

    // Randomizar global cfg
    cfg = new();
    if (!cfg.randomize()) $fatal("cfg randomize failed");

    // control
    scb.configure_ctrl(cfg.ctrl);
    $display("[CFG] initial ctrl(size=%0d,off=%0d) num_rx=%0d", cfg.ctrl.ctrl_size, cfg.ctrl.ctrl_offset, cfg.num_rx);

    // Tiempos de espera randomizados
    gap_min = cfg.gap_min; gap_max = cfg.gap_max; num_rx = cfg.num_rx;

    // Generar RX items
    for (i=0; i<num_rx; i++) begin
      ctrl_item_s dyn_ctrl;
      dyn_ctrl.ctrl_size   = pick_size();
      dyn_ctrl.ctrl_offset = (dyn_ctrl.ctrl_size==4) ? 0 : $urandom_range(0,3);

      if ((i % 8) == 0) begin
        dyn_ctrl.ctrl_size   = 4;
        dyn_ctrl.ctrl_offset = 0;
      end
      scb.configure_ctrl(dyn_ctrl);
      $display("[CTRL] iter=%0d -> size=%0d off=%0d", i, dyn_ctrl.ctrl_size, dyn_ctrl.ctrl_offset);

      it = new(); void'(it.randomize()); it.randomize_data();
      drv.send(it);
      if (is_rx_legal(it.tr)) begin
        scb.log_rx(it.tr);
      end

      beats_caught = 0;
      for (b=0; b<4; b++) begin
        t=20;
        while (t>0) begin
          if (mon.m_data.try_get(tdata)) begin
            mon.m_size.get(tsz); mon.m_off.get(tof);
            scb.check_and_log("tx", it.tr, tdata, tsz, tof);
            beats_caught++;
            break;
          end
          @(posedge clk); t--; 
        end
        if (t==0) break; 
      end

      gap = gap_min + $urandom_range(0, (gap_max-gap_min));
      repeat(gap) @(negedge clk);
    end

    $display("[TB] Completed randomized run.");
    #100 $finish;
  end
endmodule
