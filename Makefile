c2nuvcr.pl: c2nu.pl split.pl
	perl split.pl -DCMD_VCR=1 < c2nu.pl > c2nuvcr.pl
