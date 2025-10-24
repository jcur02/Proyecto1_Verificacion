class ambiente #(parameter AW = 16, parameter DW = 32);

  // --- Instancias ---
  apb_driver   #(.AW(AW), .DW(DW)) apb_driver_inst;
  rx_driver    #(.DW(DW))          rx_driver_inst;
  tx_monitor   #(.DW(DW))          tx_monitor_inst;
  tx_checker   #(.DW(DW))          tx_checker_inst;
  tx_scoreboard#(.DW(DW))          scoreboard_inst;
  agent        #(.AW(AW), .DW(DW)) agent_inst;
  // Golden model para el checker
  i_golden_model#(.DW(DW))         golden;

  // --- Virtual IFs (se conectan desde el TB antes de run) ---
  virtual apb_if   #(.AW(AW), .DW(DW)) _apb_if; 
  virtual md_rx_if #(.DW(DW))          _rx_if;
  virtual md_tx_if #(.DW(DW))          _tx_if;

  // --- Mailboxes hacia/desde drivers/monitor/checker ---
  // Agent -> Drivers
  trans_apb_mbx   apb_agnt_drv_mbx;
  trans_md_rx_mbx rx_agnt_drv_mbx;

  // (Opcional) Test -> Agent (si el agent randomiza plantillas)
  trans_apb_mbx   apb_test_agnt_mbx;
  trans_md_rx_mbx rx_test_agnt_mbx;

  // Drivers -> Checker / Checker -> Scoreboard / Monitor -> Checker
  trans_apb_mbx     apb_drv_chkr_mbx;
  trans_md_rx_mbx   drv_chkr_mbx;
  trans_md_tx_mbx   mon_chkr_mbx;
  mailbox #(check_item#(.DW(DW))) chk_sb_mbx;

  // --- Ctor ---
  function new();
    // Mailboxes
    apb_agnt_drv_mbx = new();
    rx_agnt_drv_mbx  = new();
    apb_test_agnt_mbx= new(); // usa si tu agent randomiza plantillas
    rx_test_agnt_mbx = new(); // idem
    apb_drv_chkr_mbx = new();
    drv_chkr_mbx     = new();
    mon_chkr_mbx     = new();
    chk_sb_mbx       = new();

    // Instancias
    apb_driver_inst = new();
    rx_driver_inst  = new();
    tx_monitor_inst = new();

    // Golden model concreto (ajusta a tu DUT)
    golden = new golden_aligner#(.DW(DW))();

    // Checker y Scoreboard
    tx_checker_inst  = new(golden, drv_chkr_mbx, mon_chkr_mbx, chk_sb_mbx, apb_drv_chkr_mbx);
    scoreboard_inst  = new(chk_sb_mbx);

    // Agent
    agent_inst = new();

    // Conexiones de mailboxes
    apb_driver_inst.agnt_drv_mbx   = apb_agnt_drv_mbx;
    apb_driver_inst.drv_chkr_mbx   = apb_drv_chkr_mbx;

    rx_driver_inst.agnt_drv_mbx    = rx_agnt_drv_mbx;
    rx_driver_inst.drv_chkr_mbx    = drv_chkr_mbx;

    tx_monitor_inst.mon_chkr_mbx   = mon_chkr_mbx;

    agent_inst.apb_agnt_drv_mbx    = apb_agnt_drv_mbx;
    agent_inst.rx_agnt_drv_mbx     = rx_agnt_drv_mbx;

    // (Opcional) si tu agent randomiza plantillas que vienen del test:
    agent_inst.apb_test_agnt_mbx   = apb_test_agnt_mbx;
    agent_inst.rx_test_agnt_mbx    = rx_test_agnt_mbx;
  endfunction

  // Mét odo para conectar IFs desde el TB
  function void connect_ifs(
      virtual apb_if   #(.AW(AW), .DW(DW)) apb_vif,
      virtual md_rx_if #(.DW(DW))          rx_vif,
      virtual md_tx_if #(.DW(DW))          tx_vif
  );
    _apb_if = apb_vif;
    _rx_if  = rx_vif;
    _tx_if  = tx_vif;

    apb_driver_inst.vif = _apb_if;
    rx_driver_inst.vif  = _rx_if;
    tx_monitor_inst.vif = _tx_if;
  endfunction

  // Run
  virtual task run();
    // Sanidad mínima
    if (_apb_if == null || _rx_if == null || _tx_if == null) begin
      $fatal(1, "[ambiente] Virtual IFs no conectadas. Llama connect_ifs() antes de run()");
    end

    fork
      apb_driver_inst.run();
      rx_driver_inst.run();
      tx_monitor_inst.run();
      tx_checker_inst.run();
      scoreboard_inst.run();
      agent_inst.run();
    join_none
  endtask

endclass
