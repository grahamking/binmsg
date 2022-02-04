main: funcs main.s
	nasm -g -felf64 main.s
	# -n -N prevent page alignment, much smaller binary
	ld -n -N -o xwrite funcs.o main.o

funcs: funcs.s
	nasm -g -felf64 funcs.s

.SILENT: main funcs
