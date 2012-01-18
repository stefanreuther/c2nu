#!/usr/bin/perl -w
#
#  planets.nu interface
#
#  This script accesses the Nu server by HTTP and converts between Nu
#  data and VGA Planets data. It operates in the current directory. It
#  will maintain a state file which stores some settings as well as
#  required cookies.
#
#  A Nu RST file is a JSON data structure and contains the
#  specification files, RST, and some history data.
#
#  Usage:
#    perl c2nu.pl [--host=H] [--backups=[01]] [--root=DIR] CMD [ARGS...]
#
#  Options:
#    --host=H       set host name (setting will be stored in state file)
#    --backups=0/1  disable/enable backup of received Nu RST files. Note
#                   that those are rather big so it makes sense to compress
#                   the backups.
#    --dropmines=0/1  disable/enable removal of mines from PCC chart db
#    --root=DIR     set root directory containing VGA Planets spec files.
#                   Those are used to "fill in the blanks" not contained
#                   in a Nu RST.
#
#  Commands:
#    help           Help screen (no network access)
#    status         Show state file content (no network access)
#    login USER PW  Log in with user Id and password
#    list           List games (must be logged in)
#if CMD_RST
#    rst [GAME]     Download Nu RST (must be logged in). GAME is the game
#                   number and can be omitted on second and later uses.
#                   Convert the Nu RST file to VGAP RST.
#endif
#if CMD_UNPACK
#    unpack [GAME]  Download Nu RST and create DAT/DIS files. This has the
#                   advantage of leaving undo information for building.
#endif
#if CMD_MAKETURN
#    maketurn       Create turn commands and upload.
#endif
#if CMD_DUMP
#    dump [GAME]    Download Nu RST and dump beautified JSON.
#endif
#if CMD_VCR
#    vcr [GAME]     Download Nu RST and create VGAP VCRx.DAT for PlayVCR.
#endif
#if CMD_RUNHOST
#    runhost        Run host for a solo game you previously downloaded
#endif
#
#  All download commands can be split in two halves, i.e. "vcr1 [GAME]"
#  to perform the download, and "vcr2" to convert the download without
#  accessing the network.
#
#if CMD_MAKETURN
#  Likewise, "maketurn" can be split into "maketurn1" (to prepare the
#  data) and "maketurn2" to upload it. Since "maketurn2" modifies server
#  data, it would be wise to always download new data from the server
#  after uploading.
#
#endif
#  Instructions:
#  - make a directory and go there using the command prompt
#  - log in using 'c2nu --host=planets.nu login USER PASS'
#  - list games using 'c2nu list'
#  - download stuff using 'c2nu --root=DIR vcr', where DIR is the
#    directory containing your VGA Planets installation, or PCC2's
#    'specs' direcory. Alternatively, copy a 'hullfunc.dat' file
#    into the current directory before downloading the game.
#
#  Since the server usually sends gzipped data, this script needs the
#  'gzip' program in the path to decompress it.
#
#  (c) 2011-2012 Stefan Reuther
#
use strict;
use Socket;
use IO::Handle;
use bytes;              # without this, perl 5.6.1 doesn't correctly read Unicode stuff

my $VERSION = "0.1";
my $opt_rootDir = "/usr/share/planets";

# Initialisation
stateSet('host', 'planets.nu');
stateLoad();

# Parse arguments
while (@ARGV) {
    if ($ARGV[0] =~ /^--?host=(.*)/) {
        stateSet('host', $1);
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^--?backup=(\d+)/) {
        stateSet('backups', $1);
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^--?drop[-_]?mines=(\d+)/) {
        stateSet('dropmines', $1);
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^--?root=(.*)/) {
        $opt_rootDir = $1;
        shift @ARGV;
    } else {
        last;
    }
}

# Command switch
if (!@ARGV) {
    die "Missing command name. '$0 --help' for help.\n";
}
my $cmd = shift @ARGV;
$cmd =~ s/^--?//;
if ($cmd eq 'help') {
    doHelp();
} elsif ($cmd eq 'status') {
    doStatus();
} elsif ($cmd eq 'login') {
    doLogin();
} elsif ($cmd eq 'list') {
    doList();
#if CMD_RST
} elsif ($cmd =~ /^rst([12]?)$/) {
    doDownloadResult() unless $1 eq '2';
    doWriteResult()    unless $1 eq '1';
#endif
#if CMD_UNPACK
} elsif ($cmd =~ /^unpack([12]?)$/) {
    doDownloadResult() unless $1 eq '2';
    doUnpack()         unless $1 eq '1';
#endif
#if CMD_MAKETURN
} elsif ($cmd =~ /^maketurn([12]?)$/) {
    doMakeTurn()       unless $1 eq '2';
    doUploadTurn()     unless $1 eq '1';
#endif
#if CMD_DUMP
} elsif ($cmd =~ /^dump([12]?)$/) {
    doDownloadResult() unless $1 eq '2';
    doDump()           unless $1 eq '1';
#endif
#if CMD_VCR
} elsif ($cmd =~ /^vcr([12]?)$/) {
    doDownloadResult() unless $1 eq '2';
    doWriteVcr()       unless $1 eq '1';
#endif
#if CMD_RUNHOST
} elsif ($cmd eq 'runhost') {
    doRunHost();
#endif
} else {
    die "Invalid command '$cmd'. '$0 --help' for help\n";
}
stateSave();
exit 0;

######################################################################
#
#  Help
#
######################################################################
sub doHelp {
    print "$0 - planets.nu interface - version $VERSION, (c) 2011-2012 Stefan Reuther\n\n";
    print "$0 [options] command [command args]\n\n";
    print "Options:\n";
    print "  --host=HOST       instead of 'planets.nu'\n";
    print "  --backups=0/1     disable/enable backup of Nu RST\n";
    print "  --dropmines=0/1   disable/enable removal of minefields from chart DB\n";
    print "  --root=DIR        set root directory containing VGA Planets spec files\n\n";
    print "Commands:\n";
    print "  help              this help screen\n";
    print "  status            show status\n";
    print "  login USER PASS   log in\n";
    print "  list              list games\n";
#if CMD_RST
    print "  rst [GAME]        download Nu RST and convert to VGAP RST\n";
#endif
#if CMD_UNPACK
    print "  unpack [GAME]     download Nu RST and create unpacked data\n";
#endif
#if CMD_MAKETURN
    print "  maketurn          create turn file and upload\n";
#endif
#if CMD_DUMP
    print "  dump [GAME]       download Nu RST and dump JSON\n";
#endif
#if CMD_VCR
    print "  vcr [GAME]        download Nu RST and create VGAP VCRx.DAT\n";
#endif
#if CMD_RUNHOST
    print "  runhost           run host for solo game\n";
#endif
    print "\n";
    print "Download commands can be split into the download part ('vcr1') and the\n";
    print "convert part ('vcr2').\n";
#if CMD_MAKETURN
    print "Likewise, 'maketurn1' just generates the turn, 'maketurn2' uploads it.\n";
#endif
}

#autosplit
######################################################################
#
#  Log in
#
######################################################################
sub doLogin {
    if (@ARGV != 2) {
        die "login: need two arguments, user name and password\n";
    }

    my $user = $ARGV[0];
    my $pass = $ARGV[1];

    my $reply = httpCall("POST /_ui/signin?method=Authenticate&type=get HTTP/1.0\n",
                         httpBuildQuery(UserName => $user,
                                        Password => $pass,
                                        Remember => 'true'));

    my $parsedReply = jsonParse($reply->{BODY});
    if (exists($parsedReply->{success}) && $parsedReply->{success} =~ /true/i) {
        print "++ Login succeeded ++\n";
        stateSet('user', $user);
        foreach (sort keys %$reply) {
            if (/^COOKIE-(.*)/) {
                stateSet("cookie_$1", $reply->{$_});
            }
        }
    } else {
        print "++ Login failed ++\n";
        print "Server answer:\n";
        foreach (sort keys %$parsedReply) {
            printf "%-20s %s\n", $_, $parsedReply->{$_};
        }
    }
}

######################################################################
#
#  List
#
######################################################################
sub doList {
    my $reply = httpCall("POST /_ui/plugins?method=Refresh&type=get&assembly=PlanetsNu.dll&object=PlanetsNu.DashboardFunctions HTTP/1.0\n", "");
    my $parsedReply = jsonParse($reply->{BODY});
    my $needHeader = 1;
    if (exists($parsedReply->{games})) {
        my $parsedXML = xmlParse($parsedReply->{games});
        foreach my $table (xmlIndirectChildren('table', $parsedXML)) {
            my @rows = xmlIndirectChildren('tr', @{$table->{CONTENT}});

            # Find game type
            my $type = "Games";
            if (@rows
                && $rows[0]{CONTENT}[0]{TAG} eq 'th'
                && !ref($rows[0]{CONTENT}[0]{CONTENT}[0]))
            {
                $type = $rows[0]{CONTENT}[0]{CONTENT}[0];
                shift @rows;
            }

            # Find game number: there is a link with "planetsDashboard.loadGame(<nr>);return false"
            my $gameNr = 0;
            foreach my $a (xmlIndirectChildren('a', xmlMergeContent(@rows))) {
                if (exists($a->{onclick}) && $a->{onclick} =~ m#planetsDashboard.loadGame\((\d+)\)#) {
                    $gameNr = $1;
                }
            }
            next if !$gameNr;

            # Find race: there is an image at "http://library.vgaplanets.nu/races/<race>.png"
            my $race = 0;
            foreach my $img (xmlIndirectChildren('img', xmlMergeContent(@rows))) {
                if (exists($img->{src}) && $img->{src} =~ m#/races/(\d+)\.(png|jpg|gif)#i) {
                    $race = $1;
                }
            }

            # Find game name: for real games, there is a link to "/games/<nr>".
            # For training games, there's a <div> starting with the number
            my $gameName = "";
            foreach my $a (xmlIndirectChildren('a', xmlMergeContent(@rows))) {
                if (exists($a->{href}) && $a->{href} =~ m#/games/(\d+)#) {
                    print "WARNING: game '$gameNr' links to '$1'\n" if $1 ne $gameNr;
                    $gameName = xmlTextContent(@{$a->{CONTENT}});
                }
            }
            if ($gameName eq '') {
                foreach my $div (xmlIndirectChildren('div', xmlMergeContent(@rows))) {
                    my $text = xmlTextContent(@{$div->{CONTENT}});
                    if ($text =~ /^$gameNr:/) {
                        $gameName = $text;
                    }
                }
            }
            $gameName =~ s/^$gameNr:\s+//;

            # Print
            print "Game      Name                                      Race  Category\n" if $needHeader;
            print "--------  ----------------------------------------  ----  --------------------\n" if $needHeader;
            printf "%8d  %-40s  %4d  %s\n", $gameNr, $gameName, $race, $type;
            $needHeader = 0;
        }
    } else {
        print "++ Unable to obtain game list ++\n";
    }
}


######################################################################
#
#  VCR file
#
######################################################################

sub doWriteVcr {
    # Read state
    my $body = readFile("c2rst.txt");
    print "Parsing result...\n";
    doVcr(jsonParse($body));
}

sub doVcr {
    # Fetch parameter
    my $parsedReply = shift;
    stateCheckReply($parsedReply);

    # Make spec files
    makeAllSpecFiles($parsedReply);

    # Make result
    my $player = $parsedReply->{rst}{player}{id};
    my $vcrs = rstPackVcrs($parsedReply, $player);
    my $fn = "vcr$player.dat";
    open VCR, "> $fn" or die "$fn: $!\n";
    print "Making $fn...\n";
    binmode VCR;
    print VCR $vcrs;
    close VCR;
    if (length($vcrs) < 100) {
        print "++ You do not have any VCRs this turn. ++\n";
    }
}


######################################################################
#
#  Result file
#
######################################################################

sub doDownloadResult {
    my $gameId;
    if (@ARGV == 0) {
        $gameId = stateGet('gameid');
        if (!$gameId) {
            die "rst1: need one parameter: game name\n";
        }
    } elsif (@ARGV == 1) {
        $gameId = shift @ARGV;
    } else {
        die "rst1: need one parameter: game name\n";
    }
    stateSet('gameid', $gameId);

    my $reply = httpCall("POST /_ui/plugins?method=LoadGameData&type=get&assembly=PlanetsNu.dll&object=PlanetsNu.GameFunctions HTTP/1.0\n",
                         httpBuildQuery(gameId => $gameId));

    print "Saving output...\n";
    open OUT, "> c2rst.txt" or die "c2rst.txt: $!\n";
    print OUT $reply->{BODY};
    close OUT;

    print "Parsing result...\n";
    my $parsedReply = jsonParse($reply->{BODY});
    if (!exists $parsedReply->{rst}) {
        print STDERR "WARNING: request probably did not succeed.\n";
        if (exists $parsedReply->{error}) {
            print STDERR "WARNING: error message is:\n\t", $parsedReply->{error}, "\n";
        }
    } else {
        if (stateGet('backups')) {
            print "Making backup...\n";
            my $turn = $parsedReply->{rst}{settings}{turn};
            my $player = $parsedReply->{rst}{player}{raceid};
            open OUT, sprintf("> c2rst_backup_%d_%03d.txt", $player, $turn);
            print OUT $reply->{BODY};
            close OUT;
        }
    }
}

sub doWriteResult {
    # Read state
    my $body = readFile("c2rst.txt");
    print "Parsing result...\n";
    doResult(jsonParse($body));
}

sub doResult {
    # Fetch parameter
    my $parsedReply = shift;
    stateCheckReply($parsedReply);

    # Timestamp
    my $timestamp = rstMakeTimeStamp($parsedReply);

    # Specs
    makeAllSpecFiles($parsedReply);

    # Make result
    makeResult($parsedReply, $parsedReply->{rst}{player}{id}, $timestamp);

    # Make util.dat with assorted info
    makeUtilData($parsedReply, $parsedReply->{rst}{player}{id}, $timestamp);
}

