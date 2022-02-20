**Always backup the target file first**

Writes data into spare space in ELF-64 binary or shared library.

Many ELF files have spare space at the start, often because they page-align sections. This writes data in there. The ELF binary or shared library won't know and will still function.

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

Mostly this is about me practicing assembly.
