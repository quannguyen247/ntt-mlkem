// Modular add: (a + b) mod q
function [`NTT_DATA_WIDTH-1:0] ntt_mod_add;
    input [`NTT_DATA_WIDTH-1:0] a;
    input [`NTT_DATA_WIDTH-1:0] b;
    reg [12:0] s;
    reg [13:0] d;
    begin
        s = {1'b0, a} + {1'b0, b};
        d = {1'b0, s} - 14'd3329;
        ntt_mod_add = d[13] ? s[11:0] : d[11:0];
    end
endfunction

// Modular sub: (a - b) mod q
function [`NTT_DATA_WIDTH-1:0] ntt_mod_sub;
    input [`NTT_DATA_WIDTH-1:0] a;
    input [`NTT_DATA_WIDTH-1:0] b;
    reg [12:0] d;
    reg [11:0] s;
    begin
        d = {1'b0, a} - {1'b0, b};
        s = d[11:0] + 12'd3329;
        ntt_mod_sub = d[12] ? s : d[11:0];
    end
endfunction

// Parallel CSA modular add: (a + b) mod q
function [`NTT_DATA_WIDTH-1:0] ntt_mod_add_fast;
    input [`NTT_DATA_WIDTH-1:0] a;
    input [`NTT_DATA_WIDTH-1:0] b;
    reg [11:0] s;
    reg [13:0] a14, b14, csa_s, csa_c, d;
    begin
        s = a + b;
        a14 = {2'b00, a};
        b14 = {2'b00, b};
        csa_s = a14 ^ b14 ^ 14'h32FF;
        csa_c = (a14 & b14) | ((a14 | b14) & 14'h32FF);
        d = csa_s + {csa_c[12:0], 1'b0};
        ntt_mod_add_fast = d[13] ? s : d[11:0];
    end
endfunction

// Parallel CSA modular sub: (a - b) mod q
function [`NTT_DATA_WIDTH-1:0] ntt_mod_sub_fast;
    input [`NTT_DATA_WIDTH-1:0] a;
    input [`NTT_DATA_WIDTH-1:0] b;
    reg [12:0] d;
    reg [11:0] nb, csa_s, csa_c, s;
    begin
        d = {1'b0, a} - {1'b0, b};
        nb = ~b;
        csa_s = a ^ nb ^ 12'd3330;
        csa_c = (a & nb) | ((a | nb) & 12'd3330);
        s = csa_s + {csa_c[10:0], 1'b0};
        ntt_mod_sub_fast = d[12] ? s : d[11:0];
    end
endfunction

// Twiddle table: packed {forward_16, inverse_16}
function signed [31:0] ntt_twiddle_entry;
    input [6:0] addr;
    reg signed [31:0] val;
    begin
        case (addr)
            7'd0:   val = { -16'sd1044, 16'sd1701 };
            7'd1:   val = { -16'sd758, 16'sd1807 };
            7'd2:   val = { -16'sd359, 16'sd1460 };
            7'd3:   val = { -16'sd1517, 16'sd2371 };
            7'd4:   val = {  16'sd1493, 16'sd2338 };
            7'd5:   val = {  16'sd1422, 16'sd2333 };
            7'd6:   val = {  16'sd287, 16'sd308 };
            7'd7:   val = {  16'sd202, 16'sd108 };
            7'd8:   val = { -16'sd171, 16'sd2851 };
            7'd9:   val = {  16'sd622, 16'sd870 };
            7'd10:  val = {  16'sd1577, 16'sd854 };
            7'd11:  val = {  16'sd182, 16'sd1510 };
            7'd12:  val = {  16'sd962, 16'sd2535 };
            7'd13:  val = { -16'sd1202, 16'sd1278 };
            7'd14:  val = { -16'sd1474, 16'sd1530 };
            7'd15:  val = {  16'sd1468, 16'sd1185 };
            7'd16:  val = {  16'sd573, 16'sd1659 };
            7'd17:  val = { -16'sd1325, 16'sd1187 };
            7'd18:  val = {  16'sd264, 16'sd3109 };
            7'd19:  val = {  16'sd383, 16'sd874 };
            7'd20:  val = { -16'sd829, 16'sd1335 };
            7'd21:  val = {  16'sd1458, 16'sd2111 };
            7'd22:  val = { -16'sd1602, 16'sd136 };
            7'd23:  val = { -16'sd130, 16'sd1215 };
            7'd24:  val = { -16'sd681, 16'sd2945 };
            7'd25:  val = {  16'sd1017, 16'sd1465 };
            7'd26:  val = {  16'sd732, 16'sd1285 };
            7'd27:  val = {  16'sd608, 16'sd2007 };
            7'd28:  val = { -16'sd1542, 16'sd2719 };
            7'd29:  val = {  16'sd411, 16'sd2726 };
            7'd30:  val = { -16'sd205, 16'sd2232 };
            7'd31:  val = { -16'sd1571, 16'sd2512 };
            7'd32:  val = {  16'sd1223, 16'sd75 };
            7'd33:  val = {  16'sd652, 16'sd156 };
            7'd34:  val = { -16'sd552, 16'sd3000 };
            7'd35:  val = {  16'sd1015, 16'sd2911 };
            7'd36:  val = { -16'sd1293, 16'sd2980 };
            7'd37:  val = {  16'sd1491, 16'sd872 };
            7'd38:  val = { -16'sd282, 16'sd2685 };
            7'd39:  val = { -16'sd1544, 16'sd1590 };
            7'd40:  val = {  16'sd516, 16'sd2210 };
            7'd41:  val = { -16'sd8, 16'sd602 };
            7'd42:  val = { -16'sd320, 16'sd1846 };
            7'd43:  val = { -16'sd666, 16'sd777 };
            7'd44:  val = { -16'sd1618, 16'sd147 };
            7'd45:  val = { -16'sd1162, 16'sd2170 };
            7'd46:  val = {  16'sd126, 16'sd2551 };
            7'd47:  val = {  16'sd1469, 16'sd246 };
            7'd48:  val = { -16'sd853, 16'sd1676 };
            7'd49:  val = { -16'sd90, 16'sd1755 };
            7'd50:  val = { -16'sd271, 16'sd460 };
            7'd51:  val = {  16'sd830, 16'sd291 };
            7'd52:  val = {  16'sd107, 16'sd235 };
            7'd53:  val = { -16'sd1421, 16'sd3152 };
            7'd54:  val = { -16'sd247, 16'sd2742 };
            7'd55:  val = { -16'sd951, 16'sd2907 };
            7'd56:  val = { -16'sd398, 16'sd3224 };
            7'd57:  val = {  16'sd961, 16'sd1779 };
            7'd58:  val = { -16'sd1508, 16'sd2458 };
            7'd59:  val = { -16'sd725, 16'sd1251 };
            7'd60:  val = {  16'sd448, 16'sd2486 };
            7'd61:  val = { -16'sd1065, 16'sd2774 };
            7'd62:  val = {  16'sd677, 16'sd2899 };
            7'd63:  val = { -16'sd1275, 16'sd1103 };
            7'd64:  val = { -16'sd1103, 16'sd1275 };
            7'd65:  val = {  16'sd430, 16'sd2652 };
            7'd66:  val = {  16'sd555, 16'sd1065 };
            7'd67:  val = {  16'sd843, 16'sd2881 };
            7'd68:  val = { -16'sd1251, 16'sd725 };
            7'd69:  val = {  16'sd871, 16'sd1508 };
            7'd70:  val = {  16'sd1550, 16'sd2368 };
            7'd71:  val = {  16'sd105, 16'sd398 };
            7'd72:  val = {  16'sd422, 16'sd951 };
            7'd73:  val = {  16'sd587, 16'sd247 };
            7'd74:  val = {  16'sd177, 16'sd1421 };
            7'd75:  val = { -16'sd235, 16'sd3222 };
            7'd76:  val = { -16'sd291, 16'sd2499 };
            7'd77:  val = { -16'sd460, 16'sd271 };
            7'd78:  val = {  16'sd1574, 16'sd90 };
            7'd79:  val = {  16'sd1653, 16'sd853 };
            7'd80:  val = { -16'sd246, 16'sd1860 };
            7'd81:  val = {  16'sd778, 16'sd3203 };
            7'd82:  val = {  16'sd1159, 16'sd1162 };
            7'd83:  val = { -16'sd147, 16'sd1618 };
            7'd84:  val = { -16'sd777, 16'sd666 };
            7'd85:  val = {  16'sd1483, 16'sd320 };
            7'd86:  val = { -16'sd602, 16'sd8 };
            7'd87:  val = {  16'sd1119, 16'sd2813 };
            7'd88:  val = { -16'sd1590, 16'sd1544 };
            7'd89:  val = {  16'sd644, 16'sd282 };
            7'd90:  val = { -16'sd872, 16'sd1838 };
            7'd91:  val = {  16'sd349, 16'sd1293 };
            7'd92:  val = {  16'sd418, 16'sd2314 };
            7'd93:  val = {  16'sd329, 16'sd552 };
            7'd94:  val = { -16'sd156, 16'sd2677 };
            7'd95:  val = { -16'sd75, 16'sd2106 };
            7'd96:  val = {  16'sd817, 16'sd1571 };
            7'd97:  val = {  16'sd1097, 16'sd205 };
            7'd98:  val = {  16'sd603, 16'sd2918 };
            7'd99:  val = {  16'sd610, 16'sd1542 };
            7'd100: val = {  16'sd1322, 16'sd2721 };
            7'd101: val = { -16'sd1285, 16'sd2597 };
            7'd102: val = { -16'sd1465, 16'sd2312 };
            7'd103: val = {  16'sd384, 16'sd681 };
            7'd104: val = { -16'sd1215, 16'sd130 };
            7'd105: val = { -16'sd136, 16'sd1602 };
            7'd106: val = {  16'sd1218, 16'sd1871 };
            7'd107: val = { -16'sd1335, 16'sd829 };
            7'd108: val = { -16'sd874, 16'sd2946 };
            7'd109: val = {  16'sd220, 16'sd3065 };
            7'd110: val = { -16'sd1187, 16'sd1325 };
            7'd111: val = { -16'sd1659, 16'sd2756 };
            7'd112: val = { -16'sd1185, 16'sd1861 };
            7'd113: val = { -16'sd1530, 16'sd1474 };
            7'd114: val = { -16'sd1278, 16'sd1202 };
            7'd115: val = {  16'sd794, 16'sd2367 };
            7'd116: val = { -16'sd1510, 16'sd3147 };
            7'd117: val = { -16'sd854, 16'sd1752 };
            7'd118: val = { -16'sd870, 16'sd2707 };
            7'd119: val = {  16'sd478, 16'sd171 };
            7'd120: val = { -16'sd108, 16'sd3127 };
            7'd121: val = { -16'sd308, 16'sd3042 };
            7'd122: val = {  16'sd996, 16'sd1907 };
            7'd123: val = {  16'sd991, 16'sd1836 };
            7'd124: val = {  16'sd958, 16'sd1517 };
            7'd125: val = { -16'sd1460, 16'sd359 };
            7'd126: val = {  16'sd1522, 16'sd758 };
            7'd127: val = {  16'sd1628, 16'sd1441 };
            default: val = 32'sd0;
        endcase
        ntt_twiddle_entry = val;
    end
endfunction

// Unsigned twiddle in 0..q-1
function [`NTT_DATA_WIDTH-1:0] ntt_twiddle_u;
    input [6:0] addr;
    input is_inv;
    reg signed [31:0] tmp;
    reg signed [15:0] tw16;
    reg [15:0] tw_u16;
    reg [`NTT_DATA_WIDTH-1:0] tw_u;
    begin
        tmp = ntt_twiddle_entry(addr);
        if (is_inv)
            tw16 = tmp[15:0];
        else
            tw16 = tmp[31:16];

        tw_u16 = tw16[15] ? (tw16 + `NTT_Q) : tw16;
        tw_u = tw_u16[`NTT_DATA_WIDTH-1:0];
        ntt_twiddle_u = tw_u;
    end
endfunction
