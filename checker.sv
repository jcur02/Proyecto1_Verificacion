// Interfaz de modelo dorado
virtual class i_golden_model #(parameter DW=32);
  virtual function void apply_apb(const ref trans_apb#(.DW(DW)) apb); endfunction
  // Genera 0..N beats TX esperados para un beat RX real
  pure virtual task predict_many(
      const ref trans_md_rx#(.DW(DW)) rx_in,
            ref mailbox #(trans_md_tx#(.DW(DW))) mbx_expected
  );
  endtask
endclass

// Golden del CFS Aligner (usa mapping real del DUT)
// - Valida el beat RX (regla SIZE>0 y ((BYTES+OFFSET)%SIZE)==0)
// - Corta en bloques de ctrl_size (último parcial configurable)
class golden_aligner #(parameter DW=32) extends i_golden_model#(.DW(DW));
  localparam int BYTES = DW/8;

  // Config aprendida por APB (desde cfs_regs.v)
  int unsigned ctrl_size   = 1;
  int unsigned ctrl_offset = 0;

  // Dirección de CTRL (cfs_regs.v)
  localparam int unsigned ADDR_CTRL = 'h0000;

  // Si tu RTL EMITE último beat parcial (<ctrl_size) pon TRUE;
  // Si siempre emite ctrl_size, incluso al final, pon FALSE.
  bit EXPECT_LAST_PARTIAL = 1;

  // Hook APB → actualiza ctrl_size/offset exactamente como en el DUT
  virtual function void apply_apb(const ref trans_apb#(.DW(DW)) apb);
    if (apb.tipo == escritura && apb.paddr == ADDR_CTRL) begin
      // LSB_CTRL_SIZE = 0; LSB_CTRL_OFFSET = 8
      ctrl_size   = apb.pwdata[0 +: $clog2(BYTES)+1];
      ctrl_offset = apb.pwdata[8 +: (DW<=8? 1 : $clog2(BYTES))];
      if (ctrl_size == 0) ctrl_size = 1;
      if (ctrl_offset >= BYTES) ctrl_offset = 0;
    end
  endfunction

  // Verifica legalidad del beat RX según cfs_aligner_core.v
  function bit md_is_legal(input int unsigned rx_size, input int unsigned rx_offset);
    if (rx_size == 0) return 0;
    return (((BYTES + rx_offset) % rx_size) == 0);
  endfunction

  // Predicción: genera 0..N beats TX esperados (según ctrl_size/offset)
  virtual task predict_many(
      const ref trans_md_rx#(.DW(DW)) rx_in,
            ref mailbox #(trans_md_tx#(.DW(DW))) mbx_expected
  );
    int unsigned rx_size   = rx_in.md_rx_size;
    int unsigned rx_offset = rx_in.md_rx_offset;
    bit [DW-1:0] rx_word   = rx_in.md_rx_data;

    // Si beat RX es ilegal, el DUT lo descarta: no generamos esperados
    if (!md_is_legal(rx_size, rx_offset)) begin
      return;
    end

    int remaining = rx_size;
    int src_base  = rx_offset;

    while (remaining > 0) begin
      int chunk;
      if (EXPECT_LAST_PARTIAL) chunk = (remaining >= ctrl_size) ? ctrl_size : remaining;
      else                     chunk = ctrl_size; // fuerza beats de tamaño fijo

      bit [DW-1:0] tx_word = '0;

      // Copiar 'chunk' bytes desde src_base+i → ctrl_offset+i
      for (int i = 0; i < chunk; i++) begin
        int src_byte = src_base + i;
        int dst_byte = ctrl_offset + i;
        if (src_byte < BYTES && dst_byte < BYTES) begin
          byte b = rx_word >> (8*src_byte);
          tx_word |= bit'(b) << (8*dst_byte);
        end
      end

      trans_md_tx#(.DW(DW)) exp = new();
      exp.clean();
      exp.md_tx_valid  = 1;
      exp.md_tx_ready  = 1;
      exp.md_tx_err    = 0;
      exp.md_tx_data   = tx_word;
      exp.md_tx_offset = ctrl_offset;
      exp.md_tx_size   = EXPECT_LAST_PARTIAL ? chunk : ctrl_size; // ver nota arriba
      mbx_expected.put(exp);

      src_base  += chunk;
      remaining -= chunk;
    end
  endtask
endclass

class check_item #(parameter DW=32);
  trans_md_rx#(.DW(DW)) rx_in;
  trans_md_tx#(.DW(DW)) exp_tx;
  trans_md_tx#(.DW(DW)) got_tx;
  bit ok;
  int lat;
  string tag;

  function void print();
    $display("%s ok=%0b lat=%0d", tag, ok, lat);
    if (!ok) begin
      exp_tx.print("  EXP");
      got_tx.print("  GOT");
    end
  endfunction
endclass


// Checker
class tx_checker #(parameter DW=32);
  // Entradas
  trans_md_rx_mbx drv_chkr_mbx;     // del RX driver (entrada real)
  trans_md_tx_mbx mon_chkr_mbx;     // del TX monitor (salida real)
  trans_apb_mbx   apb_drv_chkr_mbx; // opcional: APB→modelo

  // Salida hacia scoreboard
  mailbox #(check_item#(.DW(DW))) chk_sb_mbx;

  // Modelo dorado
  i_golden_model#(.DW(DW)) model;

  // Config
  int max_wait_cycles = 1000;
  bit verbose = 1;

  function new(i_golden_model#(.DW(DW)) m,
               trans_md_rx_mbx rx_mbx,
               trans_md_tx_mbx tx_mbx,
               mailbox #(check_item#(.DW(DW))) out_mbx,
               trans_apb_mbx apb_mbx = null);
    model               = m;
    drv_chkr_mbx        = rx_mbx;
    mon_chkr_mbx        = tx_mbx;
    chk_sb_mbx          = out_mbx;
    apb_drv_chkr_mbx    = apb_mbx;
  endfunction

  // APB → modelo dorado
  task apb_apply_thread();
    if (apb_drv_chkr_mbx == null) disable apb_apply_thread;
    forever begin
      trans_apb#(.DW(DW)) t_apb;
      apb_drv_chkr_mbx.get(t_apb);
      model.apply_apb(t_apb);
    end
  endtask

  function bit cmp_tx(const ref trans_md_tx#(.DW(DW)) exp,
                      const ref trans_md_tx#(.DW(DW)) got,
                      string tag);
    bit ok = 1;
    if (exp.md_tx_data   !== got.md_tx_data  ) begin ok=0; if (verbose) $display("%s DATA exp=0x%h got=0x%h", tag, exp.md_tx_data,   got.md_tx_data); end
    if (exp.md_tx_size   !== got.md_tx_size  ) begin ok=0; if (verbose) $display("%s SIZE exp=%0d got=%0d",  tag, exp.md_tx_size,   got.md_tx_size); end
    if (exp.md_tx_offset !== got.md_tx_offset) begin ok=0; if (verbose) $display("%s OFFS exp=%0d got=%0d",  tag, exp.md_tx_offset, got.md_tx_offset); end
    if (exp.md_tx_err    !== got.md_tx_err   ) begin ok=0; if (verbose) $display("%s ERR  exp=%0b got=%0b",  tag, exp.md_tx_err,    got.md_tx_err);    end
    return ok;
  endfunction

  task run();
    $display("[%0t] TX Checker inicializado", $time);
    fork apb_apply_thread(); join_none

    forever begin
      // 1) Consumir un beat RX real (ya ejecutado por el driver)
      trans_md_rx#(.DW(DW)) rx_in;
      drv_chkr_mbx.get(rx_in);

      // 2) Generar 0..N beats esperados
      mailbox #(trans_md_tx#(.DW(DW))) mbx_expected = new();
      model.predict_many(rx_in, mbx_expected);
      int n_exp = mbx_expected.num();

      // 3) Por cada esperado, esperar uno observado
      for (int k=0; k<n_exp; k++) begin
        trans_md_tx#(.DW(DW)) exp_tx, got_tx;
        mbx_expected.get(exp_tx);

        int waitc=0; bit got=0;
        while (waitc < max_wait_cycles) begin
          if (mon_chkr_mbx.num() > 0) begin mon_chkr_mbx.get(got_tx); got=1; break; end
          @(posedge $root.tb_clk);
          waitc++;
        end

        check_item#(.DW(DW)) item = new();
        item.rx_in = rx_in;
        item.exp_tx = exp_tx;
        item.tag = $sformatf("TX CHECK [%0t.%0d]", $time, k);

        if (!got) begin
          item.ok = 0;
          item.got_tx = new(); item.got_tx.clean();
          item.lat = 0;
          chk_sb_mbx.put(item);
          if (verbose) $display("[%0t] %s TIMEOUT esperando TX", $time, item.tag);
          continue;
        end

        item.got_tx = got_tx;
        item.lat    = got_tx.tiempo - rx_in.tiempo; // si llenas 'tiempo' en driver/monitor
        item.ok     = cmp_tx(exp_tx, got_tx, item.tag);
        chk_sb_mbx.put(item);
      end
    end
  endtask
endclass
