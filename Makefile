all: c2nuvcr.pl c2nuall.pl

c2nuvcr.pl: c2nu.pl split.pl
	perl split.pl -DCMD_VCR=1 < c2nu.pl > c2nuvcr.pl

c2nuall.pl: c2nu.pl split.pl
	perl split.pl -DCMD_RST=1 -DCMD_UNPACK=1 -DCMD_MAKETURN=1 -DCMD_DUMP=1 -DCMD_VCR=1 -DCMD_RUNHOST=1 < c2nu.pl > c2nuall.pl