# Make all specification files
sub makeAllSpecFiles {
    my $parsedReply = shift;

    # Simple spec files
    makeSpecFile($parsedReply->{rst}{beams}, "beamspec.dat", 10, "A20v8", 36,
                 qw(name cost tritanium duranium molybdenum mass techlevel crewkill damage));
    makeSpecFile($parsedReply->{rst}{torpedos}, "torpspec.dat", 10, "A20v9", 38,
                 qw(name torpedocost launchercost tritanium duranium molybdenum mass techlevel crewkill damage));
    makeSpecFile($parsedReply->{rst}{engines}, "engspec.dat", 9, "A20v5V9", 66,
                 qw(name cost tritanium duranium molybdenum techlevel warp1 warp2 warp3 warp4 warp5 warp6 warp7 warp8 warp9));
    makeSpecFile($parsedReply->{rst}{hulls}, "hullspec.dat", 105, "A30v15", 60,
                 qw(name zzimage zzunused tritanium duranium molybdenum fueltank
                    crew engines mass techlevel cargo fighterbays launchers beams cost));
    makeSpecFile($parsedReply->{rst}{planets}, "xyplan.dat", 500, "v3", 6,
                 qw(x y ownerid));
    makeSpecFile($parsedReply->{rst}{planets}, "planet.nm", 500, "A20", 20,
                 qw(name));

    # Make more spec files
    makeHullfuncFile($parsedReply->{rst}{hulls});
    makeTruehullFile($parsedReply->{rst}{racehulls}, $parsedReply->{rst}{player}{raceid});
}

# Make specification file from data received within nu RST
sub makeSpecFile {
    my $replyPart = shift;
    my $fileName = shift;
    my $numEntries = shift;
    my $packPattern = shift;
    my $entrySize = shift;
    my @fields = @_;

    print "Making $fileName...\n";

    # Build field-to-slot mapping and entry template
    my %fieldToSlot;
    my @entryTemplate;
    foreach (0 .. $#fields) {
        $fieldToSlot{$fields[$_]} = $_;
        push @entryTemplate, 0;
    }

    # Load existing file or build empty file
    my @file;
    if ($fileName eq 'xyplan.dat') {
        # do NOT create xyplan.dat from original, it is expected to have holes!
        foreach (1 .. $numEntries) {
            push @file, [0,0,0];
        }
    } elsif (open(FILE, "< $fileName") || open(FILE, "< $opt_rootDir/$fileName")) {
        binmode FILE;
        foreach (1 .. $numEntries) {
            my $buf;
            read FILE, $buf, $entrySize;
            push @file, [unpack $packPattern, $buf];
        }
        close FILE;
    } else {
        if ($fileName eq 'hullspec.dat') {
            print "WARNING: 'hullspec.dat' created from scratch; it will not contain image references.\n";
            print "    Copy a pre-existing 'hullspec.dat' into this directory and process the RST again\n";
            print "    to have images.\n";
        }
        foreach (1 .. $numEntries) {
            if (exists $fieldToSlot{name}) { $entryTemplate[$fieldToSlot{name}] = "#$_"; }
            push @file, [@entryTemplate];
        }
    }

    # Populate file
    foreach my $e (@$replyPart) {
        if ($e->{id} > 0 && $e->{id} <= $numEntries) {
            foreach (sort keys %$e) {
                if (exists $fieldToSlot{$_}) {
                    $file[$e->{id} - 1][$fieldToSlot{$_}] = $e->{$_};
                }
            }
        }
    }

    # Generate it
    open FILE, "> $fileName" or die "$fileName: $!\n";
    binmode FILE;
    foreach (@file) {
        print FILE pack($packPattern, @$_);
    }
    close FILE;
}

sub makeHullfuncFile {
    # Nu stores cloakiness in its spec file, but all other hull
    # functions appear as free-form text only. We therefore assume
    # the hull functions to be reasonably default, and generate
    # a hullfunc file which only updates the Cloak ability.
    # FIXME: what about AdvancedCloak?
    my $hulls = shift;
    print "Making hullfunc.txt...\n";
    open FILE, "> hullfunc.txt" or die "hullfunc.txt: $!\n";
    print FILE "# Hull function definitions for 'nu' game\n\n";
    print FILE "\%hullfunc\n\n";
    print FILE "Init = Default\n";
    print FILE "Function = Cloak\n";
    print FILE "Hull = *\n";
    print FILE "RacesAllowed = -\n";
    foreach (@$hulls) {
        if ($_->{cancloak}) {
            print FILE "Hull = ", $_->{id}, "\n";
            print FILE "RacesAllowed = +\n";
        }
    }
    close FILE;
}

sub makeTruehullFile {
    my $pRacehulls = shift;
    my $player = shift;

    print "Making truehull.dat...\n";

    # Load existing file if any
    my @truehull = replicate(20*11, 0);
    if (open(TH, "< truehull.dat") or open(TH, "< $opt_rootDir/truehull.dat")) {
        my $th;
        binmode TH;
        read TH, $th, 20*11*2;
        close TH;
        @truehull = unpack("v*", $th);
    }

    # Merge race hulls
    for (my $i = 0; $i < 20; ++$i) {
        $truehull[($player-1)*20 + $i] = ($i < @$pRacehulls ? $pRacehulls->[$i] : 0);
    }

    # Write
    open(TH, "> truehull.dat") or die "truehull.dat: $!\n";
    binmode TH;
    print TH pack("v*", @truehull);
    close TH;
}

sub makeResult {
    my $parsedReply = shift;
    my $player = shift;
    my $timestamp = shift;
    my $race = rstMapOwnerToRace($parsedReply, $player);
    my $fileName = "player$race.rst";
    print "Making $fileName...\n";

    # Create result file with stub header
    # Sections are:
    #   ships
    #   targets
    #   planets
    #   bases
    #   messages
    #   shipxy
    #   gen
    #   vcr
    #   kore
    #   skore
    my @offsets = replicate(10, 0);
    open RST, "> $fileName" or die "$fileName: $!\n";
    binmode RST;
    rstWriteHeader(@offsets);

    # Make file sections
    my $ships = rstPackShips($parsedReply, $player);
    $offsets[0] = tell(RST)+1;
    print RST $ships;

    my $targets = rstPackTargets($parsedReply, $player);
    $offsets[1] = tell(RST)+1;
    print RST $targets;

    my $planets = rstPackPlanets($parsedReply, $player);
    $offsets[2] = tell(RST)+1;
    print RST $planets;

    my $bases = rstPackBases($parsedReply, $player);
    $offsets[3] = tell(RST)+1;
    print RST $bases;

    my @msgs = (rstPackMessages($parsedReply, $player),
                rstSynthesizeMessages($parsedReply, $player));
    $offsets[4] = tell(RST)+1;
    rstWriteMessages(@msgs);

    my $shipxy = rstPackShipXY($parsedReply, $player);
    $offsets[5] = tell(RST)+1;
    print RST $shipxy;

    my $gen = rstPackGen($parsedReply, $player, $ships, $planets, $bases, $timestamp);
    $offsets[6] = tell(RST)+1;
    print RST $gen;

    my $vcrs = rstPackVcrs($parsedReply, $player);
    $offsets[7] = tell(RST)+1;
    print RST $vcrs;

    # Finish
    rstWriteHeader(@offsets);
    close RST;

    my $trn = "player$race.trn";
    if (unlink($trn)) {
        print "Removed $trn.\n";
    }
}

sub makeUtilData {
    my $parsedReply = shift;
    my $player = shift;
    my $timestamp = shift;
    my $race = rstMapOwnerToRace($parsedReply, $player);
    my $fileName = "util$race.dat";
    print "Making $fileName...\n";

    open UTIL, "> $fileName" or die "$fileName: $!\n";
    binmode UTIL;
    utilWrite(13,
              $timestamp . pack("vvCCV8A32",
                                $parsedReply->{rst}{settings}{turn},
                                $race,
                                3, 0,       # claim to be Host 3.0
                                0, 0, 0, 0, 0, 0, 0, 0,  # digests not filled in
                                $parsedReply->{rst}{settings}{name}));

    # Scores
    utilMakeScore($parsedReply, "militaryscore",  1000, "Military Score (Nu)");
    utilMakeScore($parsedReply, "inventoryscore", 1001, "Inventory Score (Nu)");
    utilMakeScore($parsedReply, "prioritypoints",    2, "Build Points (Nu)");

    # Ion storms (FIXME: should place them in RST)
    foreach (@{$parsedReply->{rst}{ionstorms}}) {
        utilWrite(17, pack("v9",
                           $_->{id},
                           $_->{x},
                           $_->{y},
                           $_->{voltage},
                           $_->{heading},
                           $_->{warp},
                           $_->{radius},
                           int(($_->{voltage} + 49)/50),
                           $_->{isgrowing}));
    }

    # Minefields
    foreach (@{$parsedReply->{rst}{minefields}}) {
        # Only current fields. Old fields are managed by PCC.
        if ($_->{infoturn} == $parsedReply->{rst}{settings}{turn}) {
            # ignored fields: friendlycode, radius
            utilWrite(0, pack("vvvvVv",
                              $_->{id},
                              $_->{x},
                              $_->{y},
                              rstMapOwnerToRace($parsedReply, $_->{ownerid}),
                              $_->{units},
                              $_->{isweb} ? 1 : 0));
        }
    }

    # Allied bases
    foreach my $base (@{$parsedReply->{rst}{starbases}}) {
        # Since we're getting allied bases as well, we must filter here
        my $baseOwner = rstGetBaseOwner($base, $parsedReply);
        if ($baseOwner != 0 && $baseOwner != $player) {
            utilWrite(11, pack("vv", $base->{planetid}, rstMapOwnerToRace($parsedReply, $baseOwner)));
        }
    }

    # TODO: explosions. Problem is that PCC2 cannot yet display those.
    # TODO: enemy planet scans


    # Drop mines
    if (stateGet('dropmines')) {
        makeDropMines($parsedReply, $player);
    }

    close UTIL;
}

sub makeDropMines {
    my $parsedReply = shift;
    my $player = shift;
    my %knownMines;
    my $ndelete = 0;

    # Generate list of known mines
    foreach (@{$parsedReply->{rst}{minefields}}) {
        $knownMines{$_->{id}} = 1;
    }

    # Open chart DB
    my $cdb = "chart$player.cc";
    if (!open(DB, "< $cdb")) { return }

    # Read header
    my $header;
    if (read(DB, $header, 16) != 16) { die "$cdb: too short" }
    my ($magic, $turn, $pos, $pprop, $sprop) = unpack "A8vvvv", $header;
    seek DB, $pos, 0;

    # Read blocks
    while (read(DB, $header, 6)) {
        my ($type, $size) = unpack "vV", $header;
        if ($size > 1000000) {
            print "ERROR: unable to parse chart database, impossible block size ($size)\n";
            last;
        }
        my $data;
        read DB, $data, $size;
        if ($type == 4) {
            # Minefields. 16 bytes per block.
            for (my $pos = 0; $pos + 16 <= length($data); $pos += 16) {
                my $id = unpack "v", substr($data, $pos, 2);
                if (!exists($knownMines{$id})) {
                    # This field is known to PCC, but not to Nu, not even as an old one,
                    # so delete it. It must have nonzero coordinates to be accepted by
                    # PCC, and zero units to be recognized as a deletion.
                    utilWrite(0, pack("vvvvVv", $id, 1, 1, 1, 0, 0));
                    ++$ndelete;
                }
            }
        }
    }
    print "Wrote $ndelete minefield deletions.\n" if $ndelete;

    close DB;
}


######################################################################
#
#  Unpack
#
######################################################################

sub doUnpack {
    # Read state
    my $body = readFile("c2rst.txt");
    print "Parsing result...\n";
    my $parsedReply = jsonParse($body);
    stateCheckReply($parsedReply);

    # Timestamp
    my $timestamp = rstMakeTimeStamp($parsedReply);

    # Specs
    makeAllSpecFiles($parsedReply);

    # Prepare
    my $player = $parsedReply->{rst}{player}{id};
    my $race = rstMapOwnerToRace($parsedReply, $player);
    my $disSig = ' 'x10;
    my $datSig = "!\"#\$%&'()*";
    my $pControl = [replicate(2499, 0)];

    # Flow tracking: for each coordinate:
    #   tritaniumUsed, duraniumUsed, molybdenumUsed, cashUsed, suppliesUsed:
    #       Resources used for building. Units that build add to these values.
    #       Units that store these resources have this value added to their
    #       old value.
    #   torpXBuilt, fightersBuilt, cashMade:
    #       Units built. Builders add to these values. Units that store these,
    #       have this value removed from their old value.
    my $pAdjust = {};

    # Bases
    my ($bdat, $bdis) = unpPackBases($parsedReply, $player, $pControl, $pAdjust);
    unpWriteFile("bdata$race.dat", $bdat, $datSig);
    unpWriteFile("bdata$race.dis", $bdis, $disSig);

    # Planets
    my ($pdat, $pdis) = unpPackPlanets($parsedReply, $player, $pControl, $pAdjust);
    unpWriteFile("pdata$race.dat", $pdat, $datSig);
    unpWriteFile("pdata$race.dis", $pdis, $disSig);

    # Ships
    my ($sdat, $sdis) = unpPackShips($parsedReply, $player, $pControl, $pAdjust);
    unpWriteFile("ship$race.dat", $sdat, $datSig);
    unpWriteFile("ship$race.dis", $sdis, $disSig);

    # Simple files
    unpWriteFile("target$race.dat", rstPackTargets($parsedReply, $player), $datSig);
    unpWriteFile("vcr$race.dat",    rstPackVcrs($parsedReply, $player), $datSig);
    unpWriteFile("shipxy$race.dat", rstPackShipXY($parsedReply, $player), $datSig);

    # Messages
    my @msgs = (rstPackMessages($parsedReply, $player),
                rstSynthesizeMessages($parsedReply, $player));
    unpWriteMessages("mdata$race.dat", @msgs);

    # FIXME: save outgoing messages
    unpWriteFile("mess$race.dat", "\0\0");

    # GEN
    unpWriteFile("gen$race.dat", unpPackGen($parsedReply, $player,
                                            $sdat.$datSig.$sdis.$disSig,
                                            $pdat.$datSig.$pdis.$disSig,
                                            $bdat.$datSig.$bdis.$disSig,
                                            $timestamp));

    # Control
    unpWriteFile("contrl$race.dat", pack("V*", @$pControl));

    # Remove files we don't create
    foreach ("control.dat", "kore$race.dat", "skore$race.dat", "mess35$race.dat") {
        if (unlink($_)) {
            print "Removed $_.\n";
        }
    }

    # Update indexes
    unpUpdateIndex($race);

    # Make util.dat with assorted info
    makeUtilData($parsedReply, $parsedReply->{rst}{player}{id}, $timestamp);

    # Log failed flows
    unpLogFailedFlows($pAdjust);
}

