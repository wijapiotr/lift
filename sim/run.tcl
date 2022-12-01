vlib work
vmap work work

vlog -sv -F ../rtl/filelist.f
vlog lift_tb.sv
vsim -voptargs=+acc lift_tb
onfinish stop
log -r /*
run -a
quit -f
