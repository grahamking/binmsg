Write data into spare space in ELF-64 binary. I'm just practicing assembly.

Many ELF binaries have spare space at the start, often because they page-align sections. This writes data in there. The ELF binary won't know and will still function.

Ideas:
	- Put a version number, build date, git hash in your binary.
	- Write some notes in there. "Use this one to fix weird customer dat files".
	- Store binary data. A (small) program within a program? Secret data for basic steganography?

- Requirements: x86-64 Linux, `nasm` assembler, `make`.
- Build: `make`
- Run: `echo -n 'some_data' | xwrite <filename>`

Note the `-n` in echo command above to suppress the new line, which makes little sense embedded in a binary.

The name will probably change.