# Write a single file
sub unpWriteFile {
    my $fname = shift;
    print "Making $fname...\n";
    open OUT, "> $fname" or die "$fname: $!\n";
    binmode OUT;
    print OUT @_;
    close OUT;
}

# Write messages
sub unpWriteMessages {
    my $fname = shift;
    my $nmessages = @_;

    # Create file
    print "Making $fname...\n";
    open OUT, "> $fname" or die "$fname: $!\n";
    binmode OUT;

    # Write preliminary header
    print OUT 'x' x (($nmessages * 6) + 2);

    # Write messages, generating header
    my $header = pack('v', $nmessages);
    foreach (@_) {
        $header .= pack('Vv', tell(OUT)+1, length($_));
        print OUT $_;
    }

    # Update header
    seek OUT, 0, 0;
    print OUT $header;
    close OUT;
}

sub unpPackGen {
    my $parsedReply = shift;
    my $player = shift;
    my $ships = shift;
    my $planets = shift;
    my $bases = shift;
    my $timestamp = shift;

    # Find turn number
    my $turn = $parsedReply->{rst}{settings}{turn};

    # Find scores
    my @scores = replicate(44, 0);
    foreach my $p (@{$parsedReply->{rst}{scores}}) {
        if ($p->{ownerid} > 0 && $p->{ownerid} <= 11 && $p->{turn} == $turn) {
            my $pos = ((rstMapOwnerToRace($parsedReply, $p->{ownerid}) - 1) * 4);
            $scores[$pos] = $p->{planets};
            $scores[$pos+1] = $p->{capitalships};
            $scores[$pos+2] = $p->{freighters};
            $scores[$pos+3] = $p->{starbases};
        }
    }

    return $timestamp
      . pack("v*", @scores)
        . pack("v", rstMapOwnerToRace($parsedReply, $player))
          . "NOPASSWORD          "
            . '?'
              . pack("V*",
                     rstChecksum($ships),
                     rstChecksum($planets),
                     rstChecksum($bases))
                . "\0\0          "
                  . pack("v", $turn)
                    . pack("v", rstChecksum($timestamp));
}

# Update init.tmp
sub unpUpdateIndex {
    my $race = shift;

    # Read
    my @index;
    if (open(TMP, "< init.tmp")) {
        my $txt;
        binmode TMP;
        read TMP, $txt, 22;
        @index = unpack "v*", $txt;
        close TMP;
    }

    # Update
    while (@index < 11) { push @index, 0 }
    $index[$race-1] = 1;
    unpWriteFile("init.tmp", pack("v*", @index));
}

sub unpPackBases {
    my ($parsedReply, $player, $pControl, $pAdjust) = @_;

    my @dat;
    my @dis;
    my @myHulls = @{$parsedReply->{rst}{racehulls}};
    while (@myHulls < 20) { push @myHulls, 0 }

    foreach my $base (@{$parsedReply->{rst}{starbases}}) {
        # Since we're getting allied bases as well, we must filter here
        next if rstGetBaseOwner($base, $parsedReply) != $player;

        # Flow tracking
        my $planet = asearch($parsedReply->{rst}{planets}, 'id', $base->{planetid}, { x=>0, y=>0 });
        my $adjkey = $planet->{x} . "," . $planet->{y};

        # Id, Owner
        my $dat = pack("v2", $base->{planetid}, rstMapOwnerToRace($parsedReply, $player));
        my $dis = $dat;

        # Defense
        $dat .= pack("v", $base->{defense});
        $dis .= pack("v", $base->{defense} - $base->{builtdefense});
        $pAdjust->{$adjkey}{cashUsed} += 10*$base->{builtdefense};
        $pAdjust->{$adjkey}{duraniumUsed} += $base->{builtdefense};

        # Damage
        $dat .= pack("v", $base->{damage});
        $dis .= pack("v", $base->{damage});

        # Tech
        foreach(qw(engine hull beam torp)) {
            my $new = $base->{$_."techlevel"};
            my $old = $base->{$_."techlevel"} - $base->{$_."techup"};
            $dat .= pack("v", $new);
            $dis .= pack("v", $old);
            $pAdjust->{$adjkey}{cashUsed} += 50*$new*($new-1) - 50*$old*($old-1);
        }

        # Engines
        foreach (1 .. 9) {
            my $stock = unpFindStock($base->{id}, $parsedReply, 2, $_);
            my $engine = asearch($parsedReply->{rst}{engines}, "id", $_);
            $dat .= pack("v", $stock->{amount});
            $dis .= pack("v", $stock->{amount} - $stock->{builtamount});
            unpAddCost($pAdjust, $adjkey, $stock->{builtamount}, $engine, 'cost');
        }

        # Hulls
        foreach (@myHulls) {
            if ($_) {
                my $stock = unpFindStock($base->{id}, $parsedReply, 1, $_);
                my $hull = asearch($parsedReply->{rst}{hulls}, "id", $_);
                $dat .= pack("v", $stock->{amount});
                $dis .= pack("v", $stock->{amount} - $stock->{builtamount});
                unpAddCost($pAdjust, $adjkey, $stock->{builtamount}, $hull, 'cost');
            } else {
                $dat .= "\0\0";
                $dis .= "\0\0";
            }
        }

        # Beams
        foreach (1 .. 10) {
            my $stock = unpFindStock($base->{id}, $parsedReply, 3, $_);
            my $beam = asearch($parsedReply->{rst}{beams}, "id", $_);
            $dat .= pack("v", $stock->{amount});
            $dis .= pack("v", $stock->{amount} - $stock->{builtamount});
            unpAddCost($pAdjust, $adjkey, $stock->{builtamount}, $beam, 'cost');
        }

        # Launchers
        foreach (1 .. 10) {
            my $stock = unpFindStock($base->{id}, $parsedReply, 4, $_);
            my $tube = asearch($parsedReply->{rst}{torpedos}, "id", $_);
            $dat .= pack("v", $stock->{amount});
            $dis .= pack("v", $stock->{amount} - $stock->{builtamount});
            unpAddCost($pAdjust, $adjkey, $stock->{builtamount}, $tube, 'launchercost');
        }

        # Torps
        foreach (1 .. 10) {
            my $stock = unpFindStock($base->{id}, $parsedReply, 5, $_);
            my $tube = asearch($parsedReply->{rst}{torpedos}, "id", $_);
            my $new = $stock->{amount};
            my $old = $stock->{amount} - $stock->{builtamount};
            unpAdjustProduce(\$old, $pAdjust, $adjkey, "torp".$_."Built");
            $dat .= pack("v", $new);
            $dis .= pack("v", $old);
            $pAdjust->{$adjkey}{cashUsed} += $stock->{builtamount} * $tube->{torpedocost};
            $pAdjust->{$adjkey}{tritaniumUsed} += $stock->{builtamount};
            $pAdjust->{$adjkey}{duraniumUsed} += $stock->{builtamount};
            $pAdjust->{$adjkey}{molybdenumUsed} += $stock->{builtamount};
        }

        # Fighters
        {
            my $new = $base->{fighters};
            my $old = $base->{fighters} - $base->{builtfighters};
            unpAdjustProduce(\$old, $pAdjust, $adjkey, "fightersBuilt");
            $dat .= pack("v", $new);
            $dis .= pack("v", $old);
            $pAdjust->{$adjkey}{cashUsed} += $base->{builtfighters} * 100;
            $pAdjust->{$adjkey}{tritaniumUsed} += $base->{builtfighters} * 3;
            $pAdjust->{$adjkey}{molybdenumUsed} += $base->{builtfighters} * 2;
        }

        # Missions
        $dat .= pack("v3", $base->{targetshipid}, $base->{shipmission}, $base->{mission});
        $dis .= pack("v3", 0,                     0,                    $base->{mission});

        # Build order
        my $buildSlot = 0;
        if ($base->{isbuilding}) {
            for (0 .. $#myHulls) {
                if ($base->{buildhullid} == $myHulls[$_]) {
                    $buildSlot = $_+1;
                    last;
                }
            }
            if (!$buildSlot) {
                print STDERR "WARNING: base $base->{planetid} is building a ship that you cannot build\n";
            }
        }
        $dat .= pack("v7", $buildSlot, $base->{buildengineid}, $base->{buildbeamid}, $base->{buildbeamcount},
                     $base->{buildtorpedoid}, $base->{buildtorpcount}, 0);
        $dis .= pack("v7", 0, 0, 0, 0, 0, 0, 0);

        # Remember
        push @dat, $dat;
        push @dis, $dis;
        $pControl->[$base->{planetid} + 999] = rstChecksum($dat);
    }

    (pack("v", scalar(@dat)) . join('', @dat),
     pack("v", scalar(@dis)) . join('', @dis));
}

sub unpPackPlanets {
    my ($parsedReply, $player, $pControl, $pAdjust) = @_;

    my @dat;
    my @dis;

    # This field list is dually-used for packing and filtering.
    # A planet is included in the result if it has at least one
    # of those fields with a sensible value.
    my @fields = qw(mines factories defense
                    neutronium tritanium duranium molybdenum
                    clans supplies megacredits
                    groundneutronium groundtritanium groundduranium groundmolybdenum
                    densityneutronium densitytritanium densityduranium densitymolybdenum
                    colonisttaxrate nativetaxrate
                    colonisthappypoints nativehappypoints
                    nativegovernment
                    nativeclans
                    nativetype);
    my @structCosts = (4, 3, 10);
    foreach my $planet (@{$parsedReply->{rst}{planets}}) {
        if ($planet->{friendlycode} ne '???' || grep {$planet->{$_} > 0} @fields) {
            # Flow tracking
            my $adjkey = $planet->{x} . "," . $planet->{y};

            # Id, owner
            my $dat = pack("vvA3",
                           rstMapOwnerToRace($parsedReply, $planet->{ownerid}),
                           $planet->{id},
                           $planet->{friendlycode});
            my $dis = $dat;

            if ($planet->{ownerid} == $player) {
                # Track base building
                if ($planet->{buildingstarbase}) {
                    $pAdjust->{$adjkey}{cashUsed} += 900;
                    $pAdjust->{$adjkey}{tritaniumUsed} += 402;
                    $pAdjust->{$adjkey}{duraniumUsed} += 120;
                    $pAdjust->{$adjkey}{molybdenumUsed} += 340;
                }

                # Structures
                foreach (0 .. 2) {
                    my $built = $planet->{"built".$fields[$_]};
                    my $new = $planet->{$fields[$_]};
                    my $old = $new - $built;
                    $dat .= pack("v", $new);
                    $dis .= pack("v", $old);
                    $pAdjust->{$adjkey}{suppliesUsed} += $built;
                    $pAdjust->{$adjkey}{cashUsed} += $structCosts[$_] * $built;
                }

                # Minerals
                foreach (qw(neutronium tritanium duranium molybdenum)) {
                    my $new = $planet->{$_};
                    my $old = unpAdjustUse($new, $pAdjust, $adjkey, $_."Used");
                    $dat .= pack("V", $new);
                    $dis .= pack("V", $old);
                }

                # Clans
                $dat .= pack("V", $planet->{clans});
                $dis .= pack("V", $planet->{clans});

                # Supplies and MC
                my $newMC = $planet->{megacredits};
                my $oldMC = $planet->{megacredits} - $planet->{suppliessold};
                my $newSup = $planet->{supplies};
                my $oldSup = $planet->{supplies} + $planet->{suppliessold};

                $oldSup = unpAdjustUse($oldSup, $pAdjust, $adjkey, "suppliesUsed");
                $oldMC  = unpAdjustUse($oldMC,  $pAdjust, $adjkey, "cashUsed");

                if ($oldMC < 0) {
                    $pAdjust->{$adjkey}{cashMade} -= $oldMC;
                    $oldMC = 0;
                }

                $dat .= pack("VV", $newSup, $newMC);
                $dis .= pack("VV", $oldSup, $oldMC);
            } else {
                my $v = rstPackFields($planet, "v3V7", qw(mines factories defense
                                                          neutronium tritanium duranium molybdenum
                                                          clans supplies megacredits));
                $dat .= $v;
                $dis .= $v;
            }

            # Ground, Natives, Taxes
            my $env = rstPackFields($planet, "V4v9Vv",
                                    qw(groundneutronium groundtritanium groundduranium groundmolybdenum
                                       densityneutronium densitytritanium densityduranium densitymolybdenum
                                       colonisttaxrate nativetaxrate
                                       colonisthappypoints nativehappypoints
                                       nativegovernment
                                       nativeclans
                                       nativetype));
            $env .= pack("v", $planet->{temp} >= 0 ? 100 - $planet->{temp} : -1);
            $env .= pack("v", $planet->{buildingstarbase});
            $dat .= $env;
            $dis .= $env;

            push @dat, $dat;
            push @dis, $dis;

            $pControl->[$planet->{id} + 499] = rstChecksum($dat);
        }
    }

    (pack("v", scalar(@dat)) . join('', @dat),
     pack("v", scalar(@dis)) . join('', @dis));
}

