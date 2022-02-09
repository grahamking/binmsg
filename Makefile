main: funcs main.s
	nasm -g -felf64 main.s
	ld -n -N -o binmsg funcs.o main.o # -n and -N prevent page alignment, much smaller binary

funcs: funcs.s
	nasm -g -felf64 funcs.s

clean:
	rm *.o
	rm binmsg

.SILENT: main funcs clean
