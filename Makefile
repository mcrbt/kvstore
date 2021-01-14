NAME = kvstore
VERS = 0.8.1
ARCH = 64
DC = dmd
DR = rdmd
DS = dscanner --styleCheck
DFLAGS = -shared -release -fPIC -O -H -m$(ARCH) -de -w -D -Dddoc \
	-preview=markdown -of=lib$(NAME).so
RFLAGS = -debug -g -m$(ARCH) -de -w -of=$(NAME)_test -unittest -main

.PHONY: all build clean lint pack test install uninstall

all: $(NAME)

build: $(NAME)

$(NAME): $(NAME).d
	$(DC) $(DFLAGS) $<
	strip --strip-all lib$(NAME).so

lint: $(NAME).d
	$(DS) $<

test: $(NAME).d
	$(DR) $(RFLAGS) $<

install: $(NAME) uninstall
	cp lib$(NAME).so /usr/lib
	ln -s /usr/lib/lib$(NAME).so /usr/lib/lib$(NAME).$(VERS).so

uninstall:
	rm -f /usr/lib/lib$(NAME)*.so

clean:
	rm -rf *$(NAME)*.{a,so,dll,lib,dylib} *$(NAME)_test* \
		*.{o,obj,exe,lst} *~ __main.di .dub doc/* docs/ \
		docs.json __dummy.html

pack:
	tar cJf $(NAME)_$(VERS).txz *.d *.di Makefile README* LICENSE \
		dub*.json .gitignore