sub unpPackShips {
    my ($parsedReply, $player, $pControl, $pAdjust) = @_;

    my @dat;
    my @dis;

    foreach my $ship (@{$parsedReply->{rst}{ships}}) {
        if ($ship->{ownerid} == $player) {
            # Flow tracking
            my $adjkey = $ship->{x} . "," . $ship->{y};

            # Id, owner, fcode, warp, location, most specs
            my $dat = rstPackFields($ship, "v", qw(id));
            $dat .= pack("v", rstMapOwnerToRace($parsedReply, $ship->{ownerid}));
            $dat .= rstPackFields($ship,
                                  "A3v",
                                  qw(friendlycode warp));
            $dat .= pack("vv",
                         $ship->{targetx} - $ship->{x},
                         $ship->{targety} - $ship->{y});
            $dat .= rstPackFields($ship,
                                  "v8",
                                  qw(x y engineid hullid beamid beams bays torpedoid));
            my $dis = $dat;

            # Ammo
            my $newAmmo = $ship->{ammo};
            my $oldAmmo = $newAmmo;
            if ($ship->{torps} > 0) {
                $oldAmmo = unpAdjustConsume($oldAmmo, $pAdjust, $adjkey, "torp".$ship->{torpedoid}."Built");
            }
            if ($ship->{bays} > 0) {
                $oldAmmo = unpAdjustConsume($oldAmmo, $pAdjust, $adjkey, "fightersBuilt");
            }
            $dat .= pack("v", $newAmmo);
            $dis .= pack("v", $oldAmmo);

            # Torp launcher count
            $dat .= pack("v", $ship->{torps});
            $dis .= pack("v", $ship->{torps});

            # Mission
            my $msn;
            if ($ship->{mission} >= 0) {
                # Missions are off-by-one!
                $msn = pack("v", $ship->{mission} + 1);
            } else {
                $msn = pack("v", $ship->{mission});
            }
            $msn .= pack("v", rstMapOwnerToRace($parsedReply, $ship->{enemy}));
            $msn .= pack("v", $ship->{mission} == 6 ? $ship->{mission1target} : 0);
            $dat .= $msn;
            $dis .= $msn;

            # Damage, Crew, Clans, Name
            $dat .= rstPackFields($ship, "v3A20", qw(damage crew clans name));
            $dis .= rstPackFields($ship, "v3A20", qw(damage crew clans name));

            # Minerals
            foreach (qw(neutronium tritanium duranium molybdenum supplies)) {
                my $new = $ship->{$_};
                my $old = unpAdjustUse($new, $pAdjust, $adjkey, $_."Used");
                $dat .= pack("v", $new);
                $dis .= pack("v", $old);
            }

            # Transfers
            # FIXME: jettison?
            if ($ship->{transfertargettype} == 1) {
                # Unload
                $dat .= rstPackFields($ship,
                                      "v7",
                                      qw(transferneutronium transfertritanium
                                         transferduranium transfermolybdenum
                                         transferclans transfersupplies
                                         transfertargetid));
            } else {
                $dat .= "\0" x 14;
            }
            $dis .= "\0" x 14;
            if ($ship->{transfertargettype} == 2) {
                # Transfer
                $dat .= rstPackFields($ship,
                                      "v7",
                                      qw(transferneutronium transfertritanium
                                         transferduranium transfermolybdenum
                                         transferclans transfersupplies
                                         transfertargetid));
            } else {
                $dat .= "\0" x 14;
            }
            $dis .= "\0" x 14;

            if ($ship->{transfermegacredits} || $ship->{transferammo}) {
                print "WARNING: transfer of mc and/or ammo not implemented yet\n";
            }

            # Remainder of mission
            $msn = pack("v", $ship->{mission} == 7 ? $ship->{mission1target} : 0);
            $dat .= $msn;
            $dis .= $msn;

            # Cash
            my $newMC = $ship->{megacredits};
            my $oldMC = unpAdjustUse($newMC, $pAdjust, $adjkey, "cashUsed");
            $oldMC = unpAdjustConsume($oldMC, $pAdjust, $adjkey, "cashMade");

            $dat .= pack("v", $newMC);
            $dis .= pack("v", $oldMC);

            # Remember
            push @dat, $dat;
            push @dis, $dis;

            if ($ship->{id} <= 500) {
                $pControl->[$ship->{id} - 1] = rstChecksum($dat);
            } else {
                $pControl->[$ship->{id} + 1499] = rstChecksum($dat);
            }
        }
    }

    (pack("v", scalar(@dat)) . join('', @dat),
     pack("v", scalar(@dis)) . join('', @dis));
}

# Find a stock
sub unpFindStock {
    my $baseId = shift;
    my $parsedReply = shift;
    my $stockType = shift;
    my $stockId = shift;
    my $pStocks = $parsedReply->{rst}{stock};
    foreach (@$pStocks) {
        if ($_->{starbaseid} == $baseId && $_->{stocktype} == $stockType && $_->{stockid} == $stockId) {
            return $_;
        }
    }
    return {"amount"=>0, "builtamount"=>0};
}

sub unpAddCost {
    my $pAdjust = shift;
    my $adjkey = shift;
    my $built = shift;
    my $item = shift;
    my $costKey = shift;
    $pAdjust->{$adjkey}{cashUsed} += $built * $item->{$costKey};
    $pAdjust->{$adjkey}{tritaniumUsed} += $built * $item->{tritanium};
    $pAdjust->{$adjkey}{duraniumUsed} += $built * $item->{duranium};
    $pAdjust->{$adjkey}{molybdenumUsed} += $built * $item->{molybdenum};
}

sub unpAdjustProduce {
    my $pOld = shift;
    my $pAdjust = shift;
    my $adjkey = shift;
    my $item = shift;
    if ($$pOld < 0) {
        # Remember that we built something but cannot store that flow
        $pAdjust->{$adjkey}{$item} -= $$pOld;
        $$pOld = 0;
    }
}

sub unpAdjustConsume {
    my $new = shift;
    my $pAdjust = shift;
    my $adjkey = shift;
    my $item = shift;
    if (exists($pAdjust->{$adjkey}{$item})) {
        my $old = $new - $pAdjust->{$adjkey}{$item};
        if ($old < 0) {
            $pAdjust->{$adjkey}{$item} = -$old;
            return 0;
        } else {
            $pAdjust->{$adjkey}{$item} = 0;
            return $old;
        }
    } else {
        return $new;
    }
}

sub unpAdjustUse {
    my $new = shift;
    my $pAdjust = shift;
    my $adjkey = shift;
    my $item = shift;
    if (exists($pAdjust->{$adjkey}{$item})) {
        $new += $pAdjust->{$adjkey}{$item};
        $pAdjust->{$adjkey}{$item} = 0;
    }
    return $new;
}

sub unpLogFailedFlows {
    my $pAdjust = shift;
    my @log;
    foreach my $xy (sort keys %$pAdjust) {
        my $item = "Location $xy:\n";
        my $did = 0;
        foreach (sort keys %{$pAdjust->{$xy}}) {
            if ($pAdjust->{$xy}{$_}) {
                $item .= "  $_ = $pAdjust->{$xy}{$_}\n";
                $did = 1;
            }
        }
        push @log, "$item\n" if $did;
    }

    if (@log) {
        printf "WARNING: %d flows not resolved, see c2flow.txt.\n", scalar(@log);
        open LOG, "> c2flow.txt" or die "c2flow.txt: $!\n";
        print LOG @log;
        close LOG;
    } else {
        unlink "c2flow.txt";
    }
}

######################################################################
#
#  Run Host
#
######################################################################

sub doRunHost {
    # Initialized?
    if (stateGet('gameid') eq '') {
        die "ERROR: please download a game first to initialize the directory.\n";
    }

    # Mark turn done
    print "Marking turn done...\n";
    my $reply = httpCall("POST /_ui/plugins?method=SetTurnReady&type=get&assembly=PlanetsNu.dll&object=PlanetsNu.GameFunctions HTTP/1.0\n",
                         httpBuildQuery(gameId => stateGet('gameid'),
                                        playerId => stateGet('playerid'),
                                        ready => "true"));
    rhCheckFailure(jsonParse($reply->{BODY}));

    # Run host
    print "Running host...\n";
    $reply = httpCall("POST /_ui/plugins?method=HostGame&type=get&assembly=PlanetsNu.dll&object=PlanetsNu.GameFunctions HTTP/1.0\n",
                      httpBuildQuery(gameId => stateGet('gameid')));
    rhCheckFailure(jsonParse($reply->{BODY}));

    # Wait
    print "Waiting for host to complete...\n";
    while (1) {
        # 10 second interval, same as AJAX app
        sleep 5;
        $reply = httpCall("POST /_ui/plugins?method=CheckHostDone&type=get&assembly=PlanetsNu.dll&object=PlanetsNu.GameFunctions HTTP/1.0\n",
                          httpBuildQuery(gameId => stateGet('gameid')));
        last if $reply->{BODY} ne '{}';
        sleep 5;
    }
    rhCheckFailure(jsonParse($reply->{BODY}));
    print "++ Success ++\n";
}

sub rhCheckFailure {
    my $reply = shift;
    if (!(exists($reply->{success}) && $reply->{success} =~ /true/i)) {
        print "++ Failure ++\n";
        print "Server answer:\n";
        foreach (sort keys %$reply) {
            printf "%-20s %s\n", $_, $reply->{$_};
        }
        die "Aborted.\n";
    }
}

######################################################################
#
#  Dumping
#
######################################################################

sub doDump {
    # Read state
    my $body = readFile("c2rst.txt");
    jsonDump(\*STDOUT, jsonParse($body), "");
}

######################################################################
#
#  UTIL.DAT creation
#
######################################################################

sub utilWrite {
    my $type = shift;
    my $data = shift;
    print UTIL pack("vv", $type, length($data)), $data;
}

sub utilMakeScore {
    my ($parsedReply, $key, $utilId, $utilName) = @_;
    my @scores = replicate(11, -1);
    foreach (@{$parsedReply->{rst}{scores}}) {
        $scores[rstMapOwnerToRace($parsedReply, $_->{ownerid})-1] = $_->{$key};
    }
    utilWrite(51, pack("A50vvVV11", $utilName, $utilId, -1, -1, @scores));
}

######################################################################
#
#  RST creation
#
######################################################################

sub rstMakeTimeStamp {
    my $parsedReply = shift;

    # Find timestamp. It has the format
    #  8/12/2011 9:00:13 PM
    #  8/7/2011 1:33:42 PM
    my @time = split m|[/: ]+|, $parsedReply->{rst}{settings}{hoststart};
    if (@time != 7) {
        print "WARNING: unable to figure out a reliable timestamp\n";
        while (@time < 7) {
            push @time, 0;
        }
    } else {
        # Convert to international time format
        if ($time[3] == 12) { $time[3] = 0 }
        if ($time[4] eq 'PM') { $time[3] += 12 }
    }
    return substr(sprintf("%02d-%02d-%04d%02d:%02d:%02d", @time), 0, 18);
}

sub rstWriteHeader {
    my @offsets = @_;
    seek RST, 0, 0;
    print RST pack("V8", @offsets[0 .. 7]), "VER3.501", pack("V3", $offsets[8], 0, $offsets[9]);
}

# Create ship section. Returns whole section as a string.
sub rstPackShips {
    my $parsedReply = shift;
    my $player = shift;
    my @packedShips;
    foreach my $ship (@{$parsedReply->{rst}{ships}}) {
        if ($ship->{ownerid} == $player) {
            my $p = rstPackFields($ship, "v", qw(id));
            $p .= pack("v", rstMapOwnerToRace($parsedReply, $ship->{ownerid}));
            $p .= rstPackFields($ship,
                                "A3v",
                                qw(friendlycode warp));
            $p .= pack("vv",
                       $ship->{targetx} - $ship->{x},
                       $ship->{targety} - $ship->{y});
            $p .= rstPackFields($ship,
                                "v10",
                                qw(x y engineid hullid beamid beams bays torpedoid ammo torps));
            if ($ship->{mission} >= 0) {
                # Missions are off-by-one!
                $p .= pack("v", $ship->{mission} + 1);
            } else {
                $p .= pack("v", $ship->{mission});
            }
            $p .= pack("v", rstMapOwnerToRace($parsedReply, $ship->{enemy}));
            $p .= pack("v", $ship->{mission} == 6 ? $ship->{mission1target} : 0);
            $p .= rstPackFields($ship,
                                "v3A20v5",
                                qw(damage crew clans name
                                   neutronium tritanium duranium molybdenum supplies));

            # FIXME: jettison?
            if ($ship->{transfertargettype} == 1) {
                # Unload
                $p .= rstPackFields($ship,
                                    "v7",
                                    qw(transferneutronium transfertritanium
                                       transferduranium transfermolybdenum
                                       transferclans transfersupplies
                                       transfertargetid));
            } else {
                $p .= "\0" x 14;
            }
            if ($ship->{transfertargettype} == 2) {
                # Transfer
                $p .= rstPackFields($ship,
                                    "v7",
                                    qw(transferneutronium transfertritanium
                                       transferduranium transfermolybdenum
                                       transferclans transfersupplies
                                       transfertargetid));
            } else {
                $p .= "\0" x 14;
            }
            if ($ship->{transfermegacredits} || $ship->{transferammo}) {
                print "WARNING: transfer of mc and/or ammo not implemented yet\n";
            }
            $p .= pack("v", $ship->{mission} == 7 ? $ship->{mission1target} : 0);
            $p .= rstPackFields($ship,
                                "v",
                                qw(megacredits));
            push @packedShips, $p;
        }
    }

    pack("v", scalar(@packedShips)) . join('', @packedShips);
}

