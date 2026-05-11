# Makefile for JPEG-XS Textbook (ElegantBook + xelatex)
# Usage:
#   make          — build PDF
#   make clean    — remove build artifacts
#   make watch    — continuous rebuild on changes

MAIN = main
LATEXMK = latexmk -xelatex -interaction=nonstopmode

.PHONY: all clean watch

all: $(MAIN).pdf

$(MAIN).pdf: $(MAIN).tex preamble.tex chapters/*.tex examples/*.tex appendices/*.tex
	$(LATEXMK) $(MAIN).tex

clean:
	latexmk -C $(MAIN).tex
	rm -f *.bbl *.blg *.fdb_latexmk *.fls *.synctex.gz *.run.xml *.bcf

watch:
	$(LATEXMK) -pvc -xelatex $(MAIN).tex
