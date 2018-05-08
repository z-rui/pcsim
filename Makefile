CFLAGS=-Wall -ggdb3
CFLAGS+=-O2

all: doc prog

prog: pcsim

pcsim: pcsim.o
	$(CC) -o $@ pcsim.o -lncurses

doc: pcsim.pdf

pcsim.pdf: pcsim.tex
	pdftex pcsim

clean:
	rm -f pcsim pcsim.{tex,log,idx,o,scn,toc}

.PHONY: all prog doc clean