# Create target section.
sub rstPackTargets {
    my $parsedReply = shift;
    my $player = shift;
    my @packedShips;
    foreach my $ship (@{$parsedReply->{rst}{ships}}) {
        if ($ship->{ownerid} != $player) {
            push @packedShips,
              rstPackFields($ship, "v", qw(id))
                . pack("v", rstMapOwnerToRace($parsedReply, $ship->{ownerid}))
                  . rstPackFields($ship,
                                  "v5A20",
                                  qw(warp x y hullid heading name));
        }
    }
    pack("v", scalar(@packedShips)) . join('', @packedShips);
}

# Create planet section.
sub rstPackPlanets {
    my $parsedReply = shift;
    my $player = shift;
    my @packedPlanets;

    # This field list is dually-used for packing and filtering.
    # A planet is included in the result if it has at least one
    # of those fields with a sensible value.
    my @fields = qw(mines factories defense
                    neutronium tritanium duranium molybdenum
                    clans supplies megacredits
                    groundneutronium groundtritanium groundduranium groundmolybdenum
                    densityneutronium densitytritanium densityduranium densitymolybdenum
                    colonisttaxrate nativetaxrate
                    colonisthappypoints nativehappypoints
                    nativegovernment
                    nativeclans
                    nativetype);
    foreach my $planet (@{$parsedReply->{rst}{planets}}) {
        if ($planet->{friendlycode} ne '???'
            || grep {$planet->{$_} > 0} @fields) {
            # FIXME: mines/factories/defense are after building,
            # supplies are after supply sale,
            # so doing it this way disallows undo in a partial turn!
            my $p = pack("v", rstMapOwnerToRace($parsedReply, $planet->{ownerid}));
            $p .= rstPackFields($planet,
                                "vA3v3V11v9Vv",
                                qw(id friendlycode), @fields);
            $p .= pack("v", $planet->{temp} >= 0 ? 100 - $planet->{temp} : -1);
            $p .= pack("v", $planet->{buildingstarbase});
            push @packedPlanets, $p;
        }
    }
    pack("v", scalar(@packedPlanets)) . join('', @packedPlanets);
}

sub rstPackBases {
    my $parsedReply = shift;
    my $player = shift;
    my @packedBases;
    my @myHulls = @{$parsedReply->{rst}{racehulls}};
    while (@myHulls < 20) { push @myHulls, 0 }
    foreach my $base (@{$parsedReply->{rst}{starbases}}) {
        # Since we're getting allied bases as well, we must filter here
        next if rstGetBaseOwner($base, $parsedReply) != $player;

        my $b = pack("v2", $base->{planetid}, rstMapOwnerToRace($parsedReply, $player));
        $b .= rstPackFields($base,
                            "v6",
                            qw(defense damage enginetechlevel
                               hulltechlevel beamtechlevel torptechlevel));
        $b .= rstPackStock($base->{id}, $parsedReply, 2, sequence(1, 9));
        $b .= rstPackStock($base->{id}, $parsedReply, 1, @myHulls);
        $b .= rstPackStock($base->{id}, $parsedReply, 3, sequence(1, 10));
        $b .= rstPackStock($base->{id}, $parsedReply, 4, sequence(1, 10));
        $b .= rstPackStock($base->{id}, $parsedReply, 5, sequence(1, 10));
        $b .= rstPackFields($base,
                            "v4",
                            qw(fighters targetshipid shipmission mission));
        my $buildSlot = 0;
        if ($base->{isbuilding}) {
            for (0 .. $#myHulls) {
                if ($base->{buildhullid} == $myHulls[$_]) {
                    $buildSlot = $_+1;
                    last;
                }
            }
            if (!$buildSlot) {
                print STDERR "WARNING: base $base->{planetid} is building a ship that you cannot build\n";
            }
        }
        $b .= pack("v", $buildSlot);
        $b .= rstPackFields($base,
                            "v5",
                            qw(buildengineid buildbeamid buildbeamcount buildtorpedoid buildtorpcount));
        $b .= pack("v", 0);
        push @packedBases, $b;
    }
    pack("v", scalar(@packedBases)) . join('', @packedBases);
}

sub rstPackMessages {
    my $parsedReply = shift;
    my $player = shift;
    my $turn = $parsedReply->{rst}{settings}{turn};
    my @result;

    # I have not yet seen all of these.
    my @templates = (
                     "(-r0000)<<< Outbound >>>",            # xx 0 'Outbound', should not appear in inbox
                     "(-h0000)<<< System >>>",              # 1 'System',
                     "(-s%04d)<<< Terraforming >>>",        # 2 'Terraforming',
                     "(-l%04d)<<< Minefield Laid >>>",      # 3 'Minelaying',
                     "(-m%04d)<<< Mine Sweep >>>",          # 4 'Minesweeping',
                     "(-p%04d)<<< Planetside Message >>>",  # 5 'Colony',
                     "(-f%04d)<<< Combat >>>",              # xx 6 'Combat',
                     "(-f%04d)<<< Fleet Message >>>",       # xx 7 'Fleet',
                     "(-s%04d)<<< Ship Message >>>",        # 8 'Ship',
                     "(-n%04d)<<< Intercepted Message >>>", # xx 9 'Enemy Distress Call',
                     "(-x0000)<<< Explosion >>>",           # 10 'Explosion',
                     "(-d%04d)<<< Space Dock Message >>>",  # 11 'Starbase',
                     "(-w%04d)<<< Web Mines >>>",           # 12 'Web Mines',
                     "(-y%04d)<<< Meteor >>>",              # 13 'Meteors',
                     "(-z%04d)<<< Sensor Sweep >>>",        # 14 'Sensor Sweep',
                     "(-z%04d)<<< Bio Scan >>>",            # xx 15 'Bio Scan',
                     "(-e%04d)<<< Distress Call >>>",       # xx 16 'Distress Call',
                     "(-r%X000)<<< Subspace Message >>>",   # 17 'Player',
                     "(-h0000)<<< Diplomacy >>>",           # 18 'Diplomacy',
                     "(-m%04d)<<< Mine Scan >>>",           # 19 'Mine Scan',
                     "(-9%04d)<<< Captain's Log >>>",       # xx  20 'Dark Sense',
                     "(-9%04d)<<< Sub Space Message >>>",   # xx 21 'Hiss'
                );

    # Build message list
    # 'messages' is regular inbox
    # 'mymessages' is diplomacy messages and outbox since 23/Nov/2011.
    my @messages = @{$parsedReply->{rst}{messages}};
    if (exists $parsedReply->{rst}{mymessages}) {
        push @messages, @{$parsedReply->{rst}{mymessages}};
    }
    foreach my $m (sort {$b->{id} <=> $a->{id}} grep {$_->{turn} == $turn} @messages) {
        my $head = rstFormatMessage("From: $m->{headline}");
        my $body = rstFormatMessage($m->{body});
        my $template = ($m->{messagetype} >= 0 && $m->{messagetype} < @templates ? $templates[$m->{messagetype}] : "(-h0000)<<< Sub Space Message >>>");
        my $msg = sprintf($template, $m->{target}) . "\n\n" . $head . "\n\n" . $body;

        # Nu messages contain a coordinate. To let PCC know that, add it to
        # the message, unless it's already there.
        # Nu often uses '( 1234, 5678 )' for coordiantes. Strip the blanks to
        # make it look better.
        $msg =~ s/\( +(\d+, *\d+) +\)/($1)/g;
        if ($m->{x} && $m->{y} && $msg !~ m|\($m->{x}, *$m->{y}\)|) {
            $msg .= "\n\nLocation: ($m->{x}, $m->{y})";
        }
        push @result, rstEncryptMessage($msg);
    }

    @result;
}

sub rstSynthesizeMessages {
    my $parsedReply = shift;
    my $player = shift;
    my @result;

    # Settings I (from 'game')
    my $text = rstSynthesizeMessage("(-h0000)<<< Game Settings (1) >>>",
                                    $parsedReply->{rst}{game},
                                    [name=>"Game Name: %s"], [description=>"Description: %s"], "\n", [hostdays=>"Host Days: %s"],
                                    [hosttime=>"Host Time: %s"], "\n", [masterplanetid=>"Master Planet Id: %s"]);
    push @result, rstEncryptMessage($text) if defined($text);

    # Settings II (from 'settings')
    $text = rstSynthesizeMessage("(-h0000)<<< Game Settings (2) >>>",
                                 $parsedReply->{rst}{settings},
                                 [buildqueueplanetid => "Build Queue Planet: %s"],
                                 [turn               => "Turn %s"],
                                 [victorycountdown   => "Victory Countdown: %s"],
                                 "\n",
                                 [hoststart          => "Host started: %s"],
                                 [hostcompleted      => "Host completed: %s"]);
    push @result, rstEncryptMessage($text) if defined($text);

    # Host config (from 'settings')
    $text = rstSynthesizeMessage("(-g0000)<<< Host Configuration >>>",
                                 $parsedReply->{rst}{settings},
                                 [cloakfail          => "Odds of cloak failure  %s %%"],
                                 [maxions            => "Ion Storms             %s"],
                                 [shipscanrange      => "Ships are visible at   %s"],
                                 [structuredecayrate => "structure decay        %s"],
                                 "\n",
                                 [mapwidth           => "Map width              %s"],
                                 [mapheight          => "Map height             %s"],
                                 [maxallies          => "Maximum allies         %s"],
                                 [numplanets         => "Number of planets      %s"],
                                 [planetscanrange    => "Planets are visible at %s"]);
    push @result, rstEncryptMessage($text) if defined($text);

    # HConfig arrays
    foreach ([freefighters=>"Free fighters at starbases", "%3s"],
             [groundattack=>"Ground Attack Kill Ratio", "%3s : 1"],
             [grounddefense=>"Ground Defense Kill Ratio", "%3s : 1"],
             [miningrate=>"Mining rates", "%3s"],
             [taxrate=>"Tax rates", "%3s"])
      {
          my $key = $_->[0];
          my $fmt = $_->[2];
          my $did = 0;
          $text = "(-g0000)<<< Host Configuration >>>\n\n$_->[1]\n";
          foreach my $r (@{$parsedReply->{rst}{races}}) {
              if (exists($r->{$key}) && exists($r->{adjective}) && $r->{id} != 0) {
                  $text .= sprintf("  %-15s", $r->{adjective})
                    . sprintf($fmt, $r->{$key})
                      . "\n";
                  $did = 1;
              }
          }
          push @result, rstEncryptMessage($text) if $did;
      }

    @result;
}

sub rstSynthesizeMessage {
    my $head = shift;
    my $pHash = shift;
    my $text = "$head\n\n";
    my $did = 0;
    my $gap = 1;
    foreach (@_) {
        if (ref) {
            if (exists $pHash->{$_->[0]}) {
                $text .= sprintf($_->[1], $pHash->{$_->[0]}) . "\n";
                $did = 1;
                $gap = 0;
            }
        } else {
            $text .= $_ unless $gap;
            $gap = 1;
        }
    }
    return $did ? $text : undef;
}

sub rstPackShipXY {
    my $parsedReply = shift;
    my $player = shift;
    my @shipxy = replicate(999*4, 0);

    foreach my $ship (@{$parsedReply->{rst}{ships}}) {
        if ($ship->{id} > 0 && $ship->{id} <= 999) {
            my $pos = ($ship->{id} - 1) * 4;
            $shipxy[$pos]   = $ship->{x};
            $shipxy[$pos+1] = $ship->{y};
            $shipxy[$pos+2] = rstMapOwnerToRace($parsedReply, $ship->{ownerid});
            $shipxy[$pos+3] = $ship->{mass};
        }
    }

    pack("v*", @shipxy);
}

sub rstPackGen {
    my $parsedReply = shift;
    my $player = shift;
    my $ships = shift;
    my $planets = shift;
    my $bases = shift;
    my $timestamp = shift;

    # Find turn number
    my $turn = $parsedReply->{rst}{settings}{turn};

    # Find scores
    my @scores = replicate(44, 0);
    foreach my $p (@{$parsedReply->{rst}{scores}}) {
        if ($p->{ownerid} > 0 && $p->{ownerid} <= 11 && $p->{turn} == $turn) {
            my $pos = ((rstMapOwnerToRace($parsedReply, $p->{ownerid}) - 1) * 4);
            $scores[$pos] = $p->{planets};
            $scores[$pos+1] = $p->{capitalships};
            $scores[$pos+2] = $p->{freighters};
            $scores[$pos+3] = $p->{starbases};
        }
    }

    return $timestamp
      . pack("v*", @scores)
        . pack("v", rstMapOwnerToRace($parsedReply, $player))
          . "NOPASSWORD          "
            . pack("V*",
                   rstChecksum(substr($ships, 2)),
                   rstChecksum(substr($planets, 2)),
                   rstChecksum(substr($bases, 2)))
              . pack("v", $turn)
                . pack("v", rstChecksum($timestamp));
}

sub rstPackVcrs {
    my $parsedReply = shift;
    my $player = shift;
    my @vcrs;
    foreach my $vcr (@{$parsedReply->{rst}{vcrs}}) {
        my $v = pack("v*",
                     $vcr->{seed},
                     0x554E,       # 'NU', signature
                     $vcr->{right}{temperature},
                     $vcr->{battletype},
                     $vcr->{left}{mass},
                     $vcr->{right}{mass});
        foreach (qw(left right)) {
            my $o = $vcr->{$_};
            $v .= pack("A20v11",
                       $o->{name},
                       $o->{damage},
                       $o->{crew},
                       $o->{objectid},
                       $o->{raceid},
                       256*$o->{hullid} + 1,  # image, hull
                       $o->{beamid},
                       $o->{beamcount},
                       $o->{baycount},
                       $o->{torpedoid},
                       $o->{baycount}==0 ? $o->{torpedos} : $o->{fighters},
                       $o->{launchercount});
        }
        $v .= pack("vv", $vcr->{left}{shield}, $vcr->{right}{shield});
        push @vcrs, $v;
    }
    pack("v", scalar(@vcrs)) . join("", @vcrs);
}

