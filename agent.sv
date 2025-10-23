// ===============================================================
// Agent que RANDOMIZA el item recibido del test:
// - Si un campo viene fijado (sin X/Z), se bloquea con rand_mode(0)
// - Se llama .randomize() con constraints del agente
// - Se reenvía al driver por su mailbox
// ===============================================================
class agent #(parameter AW = 16, parameter DW = 32);

  // Mailboxes: TEST -> AGENTE
  trans_apb_mbx   apb_test_agnt_mbx;
  trans_md_rx_mbx rx_test_agnt_mbx;

  // Mailboxes: AGENTE -> DRIVERS
  trans_apb_mbx   apb_agnt_drv_mbx;
  trans_md_rx_mbx rx_agnt_drv_mbx;

  // Knobs del agente
  int max_retardo = 10;
  bit verbose     = 1;

  function new(); endfunction

  // ---------- Helpers ----------
  // ¿El escalar 1-bit es 0/1 (no X/Z)?
  function automatic bit is_known_1b(bit v);
    return (v === 1'b0) || (v === 1'b1);
  endfunction

  // ¿El vector no contiene X/Z?
  function automatic bit is_known_vec(logic [DW-1:0] v);
    return (^v !== 1'bx); // reducción XOR devuelve X si hay X/Z en v
  endfunction

  // Overloads para otros anchos (offset/size típicamente chicos)
  function automatic bit is_known_vec_n(logic [31:0] v);
    return (^v !== 1'bx);
  endfunction

  // ---------- APB ----------
  task apb_loop();
    $display("[%0t] AGENT(APB) iniciado", $time);
    forever begin
      trans_apb#(.AW(AW), .DW(DW)) t;
      apb_test_agnt_mbx.get(t);

      // Bloquear campos que vengan ya fijados (si son rand en tu clase)
      // NOTA: en tu definición original, 'retardo' es rand (usa el tipo que corresponda)
      if (is_known_vec_n(t.paddr))   t.paddr.rand_mode(0);
      if (is_known_vec(t.pwdata))    t.pwdata.rand_mode(0);
      // Si 'tipo' es rand, también podrías bloquearlo si viene fijado:
      // t.tipo.rand_mode(0);

      // Randomize con límites del agente
      // (ajusta dominios según tu mapa/escenarios)
      if (!t.randomize() with {
          // retardo ∈ [0 .. max_retardo]
          t.retardo inside {[0:max_retardo]};
        })
      begin
        $error("[%0t] AGENT(APB) randomize() falló", $time);
      end

      // Rehabilitar rand_mode si querés reusar 't' (no necesario si no lo reusas)
      // t.paddr.rand_mode(1); t.pwdata.rand_mode(1);

      // Forward al driver
      if (apb_agnt_drv_mbx == null) begin
        $error("[%0t] [AGENT][APB] mailbox a driver no conectado", $time);
      end else begin
        apb_agnt_drv_mbx.put(t);
        if (verbose) t.print("AGENT->APB (randomized)");
      end
    end
  endtask

  // ---------- RX ----------
  task rx_loop();
    $display("[%0t] AGENT(RX) iniciado", $time);
    forever begin
      trans_md_rx#(.DW(DW)) t;
      rx_test_agnt_mbx.get(t);

      // Lock de campos fijados por el test (si son rand en tu clase)
      if (is_known_1b(t.md_rx_valid))      t.md_rx_valid.rand_mode(0);
      if (is_known_vec(t.md_rx_data))      t.md_rx_data.rand_mode(0);
      // offset/size suelen ser chicos; ajusta ancho si es 2/3 bits:
      if ((^t.md_rx_offset !== 1'bx))      t.md_rx_offset.rand_mode(0);
      if ((^t.md_rx_size   !== 1'bx))      t.md_rx_size.rand_mode(0);

      // Randomize con políticas del agente
      if (!t.randomize() with {
          // retardo ∈ [0..max_retardo]
          t.retardo inside {[0:max_retardo]};
          // size permitido (ajusta a tu DUT): {1,2,4}
          t.md_rx_size inside {1,2,4};
        })
      begin
        $error("[%0t] AGENT(RX) randomize() falló", $time);
      end

      // Forward al driver
      if (rx_agnt_drv_mbx == null) begin
        $error("[%0t] [AGENT][RX] mailbox a driver no conectado", $time);
      end else begin
        rx_agnt_drv_mbx.put(t);
        if (verbose) t.print("AGENT->RX (randomized)");
      end
    end
  endtask

  // ---------- Run ----------
  task run();
    $display("[%0t] El agente (randomizer proxy) fue inicializado", $time);
    fork
      apb_loop();
      rx_loop();
    join_none
  endtask

endclass
