class tx_scoreboard #(parameter DW=32);
  mailbox #(check_item#(.DW(DW))) chk_sb_mbx;

  // Métricas
  int total, pass, fail;
  longint sum_lat, sum_ret_rx, sum_ret_tx;
  bit verbose = 1;

  function new(mailbox #(check_item#(.DW(DW))) mbx);
    chk_sb_mbx = mbx;
    total = pass = fail = 0;
    sum_lat = sum_ret_rx = sum_ret_tx = 0;
  endfunction

  task run();
    $display("[%0t] TX Scoreboard inicializado", $time);
    forever begin
      check_item#(.DW(DW)) it;
      chk_sb_mbx.get(it);

      total++;
      if (it.rx_in  != null) sum_ret_rx += it.rx_in.retardo;
      if (it.got_tx != null) sum_ret_tx += it.got_tx.retardo;
      sum_lat += it.lat;

      if (it.ok) begin
        pass++;
        if (verbose) $display("[%0t] %s OK (lat=%0d)", $time, it.tag, it.lat);
      end else begin
        fail++;
        $display("[%0t] %s MISMATCH", $time, it.tag);
        it.print();
      end
    end
  endtask

  task report();
    real avg_lat = (total>0)? real'(sum_lat)/total : 0.0;
    real avg_rrx = (total>0)? real'(sum_ret_rx)/total : 0.0;
    real avg_rtx = (total>0)? real'(sum_ret_tx)/total : 0.0;
    $display("===============================================");
    $display("  TX SCOREBOARD REPORT");
    $display("   Total: %0d  Pass: %0d  Fail: %0d", total, pass, fail);
    $display("   Latencia promedio: %0.2f", avg_lat);
    $display("   Retardo RX prom.:  %0.2f", avg_rrx);
    $display("   Retardo TX prom.:  %0.2f", avg_rtx);
    $display("===============================================");
  endtask
endclass