sub rstWriteMessages {
    my $nmessages = @_;

    # Write preliminary header
    my $pos = tell(RST);
    print RST 'x' x (($nmessages * 6) + 2);

    # Write messages, generating header
    my $header = pack('v', $nmessages);
    foreach (@_) {
        $header .= pack('Vv', tell(RST)+1, length($_));
        print RST $_;
    }

    # Update header
    my $pos2 = tell(RST);
    seek RST, $pos, 0;
    print RST $header;
    seek RST, $pos2, 0;
}

sub rstFormatMessage {
    # Let's play simple: since our target is PCC2 which can do word wrapping,
    # we don't have to. Just remove the HTML.
    my $text = shift;
    $text =~ s|[\s\r\n]+| |g;
    $text =~ s| *<br */?> *|\n|g;
    $text;
}

sub rstEncryptMessage {
    my $text = shift;
    my $result;
    for (my $i = 0; $i < length($text); ++$i) {
        my $ch = substr($text, $i, 1);
        if ($ch eq "\n") {
            $result .= chr(26);
        } else {
            $result .= chr(ord($ch) + 13);
        }
    }
    $result;
}

sub rstPackFields {
    my $hash = shift;
    my $pack = shift;
    my @fields;
    foreach my $field (@_) {
        push @fields, $hash->{$field};
    }
    pack($pack, @fields);
}

sub rstPackStock {
    my $baseId = shift;
    my $parsedReply = shift;
    my $stockType = shift;

    my $pStocks = $parsedReply->{rst}{stock};
    my @result;
    foreach my $id (@_) {
        # Find a stock which matches this slot
        my $found = 0;
        foreach (@$pStocks) {
            if ($_->{starbaseid} == $baseId
                && $_->{stocktype} == $stockType
                && $_->{stockid} == $id)
            {
                $found = $_->{amount};
                last;
            }
        }
        push @result, $found;
    }

    pack("v*", @result);
}

sub rstChecksum {
    my $str = shift;
    my $sum = 0;
    for (my $i = 0; $i < length($str); ++$i) {
        $sum += ord(substr($str, $i, 1));
    }
    $sum;
}

sub rstGetBaseOwner {
    my $base = shift;
    my $parsedReply = shift;
    foreach my $planet (@{$parsedReply->{rst}{planets}}) {
        if ($planet->{id} == $base->{planetid}) {
            return $planet->{ownerid};
        }
    }
    return 0;
}

sub rstMapOwnerToRace {
    my $parsedReply = shift;
    my $ownerId = shift;
    foreach my $p (@{$parsedReply->{rst}{players}}) {
        if ($p->{id} == $ownerId) {
            return $p->{raceid};
        }
    }
    return 0;
}

######################################################################
#
#  Maketurn
#
######################################################################

sub doMakeTurn {
    # Load old state
    print "Reading result...\n";
    my $parsedReply = jsonParse(readFile("c2rst.txt"));
    stateCheckReply($parsedReply);
    my $player = $parsedReply->{rst}{player}{id};
    my $race = rstMapOwnerToRace($parsedReply, $player);

    # Load data
    my $pShips = mktLoadShips($race);
    my $pPlanets = mktLoadPlanets($race);
    my $pBases = mktLoadBases($race);

    # Complete data
    mktCompletePlanets($parsedReply, $pPlanets);
    mktCompleteFlows($parsedReply, $pShips, $pPlanets, $pBases);

    # Nu client uploads:
    # - changed planets
    # - changed ships
    # - changed bases
    # - all stocks if any stock changed
    # - all relations if any relation changed
    # - changed notes
    # To ensure that we always have consistent data at the host, it
    # makes sense to group items.
    # - all bases, planets, stocks, and ships orbiting
    # - planets, ships orbiting
    # - remaining ship groups

    # Ah, crap, just serialize everything into one big blob for now.
    my @turn;
    foreach (@$pPlanets) {
        push @turn, mktPackPlanet($parsedReply, $_);
    }
    foreach (@$pShips) {
        push @turn, mktPackShip($parsedReply, $_);
    }
    foreach (@$pBases) {
        push @turn, mktPackBase($parsedReply, $_);
    }
    push @turn, mktPackStocks($parsedReply, $pBases);

    my $pTurn = [ { type=>"commands",
                    data=>\@turn } ];

    # Save turn
    print "Making c2trn.txt...\n";
    open TRN, "> c2trn.txt" or die "c2trn.txt: $!\n";
    jsonDump(\*TRN, $pTurn, "");
    #foreach (@turn) {
    #    print TRN "$_\n";
    #}
    close TRN;
}

sub doUploadTurn {
    # Load the turn file
    print "Loading turn file...\n";
    my $pTurn = jsonParse(readFile("c2trn.txt"));

    # Process it
    foreach my $cmd (@$pTurn) {
        if ($cmd->{type} eq 'commands') {
            mktUploadOneCommand($cmd);
        } else {
            die "ERROR: turn file contains invalid section '$cmd->{type}'\n";
        }
    }
}


sub mktUploadOneCommand {
    my $cmd = shift;
    my $pCommands = $cmd->{data};

    my $query = join('&',
                     httpBuildQuery(gameId => stateGet('gameid'),
                                    playerId => stateGet('playerid'),
                                    turn => stateGet('turn'),
                                    version => '1.18',
                                    savekey => stateGet('savekey'),
                                    saveindex => '12'),
                     @$pCommands,
                     httpBuildQuery(keycount => 7+scalar(@$pCommands)));

    my $reply = httpCall("POST /_ui/plugins?method=Save&type=get&assembly=PlanetsNu.dll&object=PlanetsNu.GameFunctions HTTP/1.0\n", $query);
    my $parsedReply = jsonParse($reply->{BODY});
    if (exists($parsedReply->{success}) && $parsedReply->{success} =~ /true/i) {
        print "++ Upload succeeded ++\n";
    } else {
        print "++ Upload failed ++\n";
        print "Server answer:\n";
        foreach (sort keys %$parsedReply) {
            printf "%-20s %s\n", $_, $parsedReply->{$_};
        }
    }
}


sub mktPackStocks {
    my $parsedReply = shift;
    my $b = shift;
    my $th = $parsedReply->{rst}{racehulls};

    # Copy stocks
    my @stocks;
    my $lastStockId = 0;
    foreach (@{$parsedReply->{rst}{stock}}) {
        push @stocks, { amount => $_->{amount},
                        builtamount => $_->{builtamount},
                        id => $_->{id},
                        starbaseid => $_->{starbaseid},
                        stockid => $_->{stockid},
                        stocktype => $_->{stocktype} };
        if ($_->{id} >= $lastStockId) {
            $lastStockId = $_->{id};
        }
    }
    my $saveLastStockId = $lastStockId;

    # Populate and update stocks
    foreach my $bb (@$b) {
        my $origBase = asearch($parsedReply->{rst}{starbases}, 'planetid', $bb->{id});

        # Hulls
        foreach my $slot (1 .. @$th) {
            mktUpdateStock($origBase->{id}, 1, $th->[$slot - 1], \@stocks, \$lastStockId, $bb->{"hull$slot"});
        }

        # Engines
        foreach my $slot (1 .. 9) {
            mktUpdateStock($origBase->{id}, 2, $slot, \@stocks, \$lastStockId, $bb->{"engine$slot"});
        }

        # Beams
        foreach my $slot (1 .. 10) {
            mktUpdateStock($origBase->{id}, 3, $slot, \@stocks, \$lastStockId, $bb->{"beam$slot"});
        }

        # Torpedo Launchers
        foreach my $slot (1 .. 10) {
            mktUpdateStock($origBase->{id}, 4, $slot, \@stocks, \$lastStockId, $bb->{"tube$slot"});
        }

        # Torpedoes. Since these can be moved, the "built" values have been precomputed
        # in the "flows" step. So we just update the stocks.
        foreach my $slot (1 .. 10) {
            my $stock = mktFindStock($origBase->{id}, 5, $slot, \@stocks);
            if (defined($stock)) {
                $stock->{amount} = $bb->{"torp$slot"};
                $stock->{builtamount} = $bb->{"torp$slot"."Built"};
            } else {
                if ($bb->{"torp$slot"."Built"}) {
                    push @stocks, { amount => $bb->{"torp$slot"},
                                    starbaseid => $origBase->{id},
                                    builtamount => $bb->{"torp$slot"."Built"},
                                    id => ++$lastStockId,
                                    stockid => $slot,
                                    stocktype => 5 };
                }
            }
        }
    }

    if ($lastStockId != $saveLastStockId) {
        print "Created ", $lastStockId - $saveLastStockId, " stocks.\n";
        print "++ You should fetch your RST anew after uploading this turn. ++\n";
    }

    # Serialize them
    my @result;
    foreach (@stocks) {
        push @result, mktPack("Stock".$_->{id},
                              Id => $_->{id},
                              StarbaseId => $_->{starbaseid},
                              StockType => $_->{stocktype},
                              StockId => $_->{stockid},
                              Amount => $_->{amount},
                              BuiltAmount => $_->{builtamount});
    }
    @result;
}

sub mktUpdateStock {
    my $baseId = shift;
    my $stockType = shift;
    my $stockId = shift;
    my $pStocks = shift;
    my $pLastStockId = shift;
    my $amount = shift;

    my $stock = mktFindStock($baseId, $stockType, $stockId, $pStocks);
    if (defined($stock)) {
        # Update existing stock
        $stock->{builtamount} += $amount - $stock->{amount};
        $stock->{amount} = $amount;
    } else {
        # Make new stock
        if ($amount) {
            push @$pStocks, { amount => $amount,
                              starbaseid => $baseId,
                              builtamount => $amount,
                              id => ++$$pLastStockId,
                              stockid => $stockId,
                              stocktype => $stockType };
        }
    }
}

sub mktFindStock {
    my $baseId = shift;
    my $stockType = shift;
    my $stockId = shift;
    my $pStocks = shift;
    foreach (@$pStocks) {
        if ($_->{starbaseid} == $baseId && $_->{stocktype} == $stockType && $_->{stockid} == $stockId) {
            return $_;
        }
    }
    return undef;
}

sub mktPackBase {
    my $parsedReply = shift;
    my $b = shift;
    my $origBase = asearch($parsedReply->{rst}{starbases}, 'planetid', $b->{id});

    my @b;
    if ($b->{buildshiptype}) {
        my $th = $parsedReply->{rst}{racehulls};
        if ($b->{buildshiptype} <= @$th) {
            @b = (BuildHullId => $th->[$b->{buildshiptype} - 1],
                  BuildEngineId => $b->{buildengineid},
                  BuildBeamId => $b->{buildbeamid},
                  BuildTorpedoId => $b->{buildtorpedoid},
                  BuildBeamCount => $b->{buildbeamcount},
                  BuildTorpCount => $b->{buildtorpcount},
                  IsBuilding => 'true');
        } else {
            die "ERROR: starbase $b->{id}: Attempt to build an impossible ship\n";
        }
    } else {
        @b = (BuildHullId => 0,
              BuildEngineId => 0,
              BuildBeamId => 0,
              BuildTorpedoId => 0,
              BuildBeamCount => 0,
              BuildTorpCount => 0,
              IsBuilding => 'false');
    }

    mktPack("Starbase".$origBase->{id},
            Id => $origBase->{id},
            Fighters => $b->{fighters},
            Defense => $b->{defense},
            BuiltFighters => $b->{fightersBuilt},
            BuiltDefense => $b->{defense} - $origBase->{defense} + $origBase->{builtdefense},
            HullTechLevel => $b->{hulltechlevel},
            EngineTechLevel => $b->{enginetechlevel},
            BeamTechLevel => $b->{beamtechlevel},
            TorpTechLevel => $b->{torptechlevel},
            HullTechUp => $b->{hulltechlevel} - $origBase->{hulltechlevel} + $origBase->{hulltechup},
            EngineTechUp => $b->{enginetechlevel} - $origBase->{enginetechlevel} + $origBase->{enginetechup},
            BeamTechUp => $b->{beamtechlevel} - $origBase->{beamtechlevel} + $origBase->{beamtechup},
            TorpTechUp => $b->{torptechlevel} - $origBase->{torptechlevel} + $origBase->{torptechup},
            Mission => $b->{mission},
            ShipMission => $b->{yardshipaction},
            TargetShipId => $b->{yardshipid},
            @b,
            ReadyStatus => $origBase->{readystatus});
}

sub mktPackPlanet {
    my $parsedReply = shift;
    my $p = shift;
    my $origPlanet = asearch($parsedReply->{rst}{planets}, 'id', $p->{id});

    mktPack("Planet".$p->{id},
            Id => $p->{id},
            FriendlyCode => $p->{fcode},
            Mines => $p->{mines},
            Factories => $p->{factories},
            Defense => $p->{defense},
            TargetMines => $origPlanet->{targetmines},
            TargetFactories => $origPlanet->{targetfactories},
            TargetDefense => $origPlanet->{targetdefense},
            BuiltMines => $p->{mines} - $origPlanet->{mines} + $origPlanet->{builtmines},
            BuiltFactories => $p->{factories} - $origPlanet->{factories} + $origPlanet->{builtfactories},
            BuiltDefense => $p->{defense} - $origPlanet->{defense} + $origPlanet->{builtdefense},
            MegaCredits => $p->{money},
            Supplies => $p->{supplies},
            SuppliesSold => $p->{suppliesSold},
            Neutronium => $p->{neutronium},
            Molybdenum => $p->{molybdenum},
            Duranium => $p->{duranium},
            Tritanium => $p->{tritanium},
            Clans => $p->{clans},
            ColonistTaxRate => $p->{colonisttaxrate},
            NativeTaxRate => $p->{nativetaxrate},
            BuildingStarbase => ($p->{buildbase} ? "true" : "false"),
            NativeHappyChange => $origPlanet->{nativehappychange},  # let's hope the host calculates this anew.
            ColHappyChange => $origPlanet->{colhappychange},
            ColChange => $origPlanet->{colchange},
            ReadyStatus => $origPlanet->{readystatus});
}

