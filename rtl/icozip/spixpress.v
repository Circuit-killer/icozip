////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	spixpress.v
//
// Project:	ICO Zip, iCE40 ZipCPU demonsrtation project
//
// Purpose:	This module is intended to be a low logic flash controller.
// 		It uses the 8'h03 read command from the flash, and so it
// 	cannot be used with a clock speed any greater than 50MHz.
//
//	Although this controller has no erase or program capability, it
//	includes a control port.  When using the control port, you should be
//	able to send arbitrary commands to the flash--but not read from the
//	flash during that time.
//
// Configuration:
//	In the interests of *LOW* logic, the controller has options for
//	OPT_CFG and OPT_PIPE.  If both are set to zero, the controller will be
//	in its lowest logic configuration.  That said, if you set OPT_CFG to
//	zero, you must also set i_cfg_stb to zero as well--lest you expect an
//	acknowledgement from a request made when i_cfg_stb is high.
//
// Actions:
// 	Control Port
// 	[31:9]	Unused bits, ignored on write, read as zero
// 	[8]	CS_n
// 			Can be activated via a write to the control port.
// 			This will render the memory addresses unreadable.
// 			Write a '1' to this value to return the memory to
// 			normal operation.
// 	[7:0]	BYTE-DATA
// 			Following a write to the control port where bit [8]
// 			is low, the controller will send bits [7:0] out the
// 			SPI port, top bit first.  Once accomplished, the
// 			control port may be read to see what values were
// 			read from the SPI port.  Those values will be stored
// 			in these same bits [7:0].
// 
//	Memory
//		Returns the data from the address read
//
//		Requires that the CS_N setting within the control port be
//		deactivated, otherwise requests to read from memory
//		will simply return the control port register immediately
//		without doing anything.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2018, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype	none
//
module	spixpress(i_clk, i_reset,
		i_wb_cyc, i_wb_stb, i_cfg_stb, i_wb_we, i_wb_addr, i_wb_data,
			o_wb_stall, o_wb_ack, o_wb_data,
		o_spi_cs_n, o_spi_sck, o_spi_mosi, i_spi_miso);
	//
	// OPT_PIPE allows successive, sequential, transactions to
	// incrementing addresses without requiring a new address to be sent.
	//
	// Random access performance:	65+64(N-1)
	// Performance when piped:	65+32(N-1)
	//
	parameter [0:0]	OPT_PIPE = 1'b1;
	//
	// OPT_CFG creates a configuration register that can be accessed through
	// i_cfg_stb when the core isn't busy.  Using this configuration
	// register, it is possible to send arbitrary commands to the flash,
	// and hence to erase or program the flash.  Since the access is
	// arbitrary, other flash features are supported as well such as
	// programming or reading the one-time-programmable memory or more.
	parameter [0:0]	OPT_CFG  = 1'b1;
	//
	input	wire		i_clk, i_reset;
	//
	input	wire		i_wb_cyc, i_wb_stb, i_cfg_stb, i_wb_we;
	input	wire	[21:0]	i_wb_addr;
	input	wire	[31:0]	i_wb_data;
	output	reg		o_wb_stall, o_wb_ack;
	output	reg	[31:0]	o_wb_data;
	//
	output	reg		o_spi_cs_n, o_spi_sck, o_spi_mosi;
	input	wire		i_spi_miso;
	//
	//

	reg		cfg_user_mode;
	reg	[32:0]	wdata_pipe;
	reg	[6:0]	ack_delay;
	reg		actual_sck;

	wire	[21:0]	next_addr;

	wire	user_request, bus_request, next_request;

	assign	user_request = (OPT_CFG)&&(i_cfg_stb)&&(!o_wb_stall)
					&&(i_wb_we)&&(!i_wb_data[8]);
	assign	bus_request  = (i_wb_stb)&&(!o_wb_stall)
					&&(!i_wb_we)&&(!cfg_user_mode);
	assign	next_request = (OPT_PIPE)&&(i_wb_stb)&&(!i_wb_we)
					&&(i_wb_addr[21:0] == next_addr);


	initial	wdata_pipe = 0;
	always @(posedge i_clk)
	if (bus_request)
		wdata_pipe <= { 1'b0, 8'h03, i_wb_addr[21:0], 2'b00 };
	else if (user_request)
		wdata_pipe <= { 1'b0, i_wb_data[7:0], 24'h0 };
	else
		wdata_pipe <= { wdata_pipe[31:0], 1'b0 };

	assign	o_spi_mosi = wdata_pipe[32];

	initial	ack_delay = 0;
	always @(posedge i_clk)
	if ((i_reset)||(!i_wb_cyc))
		ack_delay <= 0;
	else if (bus_request)
		ack_delay <= ((o_spi_cs_n)||(!OPT_PIPE)) ? 7'd65 : 7'd32;
	else if (user_request)
		ack_delay <= 7'd9;
	else if (ack_delay != 0)
		ack_delay <= ack_delay - 1'b1;

	initial	o_wb_ack = 0;
	always @(posedge i_clk)
	if (i_reset)
		o_wb_ack <= 0;
	else if (ack_delay == 1)
		o_wb_ack <= (i_wb_cyc);
	else if ((i_wb_stb)&&(!o_wb_stall)&&(!bus_request))
		o_wb_ack <= 1'b1;
	else if ((OPT_CFG)&&(i_cfg_stb)&&(!o_wb_stall)&&(!user_request))
		o_wb_ack <= 1'b1;
	else
		o_wb_ack <= 0;

	initial	cfg_user_mode = 0;
	always @(posedge i_clk)
	if (i_reset)
		cfg_user_mode <= 0;
	else if ((OPT_CFG)&&(i_cfg_stb)&&(!o_wb_stall)&&(i_wb_we))
		cfg_user_mode <= !i_wb_data[8];

	always @(posedge i_clk)
	if (actual_sck)
	begin
		if (cfg_user_mode)
			o_wb_data <= { 23'h0, !cfg_user_mode, o_wb_data[6:0], i_spi_miso };
		else
			o_wb_data <= { o_wb_data[30:0], i_spi_miso };
	end

	initial	o_spi_cs_n = 1'b1;
	always @(posedge i_clk)
	if (i_reset)
		o_spi_cs_n <= 1'b1;
	else if ((!i_wb_cyc)&&(!cfg_user_mode))
		o_spi_cs_n <= 1'b1;
	else if (bus_request)
		o_spi_cs_n <= 1'b0;
	else if ((OPT_CFG)&&(i_cfg_stb)&&(!o_wb_stall)&&(i_wb_we))
		o_spi_cs_n <= i_wb_data[8];
	else if (cfg_user_mode)
		o_spi_cs_n <= 1'b0;
	else if ((ack_delay == 1)&&(!cfg_user_mode))
		o_spi_cs_n <= 1'b1;

	initial	o_spi_sck = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		o_spi_sck <= 1'b0;
	else if ((bus_request)||(user_request))
		o_spi_sck <= 1'b1;
	else if ((i_wb_cyc)&&(ack_delay > 2))
		o_spi_sck <= 1'b1;
	else if ((OPT_PIPE)&&(next_request)&&(ack_delay == 2))
		o_spi_sck <= 1'b1;
	else
		o_spi_sck <= 1'b0;

	initial	actual_sck = 1'b0;
	always @(posedge i_clk)
	if ((i_reset)||(!i_wb_cyc))
		actual_sck <= 1'b0;
	else
		actual_sck <= o_spi_sck;

	initial	o_wb_stall = 1'b0;
	always @(posedge i_clk)
	if (!i_wb_cyc)
		o_wb_stall <= 1'b0;
	else if ((bus_request)||(user_request))
		o_wb_stall <= 1'b1;
	else if ((OPT_PIPE)&&(next_request)&&(ack_delay == 2))
		o_wb_stall <= 1'b0;
	else
		o_wb_stall <= (ack_delay > 1);

	generate if (OPT_PIPE)
	begin
		reg	[21:0]	r_next_addr;
		always @(posedge i_clk)
		if ((i_wb_stb)&&(!o_wb_stall))
			r_next_addr <= i_wb_addr + 1'b1;

		assign	next_addr = r_next_addr;

	end else begin

		assign next_addr = 0;

	end endgenerate

	// verilator lint_off UNUSED
	wire	[22:0]	unused;
	assign	unused = i_wb_data[31:9];
	// verilator lint_on  UNUSED
`ifdef	FORMAL
	parameter	[0:0]	F_OPT_COVER = 1'b0;

	reg	f_past_valid;

	initial	f_past_valid = 1'b0;
	always @(posedge i_clk)
		f_past_valid <= 1'b1;

	wire	f_reset;
	assign	f_reset = (!f_past_valid);
	always @(*)
		assume(i_reset == f_reset);

	always @(posedge i_clk)
	if ((!f_past_valid)||($past(i_reset)))
	begin
		assert(o_spi_cs_n == 1'b1);
		assert(o_spi_sck  == 1'b0);
		//
		assert(ack_delay    ==  0);
		assert(cfg_user_mode == 0);
		assert(o_wb_stall == 1'b0);
		assert(o_wb_ack   == 1'b0);
	end

	always @(*)
	if (!OPT_CFG)
		assume(!i_cfg_stb);

	always @(*)
		assume((!i_cfg_stb)||(!i_wb_stb));

	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(i_reset))&&(i_wb_cyc)
		&&(($past(i_wb_stb))||($past(i_cfg_stb)))&&($past(o_wb_stall)))
		assume({i_wb_stb,i_cfg_stb}==$past({i_wb_stb,i_cfg_stb}));

	localparam	F_LGDEPTH = 7;
	wire	[F_LGDEPTH-1:0]	f_nreqs, f_nacks, f_outstanding;

	fwb_slave #( .AW(22), .F_MAX_STALL(7'd66), .F_MAX_ACK_DELAY(7'd66),
			.F_LGDEPTH(F_LGDEPTH),
			.F_MAX_REQUESTS((OPT_PIPE) ? 0 : 1'b1),
			.F_OPT_MINCLOCK_DELAY(1'b1)
		) slavei(i_clk, (i_reset)||(f_reset),
		i_wb_cyc, (i_wb_stb)||(i_cfg_stb), i_wb_we,
			i_wb_addr, i_wb_data, 4'hf,
			o_wb_ack, o_wb_stall, o_wb_data, 1'b0,
			f_nreqs, f_nacks, f_outstanding);

	always @(posedge i_clk)
	if (!f_past_valid)
		assert(f_outstanding == 0);
	else if ((!i_reset)&&(i_wb_cyc))
	begin
		if (((!OPT_PIPE)||($past(o_spi_cs_n)))
			&&($past(i_wb_stb))&&(!$past(o_wb_stall))&&(i_wb_cyc))
			assert(f_outstanding == 1);
		if (ack_delay > 0)
			assert((o_wb_ack)||(f_outstanding == 1));
	end

	always @(*)
	if (OPT_PIPE)
		assert(f_outstanding <= 2);
	else
		assert(f_outstanding <= 1);

	always @(posedge i_clk)
	if ((f_past_valid)&&(o_wb_ack)&&($past(o_wb_ack)))
		assert(f_outstanding <= 1);
	always @(posedge i_clk)
	if ((OPT_PIPE)&&(f_outstanding == 2))
		assert((o_wb_ack)&&(!o_spi_cs_n)&&(o_spi_sck)&&(ack_delay==7'd32));

	always @(posedge i_clk)
	if ((f_past_valid)&&($past(i_wb_stb))&&(!$past(o_wb_stall)))
	begin
		if ((i_wb_cyc)&&(!i_reset)
				&&(!$past(user_request))&&(!$past(bus_request)))
			assert((o_wb_ack)&&(f_outstanding == 1));
	end

	always @(*)
		assert((o_spi_sck||actual_sck) == (ack_delay > 0));
	always @(*)
	if (o_spi_cs_n)
		assert(!o_spi_sck);

	always @(posedge i_clk)
	if (ack_delay == 0)
		assert((o_wb_ack)||(f_outstanding == 0));

	always @(posedge i_clk)
	if (ack_delay == 0)
		assert((o_wb_ack)||(!o_wb_stall));

	always @(*)
		assert(ack_delay <= 7'd65);

	always @(*)
	if (cfg_user_mode)
		assert(ack_delay <= 7'd9);

	always @(*)
	if ((!OPT_PIPE)&&(!cfg_user_mode)&&(!o_spi_cs_n))
		assert(((o_spi_sck)||(actual_sck))&&(o_wb_stall));

	always @(*)
		assert((!bus_request)||(!user_request));

	always @(*)
	if (!cfg_user_mode)
		assert((o_spi_cs_n)||((actual_sck)&&(ack_delay>0))
			||((o_spi_sck)&&(ack_delay>1)));

	always @(*)
	if (ack_delay > 1)
		assert(o_wb_stall);

	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(o_spi_sck))&&($past(actual_sck)))
		assert(((o_spi_cs_n)||(cfg_user_mode))
				&&(!o_spi_sck)&&(!actual_sck)&&(ack_delay==0));

	generate if (F_OPT_COVER)
	begin

		always @(posedge i_clk)
			cover(o_wb_ack&&(!$past(bus_request))
				&&(!$past(user_request)));

		reg	f_pending_user_request, f_pending_bus_request;

		initial	f_pending_user_request = 1'b0;
		always @(posedge i_clk)
		if ((i_reset)||(!i_wb_cyc))
			f_pending_user_request <= 1'b0;
		else if (user_request)
			f_pending_user_request <= 1'b1;
		else if (o_wb_ack)
			f_pending_user_request <= 1'b0;

		initial	f_pending_bus_request = 1'b0;
		always @(posedge i_clk)
		if ((i_reset)||(!i_wb_cyc))
			f_pending_bus_request <= 1'b0;
		else if (bus_request)
			f_pending_bus_request <= 1'b1;
		else if (o_wb_ack)
			f_pending_bus_request <= 1'b0;

		always @(posedge i_clk)
			cover((o_wb_ack)&&(f_pending_user_request));

		always @(posedge i_clk)
			cover((o_wb_ack)&&(f_pending_bus_request));

		if (OPT_PIPE)
		begin

			always @(posedge i_clk)
				cover((f_pending_bus_request)
					&&(ack_delay == 7'h1)
					&&(bus_request)&&(o_spi_sck));
			always @(posedge i_clk)
				cover((next_request)&&(f_pending_bus_request)&&(ack_delay == 7'h2));
		end

	end endgenerate

`endif
`ifdef	VERIFIC
	reg	[21:0]	f_last_addr, f_next_addr;

	always @(posedge i_clk)
	if (bus_request)
		f_last_addr <= i_wb_addr[21:0];

	always @(*)
		f_next_addr <= f_last_addr + 1'b1;

	// Writes are immediately returned
	assert property (@(posedge i_clk)
		disable iff ((i_reset)||(!i_wb_cyc))
		((i_wb_stb)||(i_cfg_stb))&&(!o_wb_stall)
				&&(!user_request)&&(!bus_request)
		|=> (o_wb_ack)&&(!o_wb_stall));

	assert property (@(posedge i_clk)
		disable iff ((i_reset)||(!i_wb_cyc))
		(i_wb_stb)&&(!o_wb_stall)&&(!o_spi_cs_n)&&(!i_wb_we)
			&&(!cfg_user_mode)
		|-> (OPT_PIPE)&&(i_wb_addr == f_next_addr)
		);

	sequence READ_COMMAND;
		// Send command 8'h03
		(f_last_addr == $past(i_wb_addr))
				&&(!o_spi_cs_n)&&(o_spi_sck)&&(!o_spi_mosi)
				&&(!actual_sck)
		##1 ( ((f_last_addr == $past(f_last_addr))
			&&(!o_spi_cs_n)&&(o_spi_sck)) throughout
				(!o_spi_mosi)&&(ack_delay==7'd64)&&(actual_sck)
				##1 (!o_spi_mosi)&&(ack_delay==7'd63)&&(actual_sck)
				##1 (!o_spi_mosi)&&(ack_delay==7'd62)&&(actual_sck)
				##1 (!o_spi_mosi)&&(ack_delay==7'd61)&&(actual_sck)
				##1 (!o_spi_mosi)&&(ack_delay==7'd60)&&(actual_sck)
				##1 (!o_spi_mosi)&&(ack_delay==7'd59)&&(actual_sck)
				##1 ( o_spi_mosi)&&(ack_delay==7'd58)&&(actual_sck)
				##1 ( o_spi_mosi)&&(ack_delay==7'd57)&&(actual_sck));
	endsequence

	sequence	SEND_ADDRESS;
		(((f_last_addr == $past(f_last_addr))&&(!o_spi_cs_n)&&(o_spi_sck)
			&&(actual_sck))
		throughout
			(o_spi_mosi == f_last_addr[21])&&(ack_delay==7'd56)
			##1 (o_spi_mosi == f_last_addr[20])&&(ack_delay==7'd55)
			##1 (o_spi_mosi == f_last_addr[19])&&(ack_delay==7'd54)
			##1 (o_spi_mosi == f_last_addr[18])&&(ack_delay==7'd53)
			##1 (o_spi_mosi == f_last_addr[17])&&(ack_delay==7'd52)
			##1 (o_spi_mosi == f_last_addr[16])&&(ack_delay==7'd51)
			##1 (o_spi_mosi == f_last_addr[15])&&(ack_delay==7'd50)
			##1 (o_spi_mosi == f_last_addr[14])&&(ack_delay==7'd49)
			##1 (o_spi_mosi == f_last_addr[13])&&(ack_delay==7'd48)
			##1 (o_spi_mosi == f_last_addr[12])&&(ack_delay==7'd47)
			##1 (o_spi_mosi == f_last_addr[11])&&(ack_delay==7'd46)
			##1 (o_spi_mosi == f_last_addr[10])&&(ack_delay==7'd45)
			##1 (o_spi_mosi == f_last_addr[ 9])&&(ack_delay==7'd44)
			##1 (o_spi_mosi == f_last_addr[ 8])&&(ack_delay==7'd43)
			##1 (o_spi_mosi == f_last_addr[ 7])&&(ack_delay==7'd42)
			##1 (o_spi_mosi == f_last_addr[ 6])&&(ack_delay==7'd41)
			##1 (o_spi_mosi == f_last_addr[ 5])&&(ack_delay==7'd40)
			##1 (o_spi_mosi == f_last_addr[ 4])&&(ack_delay==7'd39)
			##1 (o_spi_mosi == f_last_addr[ 3])&&(ack_delay==7'd38)
			##1 (o_spi_mosi == f_last_addr[ 2])&&(ack_delay==7'd37)
			##1 (o_spi_mosi == f_last_addr[ 1])&&(ack_delay==7'd36)
			##1 (o_spi_mosi == f_last_addr[ 0])&&(ack_delay==7'd35)
			##1 (o_spi_mosi == 1'b0)&&(ack_delay==7'd34)
			##1 (o_spi_mosi == 1'b0)&&(ack_delay==7'd33));
	endsequence

	sequence	READ_DATA;
		(((o_wb_stall)&&(!o_spi_cs_n)&&(o_spi_sck)
			&&(o_wb_data == $past({o_wb_data[30:0], i_spi_miso})))
		throughout
		(ack_delay <= 7'd32)&&(ack_delay >= 7'd25) [*8]
		##1 (ack_delay <= 7'd24)&&(ack_delay >= 7'd17) [*8]
		##1 (ack_delay <= 7'd16)&&(ack_delay >=  7'd9) [*8]
		##1 (ack_delay <=  7'd8)&&(ack_delay >=  7'd2) [*7])
		##1 ((!o_spi_cs_n)&&(actual_sck)&&(ack_delay == 7'd1)
			&&(((OPT_PIPE)&&(i_wb_stb)&&(!i_wb_we)&&(o_spi_sck))
				||((o_wb_stall)&&(!o_spi_sck)))
			&&(o_wb_data == $past({o_wb_data[30:0], i_spi_miso})))
		##1 (o_wb_ack)
			&&(o_wb_data == $past({o_wb_data[30:0], i_spi_miso}))
			&&((OPT_PIPE)||((o_spi_cs_n)
					&&(!o_spi_sck)&&(!actual_sck)));
	endsequence

	assert property (@(posedge i_clk)
		disable iff ((i_reset)||(!i_wb_cyc))
		(i_wb_stb)&&(!o_wb_stall)&&(!i_wb_we)&&(o_spi_cs_n)
			&&(!cfg_user_mode)
		// Send command 8'h03
		|=> READ_COMMAND
		##1 ((f_last_addr == $past(f_last_addr)) throughout
				SEND_ADDRESS)
		##1 READ_DATA);


	//////////////
	//
	// The known data/address contract
	//
	/////////////
	(* anyconst *) wire	[21:0]	f_addr;
	(* anyconst *) wire	[31:0]	f_data;

	sequence	DATA_BYTE(local input [7:0] B);
		(i_spi_miso == B[7])
		##1 (i_spi_miso == B[6])
		##1 (i_spi_miso == B[5])
		##1 (i_spi_miso == B[4])
		##1 (i_spi_miso == B[3])
		##1 (i_spi_miso == B[2])
		##1 (i_spi_miso == B[1])
		##1 (i_spi_miso == B[0]);
	endsequence

	sequence	THIS_DATA;
			DATA_BYTE(f_data[31:24])
			##1 DATA_BYTE(f_data[23:16])
			##1 DATA_BYTE(f_data[15: 8])
			##1 DATA_BYTE(f_data[ 7: 0]);
	endsequence

	// Assume our arbitrary constant data is given as a response to a
	// request for our arbitrary address.
	//
	// This applies both to a straight initial address ...
	assume property (@(posedge i_clk)
		disable iff ((o_spi_cs_n)||(!o_spi_sck))
		(i_wb_stb)&&(!o_wb_stall)&&(!i_wb_we)&&(o_spi_cs_n)
			&&(!cfg_user_mode)
			&&(i_wb_addr[21:0] == f_addr)
		// Send command 8'h03
		##1 READ_COMMAND
		##1 (($stable(f_last_addr)) throughout
				SEND_ADDRESS)
		|=> THIS_DATA);

	// ... as well a pipe address
	assume property (@(posedge i_clk)
		disable iff ((o_spi_cs_n)||(!o_spi_sck))
		(OPT_PIPE)&&(i_wb_stb)&&(!o_wb_stall)&&(!i_wb_we)&&(!o_spi_cs_n)
			&&(!cfg_user_mode)
			&&(i_wb_addr[21:0] == f_addr)
		|=> THIS_DATA);

	// Given a sent address, and our data returned, assert we return the
	// same data on o_wb_data
	assert property (@(posedge i_clk)
		disable iff ((i_reset)||(!i_wb_cyc))
		(i_wb_stb)&&(!o_wb_stall)&&(!i_wb_we)&&(o_spi_cs_n)
			&&(!cfg_user_mode)
			&&(i_wb_addr[21:0] == f_addr)
		// Send command 8'h03
		##1 ((!o_wb_ack) throughout READ_COMMAND)
		##1(((!o_wb_ack)&&($stable(f_last_addr))) throughout
				SEND_ADDRESS)
		##1 THIS_DATA
		|=> (o_wb_ack)&&(o_wb_data == f_data));

	// Same thing as the above, but this time for a piped read request
	assert property (@(posedge i_clk)
		disable iff ((i_reset)||(!i_wb_cyc))
		(OPT_PIPE)&&(i_wb_stb)&&(!o_wb_stall)&&(!i_wb_we)&&(!o_spi_cs_n)
			&&(!cfg_user_mode)
			&&(i_wb_addr[21:0] == f_addr)
		##1 THIS_DATA
		|=> (o_wb_ack)&&(o_wb_data == f_data));

	generate if (OPT_CFG)
	begin
		// Now for configuration writes
		assert property (@(posedge i_clk)
			disable iff ((i_reset)||(!i_wb_cyc))
			((i_cfg_stb)&&(!o_wb_stall)&&(i_wb_we)&&(i_wb_data[8]))
			|=> ((!cfg_user_mode)&&(o_spi_cs_n)&&(!o_spi_sck))
				&&(o_wb_ack)&&(!o_wb_stall));

		reg	[7:0]	f_wr_data;
		always @(posedge i_clk)
		if (user_request)
			f_wr_data <= i_wb_data[7:0];

		assert property (@(posedge i_clk)
			disable iff ((i_reset)||(!i_wb_cyc))
			((i_cfg_stb)&&(!o_wb_stall)&&(i_wb_we)&&(!i_wb_data[8]))
			|=> (((cfg_user_mode)&&(!o_spi_cs_n)&&(o_spi_sck)
				&&(o_wb_stall)) throughout
				(!o_spi_mosi)&&(ack_delay==7'd9)
				##1 (o_spi_mosi == f_wr_data[7])
							&&(ack_delay==7'd8)
				##1 (o_spi_mosi == f_wr_data[6])
							&&(ack_delay==7'd7)
				##1 (o_spi_mosi == f_wr_data[5])
							&&(ack_delay==7'd6)
				##1 (o_spi_mosi == f_wr_data[4])
							&&(ack_delay==7'd5)
				##1 (o_spi_mosi == f_wr_data[3])
							&&(ack_delay==7'd4)
				##1 (o_spi_mosi == f_wr_data[2])
							&&(ack_delay==7'd3)
				##1 (o_spi_mosi == f_wr_data[1])
							&&(ack_delay==7'd2))
			##1 ((cfg_user_mode)&&(!o_spi_cs_n)&&(!o_spi_sck)
				&&(actual_sck)&&(o_wb_stall)
				&&(o_spi_mosi == f_wr_data[0])
							&&(ack_delay==7'd1))
			##1 (o_wb_ack)&&(!o_wb_stall)&&(cfg_user_mode)
				&&(!o_spi_sck)&&(!actual_sck)&&(!o_wb_stall));

		assert property (@(posedge i_clk)
			disable iff ((i_reset)||(!i_wb_cyc))
			((i_cfg_stb)&&(!o_wb_stall)&&(i_wb_we)&&(!i_wb_data[8]))
			##2 DATA_BYTE(f_data[7:0])
			|=> (o_wb_ack)&&(o_wb_data[7:0] == f_data[7:0])
				&&(cfg_user_mode)&&(!o_wb_stall));
	end endgenerate
`endif
endmodule
// Usage on an iCE40
// 		NoCfg	NoPipe	Piped
// Cells	139	157		246
// SB_CARRY	 10	 10		 30
// SB_DFF	 21	 21		 21
// SB_DFFE	 33	 10		 32
// SB_DFFESR	  7	 31		 31
// SB_DFFSR	 10	 10		 10
// SB_DFFSS	  2	  2		  2
// SB_LUT4	 56	 73		120
//
