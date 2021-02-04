NAME = kvstore
VERS = 0.8.1
ARCH = 64
DC = dmd
DR = rdmd
DS = dscanner --styleCheck
STRIP = strip --strip-all
TAIL = tail -n 1
CP = cp
LN = ln -s
RM = rm -f
TAR = tar cJf
DFLAGS = -shared -release -fPIC -O -H -m$(ARCH) -de -w -D -Dddoc \
	-preview=markdown -of=lib$(NAME).so
TFLAGS = -debug -g -m$(ARCH) -de -w -unittest -cov -main

.PHONY: all build clean coverage lint pack test install uninstall

all: $(NAME)

build: $(NAME)

$(NAME): $(NAME).d
	$(DC) $(DFLAGS) $<
	$(STRIP) lib$(NAME).so

lint: $(NAME).d
	$(DS) $<

test: $(NAME).d
	$(DR) $(TFLAGS) $<
	$(TAIL) $(NAME).lst

install: $(NAME) uninstall
	$(CP) lib$(NAME).so /usr/lib
	$(LN) /usr/lib/lib$(NAME).so /usr/lib/lib$(NAME).$(VERS).so

uninstall:
	$(RM) /usr/lib/lib$(NAME)*.so

clean:
	$(RM) -r *$(NAME)*.{a,so,dll,lib,dylib} *$(NAME)_{test,cov}* \
	*.{o,obj,exe,lst} *~ __main.* .dub doc/* docs/ \
	docs.json __dummy.html

pack:
	$(TAR) $(NAME)_$(VERS).txz *.d *.di Makefile README* LICENSE \
	dub*.json .gitignore