sub mktPackShip {
    my $parsedReply = shift;
    my $s = shift;
    my $origShip = asearch($parsedReply->{rst}{ships}, 'id', $s->{id});

    # Name: Nu allows names >20 chars, so try to keep the original name
    my $name;
    if (substr($s->{name} . (' 'x20), 0, 20) eq substr($origShip->{name}, 0, 20)) {
        $name = $origShip->{name};
    } else {
        $name = $s->{name};
    }

    # Mission: undo remapping
    my $m = $s->{mission} - 1;
    my $t1 = $m==7 ? $s->{intid} : $m==6 ? $s->{towid} : 0;
    my $t2 = 0;

    # Transfer
    my @x;
    if (mktShipHasTransfer($s, 'unload')) {
        if (mktShipHasTransfer($s, 'transfer')) {
            print "WARNING: ship $s->{id} has unload and transfer order at the same time, transfer was ignored\n";
        }
        @x = (TransferNeutronium => $s->{unloadneutronium},
              TransferDuranium => $s->{unloadduranium},
              TransferTritanium => $s->{unloadtritanium},
              TransferMolybdenum => $s->{unloadmolybdenum},
              TransferMegaCredits => 0,
              TransferSupplies => $s->{unloadsupplies},
              TransferClans => $s->{unloadclans},
              TransferAmmo => 0,
              TransferTargetId => $s->{unloadid},
              TransferTargetType => 1);
    } elsif (mktShipHasTransfer($s, 'transfer')) {
        @x = (TransferNeutronium => $s->{transferneutronium},
              TransferDuranium => $s->{transferduranium},
              TransferTritanium => $s->{transfertritanium},
              TransferMolybdenum => $s->{transfermolybdenum},
              TransferMegaCredits => 0,
              TransferSupplies => $s->{transfersupplies},
              TransferClans => $s->{transferclans},
              TransferAmmo => 0,
              TransferTargetId => $s->{transferid},
              TransferTargetType => 2);
    } else {
        @x = (TransferNeutronium => 0,
              TransferDuranium => 0,
              TransferTritanium => 0,
              TransferMolybdenum => 0,
              TransferMegaCredits => 0,
              TransferSupplies => 0,
              TransferClans => 0,
              TransferAmmo => 0,
              TransferTargetId => 0,
              TransferTargetType => 0);
    }

    my $enemy = 0;
    if ($s->{enemy}) {
        my $enemyRace = asearch($parsedReply->{rst}{players}, 'raceid', $s->{enemy});
        if (!defined($enemyRace)) {
            print "WARNING: ship $s->{id} has a Primary Enemy which is not in the game; ignored.\n";
        } else {
            $enemy = $enemyRace->{id};
        }
    }

    mktPack("Ship".$s->{id},
            Id => $s->{id},
            Name => $name,
            Neutronium => $s->{neutronium},
            Duranium => $s->{duranium},
            Tritanium => $s->{tritanium},
            Molybdenum => $s->{molybdenum},
            MegaCredits => $s->{money},
            Supplies => $s->{supplies},
            Clans => $s->{clans},
            Ammo => $s->{ammo},
            @x,
            TargetX => ($s->{x} + $s->{dx}) & 65535,
            TargetY => ($s->{y} + $s->{dy}) & 65535,
            FriendlyCode => $s->{fcode},
            Warp => $s->{warp},
            Mission => $m,
            Mission1Target => $t1,
            Mission2Target => $t2,
            Enemy => $enemy,
            Waypoints => "",
            ReadyStatus => $origShip->{readystatus}
           );
}


# Complete flows: create suppliesSold (planet), torpXBuilt, fightersBuilt (base)
sub mktCompleteFlows {
    my $parsedReply = shift;
    my $pShips = shift;
    my $pPlanets = shift;
    my $pBases = shift;

    foreach my $p (@$pPlanets) {
        # Planet: supplies
        my $origPlanet = asearch($parsedReply->{rst}{planets}, 'id', $p->{id});
        $p->{suppliesSold} = $origPlanet->{supplies} - $p->{supplies} + $origPlanet->{suppliessold};

        # Structures
        foreach (qw(mines factories defense)) {
            $p->{suppliesSold} -= $p->{$_} - $origPlanet->{$_} + $origPlanet->{"built$_"};
        }

        # Ship supplies
        foreach my $s (@$pShips) {
            if ($s->{x} == $p->{x} && $s->{y} == $p->{y}) {
                my $origShip = asearch($parsedReply->{rst}{ships}, 'id', $s->{id});
                $p->{suppliesSold} += $origShip->{supplies} - $s->{supplies};
            }
        }

        # Base and orbits: ammo
        my $b = asearch($pBases, 'id', $p->{id});
        if (defined($b)) {
            my $origBase = asearch($parsedReply->{rst}{starbases}, 'planetid', $p->{id});

            # Fighters
            $b->{fightersBuilt} = $b->{fighters} - $origBase->{fighters} + $origBase->{builtfighters};

            # Torps
            foreach (1 .. 10) {
                my $stock = unpFindStock($origBase->{id}, $parsedReply, 5, $_);
                $b->{"torp$_"."Built"} = $b->{"torp$_"} - $stock->{amount} + $stock->{builtamount};
            }

            # Ships
            foreach my $s (@$pShips) {
                if ($s->{x} == $p->{x} && $s->{y} == $p->{y}) {
                    my $origShip = asearch($parsedReply->{rst}{ships}, 'id', $s->{id});
                    if ($origShip->{bays} > 0) {
                        $b->{fightersBuilt} += $s->{ammo} - $origShip->{ammo};
                    } elsif ($origShip->{torps} > 0) {
                        $b->{"torp".$origShip->{torpedoid}."Built"} += $s->{ammo} - $origShip->{ammo};
                    }
                }
            }
        }
    }
}

# Complete planets: fill in x,y data
sub mktCompletePlanets {
    my $parsedReply = shift;
    my $pPlanets = shift;
    foreach (@$pPlanets) {
        my $origPlanet = asearch($parsedReply->{rst}{planets}, 'id', $_->{id});
        $_->{x} = $origPlanet->{x};
        $_->{y} = $origPlanet->{y};
    }
}

sub mktLoadShips {
    my $race = shift;
    return mktLoadFile("ship$race.dat", $race, 107,
                       "v2A3v19A20v21",
                       qw(id player fcode warp dx dy x y engine hull beam nbeams nbays torp ammo ntubes mission enemy towid
                          damage crew clans name neutronium tritanium duranium molybdenum supplies
                          unloadneutronium unloadtritanium unloadduranium unloadmolybdenum unloadclans unloadsupplies unloadid
                          transferneutronium transfertritanium transferduranium transfermolybdenum transferclans transfersupplies transferid
                          intid money));
}

sub mktLoadPlanets {
    my $race = shift;
    return mktLoadFile("pdata$race.dat", $race, 85,
                       "v2A3v3V11v9Vv3",
                       qw(player id fcode mines factories defense
                          neutronium tritanium duranium molybdenum
                          clans supplies money
                          groundneutronium groundtritanium groundduranium groundmolybdenum
                          densityneutronium densitytritanium densityduranium densitymolybdenum
                          colonisttaxrate nativetaxrate colonisthappypoints nativehappypoints
                          nativegovernment
                          nativeclans
                          nativeracename temperature buildbase));
}

sub mktLoadBases {
    my $race = shift;
    return mktLoadFile("bdata$race.dat", $race, 156,
                       "v78",
                       qw(id player defense damage
                          enginetechlevel hulltechlevel beamtechlevel torptechlevel
                          engine1 engine2 engine3 engine4 engine5 engine6 engine7 engine8 engine9
                          hull1 hull2 hull3 hull4 hull5 hull6 hull7 hull8 hull9 hull10
                          hull11 hull12 hull13 hull14 hull15 hull16 hull17 hull18 hull19 hull20
                          beam1 beam2 beam3 beam4 beam5 beam6 beam7 beam8 beam9 beam10
                          tube1 tube2 tube3 tube4 tube5 tube6 tube7 tube8 tube9 tube10
                          torp1 torp2 torp3 torp4 torp5 torp6 torp7 torp8 torp9 torp10
                          fighters
                          yardshipid
                          yardshipaction
                          mission
                          buildshiptype
                          buildengineid
                          buildbeamid buildbeamcount
                          buildtorpedoid buildtorpcount
                          zero));
}

# Load a file
sub mktLoadFile {
    my $f = shift;
    my $race = shift;
    my $size = shift;
    my $pattern = shift;
    my @result;

    # Open file, read count
    open FILE, "< $f" or die "$f: $!\n";
    binmode FILE;
    my $h;
    my $skip = 0;
    if (read(FILE, $h, 2) != 2) { die "$f: read error\n" }
    $h = unpack("v", $h);
    for (my $i = 0; $i < $h; ++$i) {
        # Read one item
        my $item;
        if (read(FILE, $item, $size) != $size) { die "$f: read error\n" }

        # Parse item into hash
        my @item = unpack($pattern, $item);
        my $thisResult = {};
        foreach (@_) {
            if (!@item) { die }
            $thisResult->{$_} = shift(@item);
        }
        if (@item) { die }

        # Remember item only if it belongs to our race
        if ($thisResult->{player} == $race) {
            push @result, $thisResult
        } else {
            ++$skip;
        }
    }

    # Validate
    my $j;
    my $i = read(FILE, $j, 11);
    if ($i != 0 && $i != 10) { die "$f: invalid file size\n"; }

    close FILE;
    print "Loaded $f ($h entries, $skip skipped).\n";
    return \@result;
}

# Pack data
sub mktPack {
    my $name = shift;
    my $result = "$name=";
    my $first = 1;
    while (@_) {
        my $key = shift;
        my $value = shift;
        if (!defined($value)) {
            print "WARNING: internal error, $name/$key is undefined\n";
            last
        }
        if ($value =~ s:[|&]:_:g) {
            print "WARNING: '|' or '&' are not allowed with fragile web apps, replaced with '_' on $name/$key\n";
        }
        $result .= "|||" unless $first;
        $result .= $key;
        $result .= ":::";
        $result .= latin1ToUtf8($value);
        $first = 0;
    }
    $result;
}

sub mktShipHasTransfer {
    my $s = shift;
    my $what = shift;
    return $s->{$what."neutronium"} > 0
      || $s->{$what."tritanium"} > 0
        || $s->{$what."duranium"} > 0
          || $s->{$what."molybdenum"} > 0
            || $s->{$what."clans"} > 0
              || $s->{$what."supplies"} > 0;
}


######################################################################
#
#  State file
#
######################################################################

my %stateValues;
my %stateChanged;

sub stateLoad {
    if (open(STATE, "< c2nu.ini")) {
        while (<STATE>) {
            s/[\r\n]*$//;
            next if /^ *#/;
            next if /^ *$/;
            if (/^(.*?)=(.*)/) {
                my $key = $1;
                my $val = $2;
                $val =~ s|\\(.)|stateUnquote($1)|eg;
                $stateValues{$key} = $val;
                $stateChanged{$key} = 0;
            } else {
                print "WARNING: state file line $. cannot be parsed\n";
            }
        }
        close STATE;
    }
}

sub stateSave {
    # Needed?
    my $needed = 0;
    foreach (keys %stateValues) {
        if ($stateChanged{$_}) {
            # print "Must update state file because '$_' has changed.\n";
            $needed = 1;
            last;
        }
    }
    return if !$needed;
    print "Updating state file...\n";

    # Copy existing file, updating it
    open(OUT, "> c2nu.new") or die "ERROR: cannot create new state file c2nu.new: $!\n";
    if (open(STATE, "< c2nu.ini")) {
        while (<STATE>) {
            s/[\r\n]*$//;
            if (/^ *#/ || /^ *$/) {
                print OUT "$_\n";
            } elsif (/^(.*?)=(.*)/ && $stateChanged{$1}) {
                my $key = $1;
                print OUT "$key=", stateQuote($stateValues{$key}), "\n";
                $stateChanged{$key} = 0;
            } else {
                print OUT "$_\n";
            }
        }
        close STATE;
    }

    # Print missing keys
    foreach (sort keys %stateValues) {
        if ($stateChanged{$_}) {
            print OUT "$_=", stateQuote($stateValues{$_}), "\n";
            $stateChanged{$_} = 0;
        }
    }
    close OUT;

    # Rename files
    unlink "c2nu.bak";
    rename "c2nu.ini", "c2nu.bak";
    rename "c2nu.new", "c2nu.ini" or print "WARNING: cannot rename new state file: $!\n";
}

sub stateSet {
    my $key = shift;
    my $val = shift;
    if (!exists($stateValues{$key}) || $stateValues{$key} ne $val) {
        $stateValues{$key} = $val;
        $stateChanged{$key} = 1;
    }
}

sub stateGet {
    my $key = shift;
    if (exists($stateValues{$key})) {
        $stateValues{$key}
    } else {
        "";
    }
}

sub stateQuote {
    my $x = shift;
    $x =~ s/\\/\\\\/g;
    $x =~ s/\n/\\n/g;
    $x =~ s/\r/\\r/g;
    $x =~ s/\t/\\t/g;
    $x =~ s/\t/\\t/g;
    $x =~ s/"/\\"/g;
    $x =~ s/'/\\'/g;
    $x;
}

sub stateUnquote {
    my $x = shift;
    if ($x eq 'n') {
        return "\n";
    } elsif ($x eq 't') {
        return "\t";
    } elsif ($x eq 'r') {
        return "\r";
    } else {
        return $x;
    }
}

