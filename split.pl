#!/usr/bin/perl -w
use strict;

my %preprocessorSymbols;
my %usedSubs;
foreach (@ARGV) {
    if (/^-D(.*?)=(.*)/) {
        $preprocessorSymbols{$1} = $2
    } else {
        die "invalid parameter: $_";
    }
}

# Read file into , process options
my $preprocessorState = 0;
while (<STDIN>) {
    if (/^\#if (.*)/) {
        my $expr = $1;
        $expr =~ s/(\w+)/exists($preprocessorSymbols{$1}) ? $preprocessorSymbols{$1} : "0"/eg;
        $preprocessorState <<= 1;
        if (!eval($expr)) {
            $preprocessorState |= 1
        }
    } elsif (/^\#else/) {
        $preprocessorState ^= 1;
    } elsif (/^\#end/) {
        $preprocessorState >>= 1;
    } elsif (/^\#autosplit/) {
        if ($preprocessorState) {
            # we are disabled, so just record that we need an end
            $preprocessorState <<= 1
        } else {
            # process autosplit region
            processAutosplit();
        }
    } else {
        if ($preprocessorState) {
            # disabled, do nothing
        } else {
            # enabled, output
            scanUsedSubs($_);
            print;
        }
    }
}


sub processAutosplit {
    # List of sections. Each is
    # { type => 'comment', 'blank', 'sub', 'code'
    #   used => 0/1,
    #   name => (for subs)
    #   content => string }
    my @sections;
    my $insub = 0;
    while (<STDIN>) {
        if (/^\#end/) { last }
        if ($insub) {
            $sections[-1]{content} .= $_;
            if (/^\}/) {
                $insub = 0;
            }
        } else {
            if (/^sub\s+(\w+)/) {
                push @sections, { type=>'sub', used=>0, name=>$1, content=>$_ };
                $insub = 1;
            } else {
                my $what = /^\#/ ? 'comment' : /^\s*$/ ? 'blank' : 'code';
                push @sections, { type=>$what, used=>0, content=>"" } unless @sections && $sections[-1]{type} eq $what;
                $sections[-1]{content} .= $_;
            }
        }
    }

    # Mark all code used
    foreach (@sections) {
        if ($_->{type} eq 'code') {
            $_->{used} = 1
        }
    }

    # Mark all used subs used
    while (1) {
        my $did = 0;
        foreach (@sections) {
            if ($_->{type} eq 'sub' && $_->{used} == 0 && exists($usedSubs{$_->{name}})) {
                $_->{used} = 1;
                foreach my $x (split /\n/, $_->{content}) {
                    scanUsedSubs($x);
                }
                $did = 1;
            }
        }
        last if !$did;
    }

    # Mark all comments used that precede a used sub; also box comments that precede a section.
    my $any = 0;
    for (my $i = $#sections-1; $i >= 0; --$i) {
        if ($sections[$i]{used}) {
            # It's used, so just mark.
            $any = 1
        } else {
            # Not used. Any reason it should be?
            if ($sections[$i+1]{used} && ($sections[$i]{type} eq 'comment' || $sections[$i]{type} eq 'blank')) {
                # This is a comment or blank, and our successor is used
                $sections[$i]{used} = 1
            }
            if ($sections[$i]{type} eq 'comment' && $sections[$i]{content} =~ /^#####/) {
                # This is a box comment, and we had anything in the section below it
                if ($any) {
                    $sections[$i]{used} = 1
                }
                $any = 0;
            }
        }
    }

    # Print result
    foreach (@sections) {
        if ($_->{used}) {
            print $_->{content}
        }
    }
}


sub scanUsedSubs {
    my $s = shift;
    pos($s) = 0;
    while (1) {
        if ($s =~ m!\G'([^\\\']|\\.)*'!gc) {
            # quote
        } elsif ($s =~ m!\G"([^\\\"]|\\.)*"!gc) {
            # quote
        } elsif ($s =~ m|\G\#.*|gc || $s =~ m|\G$|gc) {
            last
        } elsif ($s =~ m|\G\W+|gc) {
            # nonword
        } elsif ($s =~ m|\G(\w+)|gc) {
            # word
            $usedSubs{$1} = 1
        } else {
            # what?
            die "unable to parse: " . substr($s, pos($s));
        }
    }
}
