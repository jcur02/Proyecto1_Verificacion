class ambiente #(parameter AW = 16, parameter DW = 32);
    apb_driver #(.AW(AW), .DW(DW)) apb_driver_inst;
    rx_driver #(.DW(DW)) rx_driver_inst;
    tx_monitor #(.DW(DW)) tx_monitor_inst
    tx_checker #(.DW(DW)) tx_monitor_inst;
    score_board #(.DW(DW)) scoreboard_inst;
    agent #(.AW(AW), .DW(DW)) agent_inst;

    virtual apb_if #(.AW(AW), .DW(DW)) _apb_if; 
    virtual md_rx_if #(.DW(DW)) _rx_if;
    virtual md_tx_if #(.DW(DW)) _tx_if;

    trans_apb_mbx apb_agnt_drv_mbx;
    trans_rx_mbx rx_agnt_drv_mbx;
    trans_md_tx_mbx mon_chkr_mbx;
    trans_md_rx_mbx drv_chkr_mbx;
    trans_apb_mbx   apb_drv_chkr_mbx;

    function new();
        apb_drv_chkr_mbx = new();
        drv_chkr_mbx = new();
        mon_chkr_mbx = new();
        rx_agnt_drv_mbx = new();
        apb_agnt_drv_mbx = new();

        apb_driver_inst = new();
        rx_driver_inst = new();
        tx_monitor_inst = new();
        tx_monitor_inst = new();
        scoreboard_inst = new();
        agent_inst = new();

        apb_driver_inst.vif = apb_driver_inst;
        apb_driver_inst.agnt_drv_mbx = apb_agnt_drv_mbx;
        apb_driver_inst.drv_chkr_mbx = apb_drv_chkr_mbx;
        
endclass