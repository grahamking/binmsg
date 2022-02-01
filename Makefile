main: main.s
	nasm -felf64 main.s
	# -n -N prevent page alignment, much small file
	ld -n -N -o xwrite  main.o

.SILENT: main
