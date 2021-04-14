//============================================================================
//  SVI-328 based on ColecoVision
//
//  
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================


// TODO
//  - Complete Keyboard Mapping
//  - Make Memory size select from OSD
//  - AY clk is rigth??
//  - Wait_n signal??

//Core : 
//Z80 - 3,5555Mhz
//AY - z80/2 = 1,777 Mhz
//Mess :
//Z80 - 3,579545
//AY - 1,789772

module SVI328
(
	input         CLOCK_27,
	  
	output  [5:0] VGA_R,
	output  [5:0] VGA_G,
	output  [5:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	  
	output        LED,
	  
	input         UART_RXD,
	output        UART_TXD,
	  
	output        AUDIO_L,
	output        AUDIO_R,
	  
	input         SPI_SCK,
	output        SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,
	input         SPI_SS3,
	input         SPI_SS4,
	input         CONF_DATA0,
	  
	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE
  );




`include "build_id.v" 
parameter CONF_STR = {
	"SVI328;BINROM;",
	"O79,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"O3,Joysticks swap,No,Yes;",
	"T0,Reset;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys;
wire pll_locked;


pll pll
(
	.inclk0 (CLOCK_27),
	.c0     (clk_sys  ),
	.locked (pll_locked)
);

//pll pll
//(
//	.refclk(CLK_50M),
//	.rst(0),
//	.outclk_0(clk_sys),
//	.locked(pll_locked)
//);

reg ce_10m7 = 0;
reg ce_5m3 = 0;
always @(posedge clk_sys) begin
	reg [2:0] div;
	
	div <= div+1'd1;
	ce_10m7 <= !div[1:0];
	ce_5m3  <= !div[2:0];
end

/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [31:0] joy0, joy1;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire        ioctl_wait = ~sdram_rdy;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        forced_scandoubler;
wire [21:0] gamma_bus;
wire [10:0] PS2Keys;
wire       scandoubler_disable;

mist_io #(.STRLEN($size(CONF_STR)>>3)) mist_io
(
   
	.clk_sys(clk_sys),
	.SPI_SCK     (SPI_SCK   ),
   .CONF_DATA0  (CONF_DATA0),
   .SPI_SS2     (SPI_SS2   ),
   .SPI_DO      (SPI_DO    ),
   .SPI_DI      (SPI_DI    ),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.scandoubler_disable (scandoubler_disable),

   .ypbpr (ypbpr),	

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_ce(1),

	.ps2_key(PS2Keys),
	
	.joystick_0(joy0), // HPS joy [4:0] {Fire, Up, Down, Left, Right}
	.joystick_1(joy1)

);

/////////////////  RESET  /////////////////////////

wire reset =  status[0] | buttons[1] | ioctl_download | ~pll_locked;


////////////////  KeyBoard  ///////////////////////


wire [3:0] svi_row;
wire [7:0] svi_col;
sviKeyboard KeyboardSVI
(
	.clk		(clk_sys),
	.reset	(reset),
	
	.keys		(PS2Keys),
	.svi_row (svi_row),
	.svi_col (svi_col)
	
);


wire [15:0] cpu_ram_a;
wire        ram_we_n, ram_rd_n, ram_ce_n;
wire  [7:0] ram_di;
wire  [7:0] ram_do;


wire [13:0] vram_a;
wire        vram_we;
wire  [7:0] vram_di;
wire  [7:0] vram_do;

spram #(14) vram
(
	.clock(clk_sys),
	.address(vram_a),
	.wren(vram_we),
	.data(vram_do),
	.q(vram_di)
);


wire sdram_rdy;

`ifdef Bram
spram #(18) ram
(
	.clock(clk_sys),
	.address(ioctl_download ? {ioctl_index[0],ioctl_addr[15:0]} : ram_a),
	.wren((ioctl_wr | ( isRam & ~(ram_we_n | ram_ce_n)))), //.wren(ce_10m7 & ~(ram_we_n | ram_ce_n)),
	.data(ioctl_wr ? ioctl_dout : ram_do),
	.q(ram_di)
);
assign sdram_rdy = 1'b1; //ce_10m7;
`else 

assign SDRAM_CLK = ~clk_sys;
//assign SDRAM_CKE = 1'b1;

sdram sdram
(
	.*,
	.init(~pll_locked),
	.clk(clk_sys),

   .wtbt(2'b0),
   .addr(ioctl_download ? {ioctl_index[0],ioctl_addr[15:0]} : ram_a), //   .addr(ioctl_download ? ioctl_addr : ram_a),
	.rd( ~(ram_rd_n | ram_ce_n)),
   .dout(ram_di),
   .din(ioctl_wr ? ioctl_dout : ram_do),
   .we(ioctl_wr | ( isRam & ~(ram_we_n | ram_ce_n))), //   .we(ioctl_wr),
   .ready(sdram_rdy)
);
`endif


wire [17:0] ram_a;// = cpu_ram_a; //SVI
wire isRam;

svi_mapper RamMapper
(
    .addr_i		(cpu_ram_a),
    .RegMap_i	(ay_port_b),
    .addr_o		(ram_a),
	 .ram			(isRam)
);


////////////////  Console  ////////////////////////

wire [10:0] audio;
//assign AUDIO_L = {audio,5'd0};
//assign AUDIO_R = {audio,5'd0};
//assign AUDIO_S = 0;
//assign AUDIO_MIX = 0;

//assign CLK_VIDEO = clk_sys;

wire [7:0] R,G,B,ay_port_b;
wire hblank, vblank;
wire hsync, vsync;

wire [31:0] joya = status[3] ? joy1 : joy0;
wire [31:0] joyb = status[3] ? joy0 : joy1;



cv_console console
(
	.clk_i(clk_sys),
	.clk_en_10m7_i(ce_10m7),
	.clk_en_5m3_i(ce_5m3),
	.reset_n_i(~reset),
	.intnmi_flag(status[13:12]),
	.por_n_o(),

   .svi_row_o(svi_row),
   .svi_col_i(svi_col),	
	
	.svi_tap_i(tape_in),		
	
	.joy0_i(~{joya[4],joya[0],joya[1],joya[2],joya[3]}), //SVI {Fire,Right, Left, Down, Up} // HPS {Fire,Up, Down, Left, Right}
	.joy1_i(~{joyb[4],joyb[0],joyb[1],joyb[2],joyb[3]}),

	.cpu_ram_a_o(cpu_ram_a),
	.cpu_ram_we_n_o(ram_we_n),
	.cpu_ram_ce_n_o(ram_ce_n),
	.cpu_ram_rd_n_o(ram_rd_n),
	.cpu_ram_d_i(ram_di),
	.cpu_ram_d_o(ram_do),

	.ay_port_b(ay_port_b),
	
	.vram_a_o(vram_a),
	.vram_we_o(vram_we),
	.vram_d_o(vram_do),
	.vram_d_i(vram_di),

	.border_i(status[6]),
	.rgb_r_o(R),
	.rgb_g_o(G),
	.rgb_b_o(B),
	.hsync_n_o(hsync),
	.vsync_n_o(vsync),
	.hblank_o(hblank),
	.vblank_o(vblank),

	.audio_o(audio)
);


/////////////////  VIDEO  /////////////////////////


wire [2:0] scale = status[9:7];

//reg hs_o, vs_o;
//always @(posedge clk_sys) begin
//	hs_o <= ~hsync;
//	if(~hs_o & ~hsync) vs_o <= ~vsync;
//end

video_mixer mixer
(
	.*,

	.ce_pix(ce_5m3),
   .ce_pix_actual(ce_5m3),
	//.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==1),
   .scanlines(scandoubler_disable ? 2'b00 : {scale==3, scale==2}),
   .line_start(0),
   .ypbpr_full(0),
   .mono(0),

	//.VGA_DE(vga_de),
	.R(R[7:2]),
	.G(G[7:2]),
	.B(B[7:2]),

	// Positive pulses.
	.HSync(hsync),
	.VSync(vsync)
	//.HBlank(hblank),
	//.VBlank(vblank)
);

///////////////// Audio ////////////////////////////

dac #(
   .msbi_g         (11))
audiodac_r(
   .clk_i          (clk_sys),
   .resetn         (1),
   .dac_i          (audio),
   .dac_o          (AUDIO_L)
  );
assign AUDIO_R = AUDIO_L;  
/////////////////  Tape In   /////////////////////////

wire tape_in = ~UART_RXD;
assign LED = ioctl_download;


endmodule
