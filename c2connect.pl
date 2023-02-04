#!/usr/bin/perl -w
#
#  PlanetsCentral interface
#
#  This script accesses the PlanetsCentral server using the HTTP API.
#  This is a quick-and-dirty, proof-of-concept program.
#
#  (Actual API fun will happen in PCC2ng.)
#
#  A Nu RST file is a JSON data structure and contains the
#  specification files, RST, and some history data.
#
#  Usage:
#    perl c2connect.pl [--api=H] CMD [ARGS...]
#
#  Options:
#    --api=H        set API address name (setting will be stored in state file)
#
#  Commands:
#    help           Help screen (no network access)
#    status         Show state file content (no network access)
#    login USER PW  Log in with user Id and password
#    list           List games (must be logged in)
#    rst [PATH PLAYER]   Download RST (must be logged in). PATH is the game
#                   path and can be omitted on second and later uses.
#    trn [PLAYER]   Upload TRN
#
#  Instructions:
#  - make a directory and go there using the command prompt
#  - log in using 'c2connect login USER PASS'
#  - list games using 'c2connect list'
#  - download RST using 'c2connect rst PATH PLAYER', where PATH is the
#    directory on the server ('u/youruser/...').
#  - upload TRN using 'c2connect trn'
#
#  Limitations:
#  - Can only download RSTs for games that have a server-side directory
#  - Can only upload TRNs for hosted games
#  - Does not do HTTPS. Your password/API key will be transmitted in plain-text!
#  - No handling for other player files yet (ship list etc.)
#
#  (c) 2023 Stefan Reuther
#
use strict;
use Socket;
use IO::Handle;
use IO::Socket;
use bytes;              # without this, perl 5.6.1 doesn't correctly read Unicode stuff

my $VERSION = "0.3.7";

# Initialisation
stateSet('api', 'planetscentral.com');
stateLoad();