sub stateCookies {
    my @cookie;
    foreach (sort keys %stateValues) {
        if (/^cookie_(.*)/) {
            push @cookie, "$1=$stateValues{$_}";
        }
    }
    join("; ", @cookie);
}

# Check a received reply for consistency, and remember necessary
# items in state file.
sub stateCheckReply {
    my $parsedReply = shift;
    if (!exists $parsedReply->{rst}) {
        die "ERROR: no result file received\n";
    }
    if (!$parsedReply->{rst}{player}{raceid}) {
        die "ERROR: result does not contain player name\n";
    }
    if ($parsedReply->{rst}{player}{savekey} ne $parsedReply->{savekey}) {
        die "ERROR: received two different savekeys\n"
    }
    stateSet('savekey', $parsedReply->{savekey});
    stateSet('player', $parsedReply->{rst}{player}{raceid});     # user-visible player number ("7 = crystal")
    stateSet('playerid', $parsedReply->{rst}{player}{id});       # internal player Id used for everything
    stateSet('turn', $parsedReply->{rst}{settings}{turn});
}

sub doStatus {
    foreach (sort keys %stateValues) {
        my $v = stateQuote($stateValues{$_});
        print "$_ =\n";
        if (length($v) > 70) {
            print "   ", substr($v, 0, 67), "...\n";
        } else {
            print "   ", $v, "\n";
        }
    }
}

######################################################################
#
#  HTTP
#
######################################################################

sub httpCall {
    # Prepare
    my ($head, $body) = @_;
    my $host = stateGet('host');
    my $keks = stateCookies();
    $head .= "Host: $host\n";
    $head .= "Content-Length: " . length($body) . "\n";
    $head .= "Connection: close\n";
    $head .= "Cookie: $keks\n" if $keks ne '';
    # $head .= "User-Agent: $0\n";
    $head =~ s/\n/\r\n/;
    $head .= "\r\n";

    # Socket cruft
    print "Calling server...\n";
    my $ip = inet_aton($host) or die "ERROR: unable to resolve host '$host': $!\n";
    my $paddr = sockaddr_in(80, $ip);
    socket(HTTP, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "ERROR: unable to create socket: $!\n";
    binmode HTTP;
    HTTP->autoflush(1);
    connect(HTTP, $paddr) or die "ERROR: unable to connect to '$host': $!\n";

    # Send request
    print HTTP $head, $body;

    # Read reply header
    my %reply;
    while (<HTTP>) {
        s/[\r\n]*$//;
        if (/^$/) {
            last
        } elsif (m|^HTTP/\d+\.\d+ (\d+)|) {
            $reply{STATUS} = $1;
        } elsif (m|^set-cookie:\s*(.*?)=(.*?);|i) {
            $reply{"COOKIE-$1"} = $2;
        } elsif (m|^(.*?):\s+(.*)|) {
            $reply{lc($1)} = $2;
        } else {
            print STDERR "Unable to parse reply line '$_'\n";
        }
    }

    # Read reply body
    my $replybody;
    if (exists $reply{'content-length'}) {
        read HTTP, $replybody, $reply{'content-length'}
    } else {
        while (1) {
            my $tmp;
            if (!read(HTTP, $tmp, 4096)) { last }
            $replybody .= $tmp;
        }
    }
    close HTTP;

    # Check status
    if ($reply{STATUS} != 200) {
        print STDERR "WARNING: HTTP status is $reply{STATUS}.\n";
    }

    # Body might be compressed; decompress it
    if (lc($reply{'content-encoding'}) eq 'gzip') {
        print "Decompressing result...\n";
        open TMP, "> c2nu.gz" or die "Cannot open temporary file: $!\n";
        binmode TMP;
        print TMP $replybody;
        close TMP;
        $replybody = "";
        open TMP, "gzip -dc c2nu.gz |" or die "Cannot open gzip: $!\n";
        binmode TMP;
        while (1) {
            my $tmp;
            if (!read(TMP, $tmp, 4096)) { last }
            $replybody .= $tmp;
        }
        close TMP;
    }

    $reply{BODY} = $replybody;
    \%reply;
}

sub httpEscape {
    my $x = shift;
    $x =~ s/([&+%\r\n])/sprintf("%%%02X", ord($1))/eg;
    $x =~ s/ /+/g;
    $x;
}

sub httpBuildQuery {
    my @list;
    while (@_) {
        my $key = shift @_;
        my $val = shift @_;
        push @list, "$key=" . httpEscape($val);
    }
    join('&', @list);
}

######################################################################
#
#  JSON
#
######################################################################

sub jsonParse {
    my $str = shift;
    pos($str) = 0;
    jsonParse1(\$str);
}

sub jsonParse1 {
    my $pstr = shift;
    $$pstr =~ m|\G\s*|sgc;
    if ($$pstr =~ m#\G"(([^\\"]+|\\.)*)"#gc) {
        my $s = $1;
        $s =~ s|\\(.)|stateUnquote($1)|eg;
        # Nu data is in UTF-8. Translate what we can to latin-1, because
        # PCC does not handle UTF-8 in game files. Doing it here conveniently
        # handles all places with possible UTF-8, including ship names,
        # messages, and notes.
        utf8ToLatin1($s);
    } elsif ($$pstr =~ m|\G([-+]?\d+\.\d*)|gc) {
        $1;
    } elsif ($$pstr =~ m|\G([-+]?\.\d+)|gc) {
        $1;
    } elsif ($$pstr =~ m|\G([-+]?\d+)|gc) {
        $1;
    } elsif ($$pstr =~ m|\Gtrue\b|gc) {
        1
    } elsif ($$pstr =~ m|\Gfalse\b|gc) {
        0
    } elsif ($$pstr =~ m|\Gnull\b|gc) {
        undef
    } elsif ($$pstr =~ m|\G\{|gc) {
        my $result = {};
        while (1) {
            $$pstr =~ m|\G\s*|sgc;
            if ($$pstr =~ m|\G\}|gc) { last }
            elsif ($$pstr =~ m|\G,|gc) { }
            else {
                my $key = jsonParse1($pstr);
                $$pstr =~ m|\G\s*|sgc;
                if ($$pstr !~ m|\G:|gc) { die "JSON syntax error: expecting ':', got '" . substr($$pstr, pos($$pstr), 20) . "'.\n" }
                my $val = jsonParse1($pstr);
                $result->{$key} = $val;
            }
        }
        $result;
    } elsif ($$pstr =~ m|\G\[|gc) {
        my $result = [];
        while (1) {
            $$pstr =~ m|\G\s*|sgc;
            if ($$pstr =~ m|\G\]|gc) { last }
            elsif ($$pstr =~ m|\G,|gc) { }
            else { push @$result, jsonParse1($pstr) }
        }
        $result;
    } else {
        die "JSON syntax error: expecting element, got '" . substr($$pstr, pos($$pstr), 20) . "'.\n";
    }
}

sub jsonDump {
    my $fd = shift;
    my $tree = shift;
    my $prefix = shift;
    my $indent = "$prefix    ";
    if (ref($tree) eq 'ARRAY') {
        # Array.
        if (@$tree == 0) {
            # Empty
            print $fd "[]";
        } elsif (grep {ref or /\D/} @$tree) {
            # Full form
            print $fd "[\n$indent";
            my $i = 0;
            foreach (@$tree) {
                print $fd ",\n$indent" if $i;
                $i = 1;
                jsonDump($fd, $_, $indent);
            }
            print $fd "\n$prefix]";
        } else {
            # Short form
            print $fd "[";
            my $i = 0;
            foreach (@$tree) {
                if ($i > 20) {
                    print $fd ",\n$indent";
                    $i = 0;
                } else {
                    print $fd "," if $i;
                    ++$i;
                }
                jsonDump($fd, $_, $indent);
            }
            print $fd "]";
        }
    } elsif (ref($tree) eq 'HASH') {
        # Hash
        print $fd "{";
        my $i = 0;
        foreach (sort keys %$tree) {
            print $fd "," if $i;
            $i = 1;
            print $fd "\n$indent\"", stateQuote($_), "\": ";
            jsonDump($fd, $tree->{$_}, $indent);
        }
        print $fd "\n$prefix" if $i;
        print $fd "}";
    } else {
        # scalar
        if (!defined($tree)) {
            print $fd "null";
        } elsif ($tree =~ /^-?\d+$/) {
            print $fd $tree;
        } else {
            print $fd '"', stateQuote($tree), '"';
        }
    }
}

######################################################################
#
#  XML
#
######################################################################

# DOM:
#   a document is a list of items.
#   an item is a string or a tag.
#   a tag is an embedded hash:
#     TAG => tag name
#     CONTENT => content, reference to a document
#     name => attribute

sub xmlParse {
    my $str = shift;
    pos($str) = 0;
    my @stack = ({CONTENT=>[]});
    while (1) {
        if ($str =~ m|\G$|) {
            last
        } elsif ($str =~ m|\G</(\w+)>|gc) {
            if (!exists($stack[-1]->{TAG}) || $stack[-1]->{TAG} ne $1) {
                die "XML syntax error: got '</$1>' while expecting another\n";
            }
            pop @stack;
        } elsif ($str =~ m|\G<!--.*?-->|gc) {
            # Comment
        } elsif ($str =~ m|\G<(\w+)\s*|gc) {
            # Opening tag
            my $t = {TAG=>$1, CONTENT=>[]};
            push @{$stack[-1]->{CONTENT}}, $t;
            push @stack, $t;

            # Read attributes
            while ($str =~ m|\G(\w+)\s*=\"([^"]*)\"\s*|gc || $str =~ m|\G(\w+)\s*=\'([^']*)\'\s*|gc) {       #"){
                $t->{lc($1)} = xmlUnquote($2);
            }

            # Close
            if ($str =~ m|\G/\s*>|gc) {
                pop @stack;
            } elsif ($str =~ m|\G>|gc) {
                # keep
            } else {
                die "XML syntax error: got '" . substr($str, pos($str), 20) . "' while expecting tag end\n";
            }
        } elsif ($str =~ m|\G([^<]+)|sgc) {
            push @{$stack[-1]->{CONTENT}}, xmlUnquote($1);
        } else {
            die "XML syntax error: got '" . substr($str, pos($str), 20) . "' while expecting tag or text\n";
        }
    }
    $stack[0];
}

sub xmlUnquote {
    my $str = shift;
    $str =~ s|&(.*?);|xmlEntity($1)|eg;
    $str;
}

sub xmlEntity {
    my $x = shift;
    if ($x eq 'lt') { return "<" }
    if ($x eq 'gt') { return ">" }
    if ($x eq 'amp') { return "&" }
    if ($x eq 'quot') { return "\"" }
    if ($x eq 'apos') { return "'" }
    if ($x =~ /^\#(\d+)/) { return chr($1) }
    if ($x =~ /^\#x([0-9a-f]+)/i) { return chr(hex($1)) }
    return "?";
}

sub xmlPrint {
    my $xml = shift;
    my $indent = shift || "";
    if (exists $xml->{TAG}) {
        print "$indent <$xml->{TAG}>\n";
        foreach my $k (sort keys %$xml) {
            print "$indent   \@$k=$xml->{$k}\n"
                unless $k eq 'TAG' || $k eq 'CONTENT';
        }
    } else {
        print "$indent ROOT\n";
    }
    foreach (@{$xml->{CONTENT}}) {
        if (ref) {
            xmlPrint($_, "$indent    ");
        } else {
            print "$indent     \"$_\"\n";
        }
    }
}

# xmlDirectChildren($tag, @list)
#   Given a list of items, extract all that have a particular tag name.
#   Somehow like XPath "<list>/tag".
sub xmlDirectChildren {
    my $tag = shift;
    grep {ref($_) && $_->{TAG} eq $tag} @_;
}

# xmlIndirectChildren($tag, @list)
#   Like xmlDirectChildren, but searches indirect children as well.
#   Somehow like XPath "<list>//tag".
sub xmlIndirectChildren {
    my $tag = shift;
    my @result;
    foreach (@_) {
        if (ref($_)) {
            if (exists($_->{TAG}) && $_->{TAG} eq $tag) {
                push @result, $_
            } else {
                push @result, xmlIndirectChildren($tag, @{$_->{CONTENT}});
            }
        }
    }
    @result;
}

# Given a list of tags, merge its content into one list
sub xmlMergeContent {
    my @result;
    foreach (@_) {
        push @result, @{$_->{CONTENT}};
    }
    @result;
}

# Find content.
sub xmlTextContent {
    join ('', grep {!ref($_)} @_);
}

######################################################################
#
#  Utilities
#
######################################################################

sub replicate {
    my $n = shift;
    my @result;
    foreach (1 .. $n) { push @result, @_ }
    @result;
}

sub sequence {
    my $a = shift;
    my $b = shift;
    my @result;
    while ($b > 0) {
        push @result, $a++;
        --$b;
    }
    @result;
}

# Array search: given an array, returns the element which has {$key} = $value
sub asearch {
    my $pArray = shift;
    my $key = shift;
    my $value = shift;
    my $default = shift;
    foreach (@$pArray) {
        if ($_->{$key} == $value) {
            return $_
        }
    }
    return $default;
}

sub utf8ToLatin1 {
    my $s = shift;
    $s =~ s/([\xC0-\xC3])([\x80-\xBF])/chr(((ord($1) & 3) << 6) + (ord($2) & 63))/eg;
    $s;
}

sub latin1ToUtf8 {
    my $s = shift;
    $s =~ s/([\x80-\xFF])/chr(0xC0 + (ord($1) >> 6)) . chr(0x80 + (ord($1) & 63))/eg;
    $s;
}

sub readFile {
    my $f = shift;
    open IN, "< $f" or die "$f: $!\n";
    my $body;
    while (1) {
        my $tmp;
        if (!read(IN, $tmp, 4096)) { last }
        $body .= $tmp;
    }
    close IN;
    $body;
}
#end
