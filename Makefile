# ECW Expression Calculator — build wrapper around ./build.sh
#
#   make          build the GUI   -> ./ecwcalc
#   make gui      build the GUI
#   make cli      build the CLI   -> ./ecw
#   make battery  run the regression battery against ./ecw
#   make clean    remove build artifacts

.PHONY: all gui cli battery clean

all: gui

gui:
	./build.sh gui

cli:
	./build.sh cli

battery: cli
	python3 tests/battery.py ./ecw

clean:
	rm -rf lib lib-cli
	rm -f ecw ecwcalc ecwcalc.exe
	rm -f *.o *.ppu *.compiled
