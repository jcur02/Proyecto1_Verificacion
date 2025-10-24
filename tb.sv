`timescale 1ns/1ps

// =====================================================
// TB TOP: clock/reset, interfaces, DUT, ambiente, correr
// =====================================================
module tb_top;
  localparam int AW = 16;
  localparam int DW = 32;
  localparam time TCK = 10ns;

  // Clock global (lo usa el checker con $root.tb_clk)
  logic tb_clk;
  initial tb_clk = 0;
  always #(TCK/2) tb_clk = ~tb_clk;

  // Reset asíncrono activo en bajo, sincr. adentro si querés
  logic rst_n;
  initial begin
    rst_n = 0;
    repeat (5) @(posedge tb_clk);
    rst_n = 1;
  end

  // Interfaces (amarradas al clock del TB)
  apb_if   #(.AW(AW), .DW(DW)) apb_vif (tb_clk);
  md_rx_if #(.DW(DW))          rx_vif  (tb_clk);
  md_tx_if #(.DW(DW))          tx_vif  (tb_clk);

  // DUT (ajusta el nombre del módulo/puertos si difieren en tu design.v)
  // Asumo puertos estándar:
  //   input  clk, input rst_n
  //   APB:   paddr, pwrite, psel, penable, pwdata, prdata, pready, pslverr
  //   MD RX: md_rx_valid, md_rx_data, md_rx_offset, md_rx_size, md_rx_ready, md_rx_err
  //   MD TX: md_tx_valid, md_tx_data, md_tx_offset, md_tx_size, md_tx_ready, md_tx_err
  design cfs_aligner (
    .clk          (tb_clk),
    .rst_n        (rst_n),

    // APB
    .paddr        (apb_vif.paddr),
    .pwrite       (apb_vif.pwrite),
    .psel         (apb_vif.psel),
    .penable      (apb_vif.penable),
    .pwdata       (apb_vif.pwdata),
    .prdata       (apb_vif.prdata),
    .pready       (apb_vif.pready),
    .pslverr      (apb_vif.pslverr),

    // MD RX (entrada al DUT; las maneja el rx_driver)
    .md_rx_valid  (rx_vif.md_rx_valid),
    .md_rx_data   (rx_vif.md_rx_data),
    .md_rx_offset (rx_vif.md_rx_offset),
    .md_rx_size   (rx_vif.md_rx_size),
    .md_rx_ready  (rx_vif.md_rx_ready),
    .md_rx_err    (rx_vif.md_rx_err),

    // MD TX (salida del DUT; la observa el tx_monitor)
    .md_tx_valid  (tx_vif.md_tx_valid),
    .md_tx_data   (tx_vif.md_tx_data),
    .md_tx_offset (tx_vif.md_tx_offset),
    .md_tx_size   (tx_vif.md_tx_size),
    .md_tx_ready  (tx_vif.md_tx_ready),
    .md_tx_err    (tx_vif.md_tx_err)
  );

  // Ambiente
  ambiente#(.AW(AW), .DW(DW)) env = new();

  // Conectar IFs
  initial begin
    env.connect_ifs(apb_vif, rx_vif, tx_vif);

    // Opcional: knobs del agente
    env.agent_inst.max_retardo = 6;  // el agente randomiza retardo en [0..6]
    env.agent_inst.verbose     = 1;

    // ¡Correr el ambiente! (drivers/monitor/checker/scoreboard/agent)
    env.run();

    // Lanzar el test
    test_basic#(.AW(AW), .DW(DW)) t = new(env);
    // Espera a que salga de reset para no empujar APB antes de tiempo
    @(posedge rst_n);
    repeat (2) @(posedge tb_clk);
    t.run();

    // Tiempo de corrida y reporte final del scoreboard
    repeat (1000) @(posedge tb_clk);
    env.scoreboard_inst.report();
    $finish;
  end

endmodule
