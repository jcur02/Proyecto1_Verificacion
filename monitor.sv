// Monitor del MD TX 
class tx_monitor #(parameter DW = 32);
    virtual md_tx_if #(.DW(DW)) vif;
    trans_md_tx_mbx mon_chkr_mbx;
    int espera; 

    task run();
        $display("[%0t] El monitor del TX fue inicializado", $time);

        forever begin
            trans_md_tx #(.DW(DW)) transaction;
            $display("[%0t] El Monitor del TX espera una transaccion", $time);

            @(posedge vif.clk);
            while (!vif.md_tx_valid)
                @(posedge vif.clk);

            espera = 0;
            while (!(vif.md_tx_valid && vif.md_tx_ready)) begin
                @(posedge vif.clk);
                if (vif.md_tx_valid && !vif.md_tx_ready)
                    espera++;
                if (!vif.md_tx_valid) begin
                    while (!vif.md_tx_valid)
                        @(posedge vif.clk);
                    espera = 0;
                end
            end

            transaction.md_tx_valid  = 1'b1;           
            transaction.md_tx_ready  = 1'b1;
            transaction.md_tx_data   = vif.md_tx_data;
            transaction.md_tx_offset = vif.md_tx_offset;
            transaction.md_tx_size   = vif.md_tx_size;
            transaction.md_tx_err    = vif.md_tx_err;

            transaction.retardo = espera;             
            transaction.tiempo  = $time;               

            mon_chkr_mbx.put(transaction);
            transaction.print("TX Monitor: Transaccion observada");

            @(posedge vif.clk);
        end
    endtask
endclass