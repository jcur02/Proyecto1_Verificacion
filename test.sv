`timescale 1ns/1ps

// =====================================================
// TEST: genera la prueba usando el ambiente y el agente
// =====================================================
class test_basic #(parameter AW=16, parameter DW=32);

  ambiente #(.AW(AW), .DW(DW)) env;

  // Helper: empacar CTRL (según cfs_regs: SIZE en [2:0], OFFSET desde bit 8)
  static function automatic bit [DW-1:0] pack_ctrl(input int unsigned size, input int unsigned offset);
    bit [DW-1:0] w;
    w = '0;
    w[2:0]      = size[2:0];   // LSB_CTRL_SIZE = 0
    w[8 +: 8]   = offset[7:0]; // LSB_CTRL_OFFSET = 8 (ajusta ancho si OFFSET_WIDTH != 8)
    return w;
  endfunction

  function new(ambiente#(.AW(AW), .DW(DW)) env_h);
    env = env_h;
  endfunction

  // Secuencia: configura CTRL por APB y luego empuja varios RX beats
  task run();
    // 1) Config por APB: CTRL.SIZE=2 bytes, CTRL.OFFSET=1
    trans_apb#(.AW(AW), .DW(DW)) apb_t;

    apb_t = new();
    apb_t.tipo   = escritura;
    apb_t.paddr  = 'h0000; // ADDR_CTRL (ajusta si tu mapa difiere)
    apb_t.pwdata = pack_ctrl(2, 1);
    apb_t.retardo= 1;      // el agente puede re-randomizar dentro de límites
    env.apb_test_agnt_mbx.put(apb_t);

    // 2) Otra escritura de CTRL: SIZE=4, OFFSET=0 (probar otra config)
    apb_t = new();
    apb_t.tipo   = escritura;
    apb_t.paddr  = 'h0000;
    apb_t.pwdata = pack_ctrl(4, 0);
    apb_t.retardo= 2;
    env.apb_test_agnt_mbx.put(apb_t);

    // 3) Tráfico RX: dos plantillas (el agente randomiza size/retardo si no se fijan)
    trans_md_rx#(.DW(DW)) rx_t;

    // 3a) Fijo data/offset, dejo size/retardo al agente
    rx_t = new();
    rx_t.md_rx_valid  = 1;
    rx_t.md_rx_data   = 32'hDEAD_BEEF;
    rx_t.md_rx_offset = 2;
    // rx_t.md_rx_size   = X (lo randomiza el agente dentro de {1,2,4})
    // rx_t.retardo      = X (lo randomiza el agente dentro de [0..max_retardo])
    env.rx_test_agnt_mbx.put(rx_t);

    // 3b) Fijo size=4, offset=1, data específica, retardo libre al agente
    rx_t = new();
    rx_t.md_rx_valid  = 1;
    rx_t.md_rx_data   = 32'hA5A5_5A5A;
    rx_t.md_rx_offset = 1;
    rx_t.md_rx_size   = 4;
    env.rx_test_agnt_mbx.put(rx_t);

    // 4) Un pequeño burst de N plantillas más (todas libres para que el agente randomice)
    foreach (int'(i) [0:7]) begin
      rx_t = new();
      rx_t.md_rx_valid = 1;
      // Dejo data/offset/size sin fijar para que el agente aplique sus policies
      env.rx_test_agnt_mbx.put(rx_t);
    end
  endtask
endclass