// interfaz del apb
interface apb_if #(parameter AW = 16, DW = 32 ) (input bit clk);
    logic [AW-1:0] paddr; // address
    logic pwrite, psel, penable; 
    logic [DW-1:0] pwdata // dato a escribir
    logic pready, pslverr
    logic [DW-1:0] prdata // dato leido
endinterface

// interfaz del MD RX
interface md_rx_if #(parameter DW = 32) (input bit clk);
    logic md_rx_valid;
    logic [DW-1:0] md_rx_data;
    logic [1:0] md_rx_offset;
    logic [2:0] md_rx_size;
    logic md_rx_ready, md_rx_err;
endinterface

// interfaz del MD TX
interface md_tx_if #(parameter DW = 32) (input bit clk);
    logic md_tx_valid;
    logic [DW-1:0] md_tx_data;
    logic [1:0] md_tx_offset;
    logic [2:0] md_tx_size;
    logic md_tx_ready, md_tx_err;
endinterface