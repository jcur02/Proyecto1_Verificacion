// Driver / Monitor del APB
class apb_driver #(parameter AW = 15, DW = 32);
    virtual apb_if #(.AW(AW), .DW(DW)) vif;
    trans_apb_mbx agnt_drv_mbx;
    trans_apb_mbx
endclass