# Parse arguments
while (@ARGV) {
    if ($ARGV[0] =~ /^--?api=(.*)/) {
        stateSet('api', $1);
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
} elsif ($cmd eq 'rst') {
    doDownloadResult();
} elsif ($cmd eq 'trn') {
    doUploadTurn();
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
    print "$0 - planetscentral.com interface - version $VERSION, (c) 2023 Stefan Reuther\n\n";
    print "$0 [options] command [command args]\n\n";
    print "Options:\n";
    print "  --api=HOST        instead of 'planetscentral.com'\n";
    print "Commands:\n";
    print "  help              this help screen\n";
    print "  status            show status\n";
    print "  login USER PASS   log in\n";
    print "  list              list games\n";
    print "  rst [PATH USER]   download RST\n";
    print "  trn [USER]        upload TRN\n";
}

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

    my $reply = httpCall("POST /api/user.cgi HTTP/1.0\n",
                         httpBuildQuery(action => "whoami",
                                        api_user => $user,
                                        api_password => $pass));

    my $parsedReply = jsonParse($reply->{BODY});
    if ($parsedReply->{result} && $parsedReply->{loggedin}) {
        print "++ Login succeeded ++\n";
        stateSet('user', $user);
        stateSet('apikey', $parsedReply->{api_token});
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
    my $reply = httpCall("POST /api/file.cgi HTTP/1.0\n",
                         httpBuildQuery(api_token => stateGet('apikey'),
                                        action => 'lsgame',
                                        dir => 'u/'.stateGet('user')));
    my $parsedReply = jsonParse($reply->{BODY});
    my $needHeader = 1;
    if ($parsedReply->{result} && ref($parsedReply->{reply})) {
        foreach (@{$parsedReply->{reply}}) {
            my $gameName = $_->{name} || '?';
            my $gameNr   = $_->{game} || '';
            my $type     = $_->{game} ? 'Hosted' : 'Uploaded';
            my $path     = $_->{path} || '?';
            my @races    = $_->{races} ? sort {$a<=>$b} keys %{$_->{races}} : ();

            # Print
            print "Game      Path                                      Name                  Races            Category\n" if $needHeader;
            print "--------  ----------------------------------------  --------------------  ---------------  --------------------\n" if $needHeader;
            printf "%8s  %-40s  %-20s  %-15s  %s\n", $gameNr, $path, $gameName, join(' ', @races), $type;
            $needHeader = 0;
        }
    } else {
        print "++ Unable to obtain game list ++\n";
    }
}

######################################################################
#
#  Result file
#
######################################################################
sub doDownloadResult {
    my $gamePath;
    my $player;
    foreach (@ARGV) {
        if (/^-/) {
            die "rst: unknown option '$_'\n";
        } else {
            if (!defined($gamePath)) {
                $gamePath = $_;
            } elsif (!defined($player)) {
                $player = $_;
            } else {
                die "rst: need zero or two parameters, game path + player number\n";
            }
        }
    }
    if (!defined($gamePath)) {
        $gamePath = stateGet('gamepath');
    }
    if (!defined($player)) {
        $player = stateGet('player');
    }
    if (!$gamePath || !$player) {
        die "rst1: need two parameters, game path + player number\n";
    }
    stateSet('gamepath', $gamePath);
    stateSet('player', $player);

    # For now, there is no "get file" API, but the regular file download entrypoint can be "abused".
    # However, it does not expect the leading 'u/'.
    $gamePath =~ s|^u/||;

    print "Getting result...\n";
    my $rstName = 'player'.$player.'.rst';
    my $params = httpBuildQuery(api_token => stateGet('apikey'));
    my $reply = httpCall("GET /file.cgi/$gamePath/$rstName?$params HTTP/1.0\n", '');

    if ($reply->{STATUS} == 200) {
        open RST, '>', $rstName or die "$rstName: $!\n";
        binmode RST;
        print RST $reply->{BODY};
        close RST;
        print "Result downloaded successfully.\n";
    } else {
        print "++ Result download failed. ++\n";
    }
}

######################################################################
#
#  Turn Upload
#
######################################################################
sub doUploadTurn {
    my $player;
    foreach (@ARGV) {
        if (/^-/) {
            die "trn: unknown option '$_'\n";
        } else {
            if (!defined($player)) {
                $player = $_;
            } else {
                die "trn: one parameter, player number\n";
            }
        }
    }
    if (!defined($player)) {
        $player = stateGet('player');
    }
    if (!$player) {
        die "trn: one parameter, player number\n";
    }

    # Load the turn file
    my $file = readFile('player'.$player.'.trn');

    # Upload
    print "Submitting turn file...\n";
    my $reply = httpCall("POST /api/host.cgi HTTP/1.0\n",
                         httpBuildQuery(api_token => stateGet('apikey'),
                                        action => 'trn',
                                        data => $file));

    my $parsedReply = jsonParse($reply->{BODY});
    if ($parsedReply->{result}) {
        printf "Turn accepted for game %d, \"%s\".\n", $parsedReply->{game} || 0, $parsedReply->{name} || '?';
        print "Turn checker output:\n---------------\n$parsedReply->{output}\n---------------\n"
            if $parsedReply->{output};
    } else {
        print "++ Turn not accepted ++\n";
        print "Server answer:\n";
        foreach (sort keys %$parsedReply) {
            printf "%-20s %s\n", $_, $parsedReply->{$_};
        }
    }
}


######################################################################
#
#  State file
#
######################################################################

my %stateValues;
my %stateChanged;

sub stateLoad {
    if (open(STATE, "< c2connect.ini")) {
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
    open(OUT, "> c2connect.new") or die "ERROR: cannot create new state file c2connect.new: $!\n";
    if (open(STATE, "< c2connect.ini")) {
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
    unlink "c2connect.bak";
    rename "c2connect.ini", "c2connect.bak";
    rename "c2connect.new", "c2connect.ini" or print "WARNING: cannot rename new state file: $!\n";
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
    my $host = stateGet('api');
    my $port = 80;
    my $path = '';
    if ($host =~ s|/(.*)$||) {
        $path = $1;
    }
    if ($host =~ s/:(\d+)//) {
        $port = $1;
    }
    $head =~ s|/|/$path|;           # replace only the first slash, so GET /api/... is translated to GET /test/api/...
    $head .= "Host: $host\n";
    $head .= "Content-Length: " . length($body) . "\n";
    $head .= "Connection: close\n";
    $head .= "Content-Type: application/x-www-form-urlencoded; charset=UTF-8\n" if $body ne '';
    # $head .= "User-Agent: $0\n";
    $head =~ s/\n/\r\n/g;
    $head .= "\r\n";

    # Socket cruft
    print "Calling server...\n";
    my $ip = inet_aton($host) or die "ERROR: unable to resolve host '$host': $!\n";
    my $paddr = sockaddr_in($port, $ip);
    socket(HTTP, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "ERROR: unable to create socket: $!\n";
    binmode HTTP;
    HTTP->autoflush(1);
    connect(HTTP, $paddr) or die "ERROR: unable to connect to '$host': $!\n";

    #print "\033[36m$head$body\033[0m\n";

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

    # Body might be compressed; decompress it [as of 2023, not relevant for PCc, but eventually planned for large replies]
    if (exists $reply{'content-encoding'} && lc($reply{'content-encoding'}) eq 'gzip') {
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
        $s
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


######################################################################
#
#  Utilities
#
######################################################################

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
