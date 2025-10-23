// tipo de transacciones posibles en el APB
typedef enum { lectura, escritura } tipo_trans;

// Objeto de transaccion que entran y salen del APB
class trans_apb #(parameter AW = 16, DW = 32);
    rand bit retardo; // tiempo de retardo en ciclos de reloj que se debe esperar antes de ejecutrar la transaccion
    rand bit [AW-1:0] paddr; // address
    rand bit [DW-1:0] pwdata // dato a escribir
    bit pready, pslverr
    bit [DW-1:0] prdata // dato leido
    int tiempo; // tiempo de la simulacion en que se ejecuto la transaccion
    rand tipo_trans tipo; // lectura o escritura
    int max_retardo;

    constraint const_retardo {retardo < max_retardo; retardo > 0;}

    function new(int ret = 0, bit[AW-1:0] addr = 0, bit [DW-1:0] wdt = 0, bit rdy = 0, bit slver = 0, bit [DW-1:0] rdt = 0, int tmp = 0, tipo_trans tpo = lectura, int max_rtrd = 10);
        this.retardo = ret;
        this.paddr = addr;
        this.pwdata = wdt;
        this.pready = rdy;
        this.pslverr = slver;
        this.prdata = rdt;
        this.tiempo = tmp;
        this.tipo = tpo;
        this.max_retardo = max_rtrd;
    endfunction

    function clean;
        this.retardo = 0;
        this.paddr = 0;
        this.pwdata = 0;
        this.pready = 0;
        this.pslverr = 0;
        this.prdata = 0;
        this.tiempo = 0;
        this.tipo = lectura;
    endfunction

    function void print (string tag="");
        $display("[%g] %s Tiempo=%g Tipo=%s Retardo=%g Wdata=0x%h Rdata=0x%h", $time, tag, tiempo, this.tipo, this.retardo, this.pwdata, this.prdata);
    endfunction
    
endclass

// Objeto de transaccion usado para el MD RX (entrada)
class trans_md_rx #(parameter DW = 32);
    rand int retardo;
    rand bit md_rx_valid;
    rand bit [DW-1:0] md_rx_data;
    rand bit [1:0] md_rx_offset;
    rand bit [2:0] md_rx_size;
    bit md_rx_ready, md_rx_err;
    int tiempo, max_retardo;

    constraint c_sz { md_rx_size inside {1,2,4}; }

    function new(int ret = 0, bit vld = 0, bit [DW-1:0] dta = 0, bit of = 0, bit sz = 1, bit rdy = 0, bit er = 0, int tmp = 0, int max_rtrd = 10);
        this.retardo = ret;
        this.md_rx_valid = vld;
        this.md_rx_data = dta;
        this.md_rx_offset = of;
        this.md_rx_size = sz;
        this.md_rx_ready = rdy;
        this.md_rx_err = er;
        this.tiempo = tmp;
        this.max_retardo = max_rtrd;
    endfunction

    function clean;
        this.retardo = 0;
        this.md_rx_valid = 0;
        this.md_rx_data = 0;
        this.md_rx_offset = 0;
        this.md_rx_size = 1;
        this.md_rx_ready = 0;
        this.md_rx_err = 0;
        this.tiempo = 0;
    endfunction

    function void print (string tag="");
        $display("[%g] %s Tiempo=%g Retardo=%g Dato=0x%h Size=%d Offset=%d", $time, tag, tiempo, this.retardo, this.md_rx_data, this.md_rx_size, this.md_rx_offset);
    endfunction
endclass

// Objeto de transaccion usado para el MD TX (salida)
class trans_md_tx #(parameter DW = 32);
    rand int retardo;
    bit md_tx_valid;
    bit [DW-1:0] md_tx_data;
    bit [1:0] md_tx_offset;
    bit [2:0] md_tx_size;
    rand bit md_tx_ready, md_tx_err;
    int tiempo, max_retardo;

    function new(int ret = 0, bit vld = 0, bit [DW-1:0] dta = 0, bit of = 0, bit sz = 1, bit rdy = 0, bit er = 0, int tmp = 0, int max_rtrd = 10);
        this.retardo = ret;
        this.md_tx_valid = vld;
        this.md_tx_data = dta;
        this.md_tx_offset = of;
        this.md_tx_size = sz;
        this.md_tx_ready = rdy;
        this.md_tx_err = er;
        this.tiempo = tmp;
        this.max_retardo = max_rtrd;
    endfunction

    function clean;
        this.retardo = 0;
        this.md_tx_valid = 0;
        this.md_tx_data = 0;
        this.md_tx_offset = 0;
        this.md_tx_size = 1;
        this.md_tx_ready = 0;
        this.md_tx_err = 0;
        this.tiempo = 0;
    endfunction

    function void print (string tag="");
        $display("[%g] %s Tiempo=%g Retardo=%g Dato=0x%h Size=%d Offset=%d", $time, tag, tiempo, this.retardo, this.md_tx_data, this.md_tx_size, this.md_tx_offset);
    endfunction
endclass

// Objeto de transaccion usado en el scoreboard
class trans_sb #(parameter DW=32);
    bit [DW-1:0] dato_rx, dato_tx;
    int tiempo_rx, tiempo_tx;
    bit reset;
    int latencia;
    bit [DW-1:0] status_reg, irq_reg

    function clean();
        this.dato_rx = 0;
        this.dato_tx = 0;
        this.tiempo_rx = 0;
        this.tiempo_tx = 0;
        this.reset = 0;
        this.latencia = 0;
        this.status_reg = 0;
        this.irq_reg = 0;
    endfunction

    task calc_latencia;
        this.latencia = this.tiempo_tx - this.tiempo_rx;
    endtask

    function void print (string tag="");
        $display("[%g] %s Tiempo=%g Dato_rx=0x%h Dato_tx=0x%h t_rx=%g t_tx=%g rst=%g ltncy=%g st_reg=0x%h irq_reg=0x%h", 
                                            $time, tag, this.dato_rx, this.dato_tx, this.tiempo_rx, this.tiempo_tx, this.reset, this.latencia, this.status_reg, this.irq_reg);
    endfunction
endclass

// comandos hacia el scoreboard
typedef enum {retardo_promedio, reporte} solicitud_sb;

// comandos hacia el agente
typedef enum {llenad_aleatorio, trans_aleatoria, trans_especifica, sec_trans_aleatorias} instrucciones_agente;

// mailboxes de tipo definido para comunicar interfaces
typedef mailbox #(trans_apb) trans_apb_mbx;

typedef mailbox #(trans_md_rx) trans_md_rx_mbx;

typedef mailbox #(trans_md_tx) trans_md_tx_mbx;

typedef mailbox #(trans_sb) trans_sb_mbx;

typedef mailbox #(solicitud_sb) comando_test_sb_mbx;

typedef mailbox #(instrucciones_agente) comando_test_agent_mbx;