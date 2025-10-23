// Driver / Monitor del APB
class apb_driver #(parameter AW = 15, DW = 32);
    virtual apb_if #(.AW(AW), .DW(DW)) vif;
    trans_apb_mbx agnt_drv_mbx;
    trans_apb_mbx drv_chkr_mbx;
    int espera;

    task run();
        $display("[%0t] El driver del APB fue inicializado", $time);

        forever begin
            trans_apb #(.AW(AW), .DW(DW)) transaction;

            // Reset de señales
            vif.paddr   = 0;
            vif.pwrite  = 0;
            vif.psel    = 0;
            vif.penable = 0;
            vif.pwdata  = 0;

            $display("[%0t] El Driver del APB espera una transacción", $time);
            agnt_drv_mbx.get(transaction);
            transaction.print("APB Driver: Transacción recibida");
            $display("Transacciones pendientes en agent_drv = %0d", agnt_drv_mbx.num());

            // Retardo antes de iniciar
            espera = 0;
            while (espera < transaction.retardo) begin
                @(posedge vif.clk);
                espera++;
            end

            // --- Setup Phase ---
            @(posedge vif.clk);
            vif.paddr  = transaction.paddr;
            vif.pwrite = (transaction.tipo == escritura);
            vif.pwdata = transaction.pwdata;
            vif.psel   = 1;
            vif.penable = 0;

            // --- Access Phase ---
            @(posedge vif.clk);
            vif.penable = 1;

            // Esperar a que el esclavo esté listo
            wait (vif.pready == 1);

            // Handshake completado
            transaction.tiempo = $time;
            transaction.pready = vif.pready;
            transaction.pslverr = vif.pslverr;
            if (transaction.tipo == lectura)
                transaction.prdata = vif.prdata;

            drv_chkr_mbx.put(transaction);
            transaction.print("APB Driver: Transacción ejecutada");

            // --- Finalización ---
            @(posedge vif.clk);
            vif.psel    = 0;
            vif.penable = 0;
            vif.pwrite  = 0;
        end
    endtask
endclass


// Driver del MD RX
class rx_driver #(parameter DW = 32);
    virtual md_rx_if #(.DW(DW)) vif;
    trans_md_rx_mbx agnt_drv_mbx;
    trans_md_rx_mbx drv_chkr_mbx;
    int espera;

    task run();
        $display("[%0t] El driver del RX fue inicializado", $time);

        forever begin
            trans_md_rx #(.DW(DW)) transaction;

            // Reset de señales
            vif.md_rx_valid  = 0;
            vif.md_rx_data   = 0;
            vif.md_rx_offset = 0;
            vif.md_rx_size   = 0;

            $display("[%0t] El Driver del RX espera una transaccion", $time);
            agnt_drv_mbx.get(transaction);
            transaction.print("RX Driver: Transaccion recibida");
            $display("Transacciones pendientes en agent_drv = %0d", agnt_drv_mbx.num());

            // Retardo antes de enviar
            espera = 0;
            while (espera < transaction.retardo) begin
                @(posedge vif.clk);
                espera++;
            end

            // Colocar valores de la transacción
            vif.md_rx_valid  = transaction.md_rx_valid;
            vif.md_rx_data   = transaction.md_rx_data;
            vif.md_rx_offset = transaction.md_rx_offset;
            vif.md_rx_size   = transaction.md_rx_size;

            // Esperar a que el DUT esté listo (handshake)
            @(posedge vif.clk);
            while (!vif.md_rx_ready)
                @(posedge vif.clk);

            // Handshake completado
            transaction.tiempo = $time;
            drv_chkr_mbx.put(transaction);
            transaction.print("RX Driver: Transaccion ejecutada");

            // Bajar valid
            @(posedge vif.clk);
            vif.md_rx_valid = 0;
        end
    endtask
endclass