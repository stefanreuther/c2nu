all: c2nuvcr.pl c2nuall.pl

c2nuvcr.pl: c2nu.pl split.pl
	perl split.pl -DCMD_VCR=1 < c2nu.pl > c2nuvcr.pl

c2nuall.pl: c2nu.pl split.pl
	perl split.pl -DCMD_RST=1 -DCMD_UNPACK=1 -DCMD_MAKETURN=1 -DCMD_DUMP=1 -DCMD_VCR=1 -DCMD_RUNHOST=1 < c2nu.pl > c2nuall.pl

ifneq ($(VERSION),)
.PHONY: dist
dist: all
	$(RM) c2nuvcr-$(VERSION).zip c2nu-$(VERSION).zip c2nu-$(VERSION)-src.zip
	zip -9 c2nuvcr-$(VERSION).zip c2nuvcr.pl c2nuvcr.txt
	zip -9 c2nu-$(VERSION).zip c2nuall.pl
	zip -9 c2nu-$(VERSION)-src.zip c2nu.pl c2nu.txt split.pl Makefile
endif
