% citing text (probably from the homework spec
\def\begincite{\begingroup\smallskip \leftskip=.5in \rightskip=.5in}
\def\endcite{\smallskip\endgroup}

\datethis

@* Introduction.  This is a
{\bf p}rocessor and {\bf c}ontrol {\bf sim}ulator
for ECE550 Homework~4.
It's named like this because the processor and control are
the parts we are actually to implement in this homework, in hardware,
even though this program also simulates other stuff (e.g.~ALU).

The program is arranged as follows:
@p
@<headers@>@/
@<declarations@>@/
@<global variables@>@/
@<function definitions@>@/
@<main program@>

@ The specification of the instruction set is copy-and-pasted
from the homework spec, for easy reference.

\begincite
Your CPU has 32 general purpose registers: \$r0--\$r31.
Register \$r0 is the constant value~0
(i.e., an instruction can specify it as a destination but
``writing'' to \$r0 must not change its value).
The register \$r31 is the link register for the {\tt jal} instruction
(similar to \$ra in MIPS).
The user of your CPU may write to it with other instructions,
but that would mess up function call/return for them.
\endcite

\begingroup\tabskip=.5em plus 1fil
\let\$=$ % it's handy to disable $ as math shift character,
         % but it confuses syntax highlighter.
\catcode`\$=12 

% now, $ is an ordinary $, \$ actually switches math mode
\offinterlineskip\smallskip
\halign to\hsize{
\strut\hfil\tt#\hfil&\hfil\tt#\hfil&\hfil\tt#\hfil&\tt#\hfil&\$#\$\hfil\cr
\noalign{\hrule\kern2pt}
\bf instruction&\bf opcode&\bf type&\hfil\bf usage&
\hfil\hbox{\bf operation}\cr
\noalign{\kern2pt\hrule\kern2pt}
     add& 00000&  R&   add $rd, $rs, $rt&     $rd = $rs + $rt\cr
     sub& 00001&  R&   sub $rd, $rs, $rt&     $rd = $rs - $rt\cr
     and& 00010&  R&   and $rd, $rs, $rt&     $rd = $rs \mathop{\rm AND} $rt\cr
      or& 00011&  R&    or $rd, $rs, $rt&     $rd = $rs \mathop{\rm OR} $rt\cr
     sll& 00100&  R&   sll $rd, $rs, $rt&
$rd = $rs \hbox{ shifted left by } $rt[4{:}0]\hbox{, zero-fill}\cr
     srl& 00101&  R&   srl $rd, $rs, $rt&
$rd = $rs \hbox{ shifted right by } $rt[4{:}0]\hbox{, zero-extend}\cr
    addi& 00110&  I&  addi $rd, $rs, N&       $rd = $rs + N\cr
      lw& 00111&  I&    lw $rd, N($rs)&       $rd = {\it Mem}[$rs+N]\cr
      sw& 01000&  I&    sw $rd, N($rs)&       {\it Mem}[$rs+N] = $rd\cr
     beq& 01001&  I&   beq $rd, $rs, N&
{\bf if}\mathinner{($rd\equiv$rs)}{\bf then}\>PC=PC+1+N\cr
     bgt& 01010&  I&   bgt $rd, $rs, N&
{\bf if}\mathinner{($rd>$rs)}{\bf then}\>PC=PC+1+N\cr
      jr& 01011&  I&    jr $rd&               PC = $rd\cr
       j& 01100&  J&     j N&                 PC = N\cr
     jal& 01101&  J&   jal N&                 $r31 = PC + 1;\; PC = N\cr
   input& 01110&  I& input $rd&               $rd = \hbox{keyboard input}\cr
  output& 01111&  I& output $rd&
\hbox{print character \$$rd[7{:}0]\$ on LCD display}\cr
\noalign{\kern2pt\hrule}
}\bigskip\endgroup

The formats of the R, I, and J~type instructions are shown below.  

\begingroup\tabskip=.5em plus 1fil
\offinterlineskip\smallskip
\def\strut{\vrule width0pt height10.5pt depth 4.5pt} % slightly higher
\halign to\hsize{\vrule#&\strut\hfil\bf#\hfil&&\vrule#&\hfil#\hfil\cr
\multispan{13}\hrulefill\cr
& Type&&\multispan9\hfil\bf Format\hfil&\cr
\multispan{13}\hrulefill\cr
& R&& Opcode [31:27]&& Rd [26:22]&& Rs [21:17]&& Rt [16:12]&& Zeroes [11:0]&\cr
\multispan{13}\hrulefill\cr
& I&& Opcode [31:27]&& Rd [26:22]&& Rs [21:17]&&
\multispan2\span Immediate [16:0]&\cr
\multispan{13}\hrulefill\cr
& J&& Opcode [31:27]&&
\multispan6\span Target [26:0]&\cr
\multispan{13}\hrulefill\cr
}\endgroup


@* Common routines.

@<headers@>+=
#include <stdio.h> /* need I/O functions */
#include <stdlib.h> /* for |exit|, etc. */
#include <stdarg.h> /* for |va_list|, etc. */

@ In case of fatal error, we need a function to print an error message
and exit.
@<function definitions@>+=
void
fatal_error(const char *msgfmt, ...)
{
	va_list va;

	va_start(va, msgfmt);
	vfprintf(stderr, msgfmt, va);
	va_end(va);
	fprintf(stderr, "\n");
	exit(EXIT_FAILURE);
}

@ The testing programs will enter a dead loop when finished.
That's how it works on the hardware, but in the simulation
we do not want to waste CPU cycles doing these meaningless loops.

@<headers@>+=
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <unistd.h>
#endif

@ @<function definitions@>+=
void simulator_idle(void)
{
#ifdef _WIN32
	Sleep(1);
#else
	usleep(1000);
#endif
}


@* Memory.
First of all, the word width is 32~bit.
@d WORD_WIDTH 32
@s uint32_t int
@<headers@>+=
#include <stdint.h> /* for |uint32_t| */

@ We define a custom type |word_t| to be used for elements in the
instruction/data memory.
@s word_t int
@<declarations@>+=
typedef uint32_t word_t;

@ According to the spec, PC is 12-bit wide.
Therefore, the instruction memory has $2^{12}=4096$ words.
@d PC_WIDTH 12
@d IMEM_SIZE (1<<PC_WIDTH)

@<global variables@>+=
word_t iMem[IMEM_SIZE];

@ We also define the data memory.
@d DMEM_SIZE 1048576 /* ??? */

@<global variables@>+=
word_t dMem[DMEM_SIZE];

@ The instruction/data memory can be initialized from an image.

@<function definitions@>+=
void
load_mem(word_t *mem, size_t size, const char *filename)
{
	FILE *f;
	size_t nRead;

	f = fopen(filename, "rb");
	if (f == NULL)
		fatal_error("Cannot open %s", filename);
	nRead = fread(mem, size, sizeof (word_t), f);
	fclose(f);
	if (nRead != size)
		fatal_error("bad memory image");
}

@ Or, it can be initialized from an hex file, which is the output format
used by the a provided assembler.

@<function definitions@>+=
static unsigned long
parsehex(char *begin, char *end)
{
	*end = '\0';
	return strtoul(begin, NULL, 16);
}

void
load_mem_hex(word_t *mem, size_t size, const char *filename)
{
	FILE *f;
	unsigned addr;
	unsigned long data;
	char buf[100];

	f = fopen(filename, "rb");
	if (f == NULL)
		fatal_error("Cannot open %s", filename);
	for (;;) {
		fgets(buf, 100, f); /* no |gets|? :-) */
		if (!(buf[7] == '0' && buf[8] == '0'))
			break;
		data = parsehex(buf + 9, buf + 17);
		addr = parsehex(buf + 3, buf + 7);
		mem[addr] = data;
	}
	fclose(f);
	return;
}


@*Input/Output. 
The program can get input from the keyboard,
and print characters to the screen.

(Link curses library ({\tt -lcurses}) if using it.)

@<headers@>+=
#ifdef _WIN32
# include <conio.h>
#else
# include <curses.h>
#endif

@ @<function definitions@>+=
word_t simulator_input(void)
{
#ifdef _WIN32
	return _getch();
#else
	return getch();
#endif
}

void simulator_output(word_t ch)
{
#ifdef _WIN32
	_putch(ch);
#else
	echochar(ch);
#endif
}

@ The console may need initialization before use,
and finialization after use.
@s WINDOW int
@<global variables@>+=
#ifndef _WIN32
WINDOW *mainwin;
#endif

@ @<function definitions@>+=
void simulator_conini(void)
{
#ifndef _WIN32
	if ((mainwin = initscr()) == NULL)
		fatal_error("cannot init console");
	cbreak();
	noecho();
	scrollok(mainwin, 1);
#endif
}

void simulator_confin(void)
{
#ifndef _WIN32
	delwin(mainwin);
	endwin();
	refresh();
#endif
}

@* Simulation.  We define a function that simulates the processor.
Basically it first sets $PC$ to the start address, and then keeps
executing instuctions.

@<function definitions@>+=
void simulate(word_t pc)
{
	word_t r[32] = {0}; /* the register file */
	word_t instcode; /* instruction code */

	simulator_conini();
	for (;;) {
		r[0] = 0; /* constant zero */
		@<execute the instruction at |pc|@>@;
	}
	simulator_confin();
}

@ Inside the above for loop, we will fetch and execute each instruction.
To ``simplify'' code, we define some macros which will automatically
expand to the corresponding opcode/register/immediate/target.

@d OPCODE (instcode>>27)
@d RD (r[(instcode>>22)&31])
@d RS (r[(instcode>>17)&31])
@d RT (r[(instcode>>12)&31])
@d ZEROIMM (instcode&(((word_t)1<<17)-1))
@d SIGNIMM ((instcode&((word_t)1<<16))?((~(word_t)0)<<17)|ZEROIMM:ZEROIMM)
@d TARGET (instcode&(((word_t)1<<27)-1))

@<execute...@>=
if (pc >= IMEM_SIZE)
	fatal_error("PC went out of range");
instcode = iMem[pc++];
/* Note: |pc| is incremented before executing the instruction */
switch (OPCODE) {
	@<cases for different opcodes@>@;
}

@ The R~type instructions ({\tt add}, {\tt sub}, {\tt and}, {\tt or},
{\tt sll} and {\tt srl}) are easy to implement.
@<cases for...@>+=
case 0: /* \tt add */
	RD = RS + RT; break;
case 1: /* \tt sub */
	RD = RS - RT; break;
case 2: /* \tt and */
	RD = RS & RT; break;
case 3: /* \tt or */
	RD = RS | RT; break;
case 4: /* \tt sll */
	RD = RS << (RT & 31); break;
case 5: /* \tt srl */
	RD = RS >> (RT & 31); break;

@ {\tt addi} is also easy, but it is an I~type instruction.
@<cases for...@>+=
case 6: /* \tt addi */
	RD = RS + SIGNIMM; break;

@ {\tt lw} and {\tt sw} involves reading and writing data memory.
@<cases for...@>+=
case 7: /* \tt lw */
	RD = dMem[RS + SIGNIMM]; break;
case 8: /* \tt sw */
	dMem[RS + SIGNIMM] = RD; break;

@ {\tt beq} may conditionally modify the program counter.
@<cases for...@>+=
case 9: /* \tt beq */
	if (RD == RS) {
		@<do branch@>@;
	}
	break;

@ Be careful, {\tt bgt} is doing comparison with 2's complement numbers.
@d WORD_MSB (1<<(WORD_WIDTH-1)) /* most significant bit */
@<cases for...@>+=
case 10: /* \tt bgt */
	if (RD + WORD_MSB > RS + WORD_MSB) {
		@<do branch@>@;
	}
	break;

@ @<do branch@>=
pc += SIGNIMM;
if (~SIGNIMM == 0) /* dead loop */
	simulator_idle();

@ {\tt jr} is an I~type instruction but it does not use the immediate.
@<cases for...@>+=
case 11: /* \tt jr */
	pc = RD; break;

@ Now the (only) two J~type instructions: {\tt j} and {\tt jal}.
@<cases for...@>+=
case 13: /* \tt jal */
	r[31] = pc;
case 12: /* \tt j */
{
	word_t oldpc = pc-1;
	pc = TARGET & ((1<<12)-1);
	if (pc == oldpc) /* dead loop */
		simulator_idle();
	break;
}

@ For {\tt input} and {\tt output} instructions, we use functions
defined in other sections.
@<cases for...@>+=
case 14: /* input */
	RD = simulator_input();
	break;
case 15: /* output */
	simulator_output(RD & 255);
	break;

@ For any other opcode, it is an illegal instruction.
@<cases for...@>+=
default:
	fatal_error("illegal opcode at pc=%lu\n", (unsigned long) (pc-1));
	break;

@*The main program.

@<main program@>=
int main(int argc, char *argv[])
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s imem_image dmem_image\n", argv[0]);
		return 1;
	}
	load_mem_hex(iMem, IMEM_SIZE, argv[1]);
	if (argc > 2) {
		load_mem_hex(dMem, DMEM_SIZE, argv[2]);
	}
	simulate(0);
	return 0;
}

@* Index.
