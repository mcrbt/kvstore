NAME = kvstore
VERS = 0.7.1
ARCH = 64
DC = dmd
DR = rdmd
DFLAGS = -shared -release -fPIC -O -H -m$(ARCH) -de -w -D -Dddoc \
	-preview=markdown -of=lib$(NAME).so
RFLAGS = -debug -g -m$(ARCH) -de -w -of=$(NAME)_test -unittest -main

.PHONY: all build clean pack test install uninstall

all: $(NAME)

build: $(NAME)

$(NAME): $(NAME).d
	$(DC) $(DFLAGS) $<
	strip --strip-all lib$(NAME).so

test: $(NAME).d
	$(DR) $(RFLAGS) $<

install: $(NAME) uninstall
	cp lib$(NAME).so /usr/local/lib
	ln -s /usr/local/lib/lib$(NAME).so /usr/local/lib/lib$(NAME).$(VERS).so

uninstall:
	rm -f /usr/local/lib/lib$(NAME)*.so

clean:
	rm -rf *$(NAME)*.{a,so,dll,lib,dylib} *$(NAME)_test* \
		*.{o,obj,exe,lst} *~ __main.di .dub doc/* docs/ \
		docs.json __dummy.html

pack:
	tar cJf $(NAME)_$(VERS).txz *.d *.di Makefile README* LICENSE \
		dub*.json .gitignore
