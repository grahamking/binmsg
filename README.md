Write data into spare space in ELF-64 binary. I'm just practicing assembly.

Many ELF binaries have spare space at the start, often because they page-align sections. This writes data in there. The ELF binary won't know and will still function.

Ideas:

- Put a version number, build date, git hash in your binary.
- Write some notes in there. "Use this one to fix weird customer dat files".
- Store binary data. A (small) program within a program? Secret data for basic steganography?

Build:

- Requirements: x86-64 Linux, `nasm` assembler, `make`.
- Build: `make`

Use:

- Write into file: `echo -n 'some_data' | binmsg <filename>`
- Read from file: `binmsg <filename>`. If the file doesn't have any data it will tell you how much space it has.

Note the `-n` in echo command above to suppress the new line, which makes little sense embedded in a binary.

Only supports EXE ELF files, which is **not many**. Most of your files are probably DYN. Do `readelf -h <file>` and look at "Type" field. `binmsg` will currently only work if that says "EXEC". And even then it doesn't always support those, but am improving it all the time. Assembly is about the journey.
