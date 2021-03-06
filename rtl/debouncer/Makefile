################################################################################
##
## Filename: 	debouncer/Makefile
##
## Project:	ICO Zip, iCE40 ZipCPU demonsrtation project
##
## Purpose:	To coordinate the build of a button debouncing test design
##		for the icoboard.
##
## Creator:	Dan Gisselquist, Ph.D.
##		Gisselquist Technology, LLC
##
################################################################################
##
## Copyright (C) 2016-2017, Gisselquist Technology, LLC
##
## This program is free software (firmware): you can redistribute it and/or
## modify it under the terms of  the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or (at
## your option) any later version.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
## FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
## for more details.
##
## You should have received a copy of the GNU General Public License along
## with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
## target there if the PDF file isn't present.)  If not, see
## <http://www.gnu.org/licenses/> for a copy.
##
## License:	GPL, v3, as defined and found on www.gnu.org,
##		http://www.gnu.org/licenses/gpl.html
##
##
################################################################################
##
##
all: testbus
# ARACHNEPNR := arachne-pnr
YOSYS      := yosys
ARACHNEPNR := /home/dan/work/rnd/opencores/icozip/arachne-pnr/bin/arachne-pnr
ICEPACK    := icepack
ICETIME    := icetime

# GNU Make automatic variables (since I can never remember these ...)
# $@	- name of the target
# $<	- Name of the first prerequisite
# $^	- Names of all the prerequisites
%.blif: %.v
	$(YOSYS) -p 'synth_ice40 -blif $@' $<
%.asc: %.blif %.pcf
	$(ARACHNEPNR) -d 8k -p $*.pcf -o $@ $<
%.bin: %.asc
	$(ICETIME) -d hx8k -c 80 $<
	$(ICEPACK) $< $@

PPSRCS := ppio.v pport.v
HEXSRCS := hbbus.v hbdechex.v hbdeword.v hbexec.v hbgenhex.v hbidle.v hbints.v hbnewline.v hbpack.v
PSRCS := $(addprefix ../pport/,$(PPSRCS))
HSRCS := $(addprefix ../hexbus/,$(HEXSRCS))
VSRCS :=  testbus.v debouncer.v unbounced.v wbscopc.v # wbscope.v
testbus.blif: $(VSRCS) $(HSRCS)
	$(YOSYS) -p 'synth_ice40 -blif $@ -top testbus' $(VSRCS) $(HSRCS) $(PSRCS) | tee log.txt
testbus.asc: testbus.blif debouncer.pcf
	$(ARACHNEPNR) -d 8k -p debouncer.pcf -o $@ $< | tee -a log.txt


.PHONY: testbus
testbus: testbus.bin

clean:
	rm -f *.blif *.asc *.bin
	rm -rf obj_dir

