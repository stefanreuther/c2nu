# c2nu
planets.nu to PCC2 adapter

This is a perl program to interface to the planets.nu VGAP host and produce
result files for use with [PCC2](http://phost.de/~stefan/pcc2.html)
(and other client programs, such as [VPA](http://vpa.sourceforge.net/)
or [PCC 1.x](http://phost.de/~stefan/pcc.html)).

It can download result files and upload turn files, allowing you to play
planets.nu on your local computer.


## Preconditions and Installation

*c2nu* is written in Perl and therefore requires a Perl interpreter.
It requires the *gzip* program to decompress network data.
Other than that, it has no external dependencies other than Perl standard modules.
In particular, all network protocols are implemented internally.

*c2nu* does not require a formal installation procedure.
Just drop the script somewhere convenient.


## Quickstart

* Make a new directory and open a command prompt in it.
* Make a solo game on planets.nu.
* Use `perl c2nu.pl login USER PASSWORD` to log in.
* Use `perl c2nu.pl list` to obtain a list of your games.
* Use `perl c2nu.pl unpack N` to fetch data for game N.
* Play the game using PCC2, VPA, etc.
* Use `perl c2nu.pl maketurn` to upload the turn file.
* Use `perl c2nu.pl runhost` to run the host.
* Repeat from the `unpack` step as needed.


## Usage

*c2nu* stores some persistent state in a file `c2nu.ini` in the current directory.
This file includes the login credentials and the game number.
Therefore, you typically invoke *c2nu* from a diffent directory for each game
(like you would do for regular v3 programs).

*c2nu* is invoked as follows:

    perl c2nu.pl [--global-options] command [arguments...]

Global options can precede any command:


* `--api=host`

  Set the host name of the planets.nu API server.
  The default is `api.planets.nu`.

  This setting is saved in the state file.

* `--backup=0|1`

  Enable or disable the creation of result file backups.
  When enabled, every downloaded result file is stored in a file `c2rst_backup_PL_TRN.txt`
  (where PL is the player number, TRN is the turn number).

  This setting is saved in the state file.

* `--dropmines=0|1`

  When enabled, *c2nu* will remove obsolete minefields from PCC's starchart database (`chartX.cc`).
  When disabled (default), old minefields will remain in the database until the user manually removes them.

  This setting is saved in the state file.

* `--root=DIR`

  Specifies the directory of a folder containing the standard VGAP files.
  This could be your planets.exe folder, PCC folder, Winplan folder, etc.

  See the `unpack` / `rst` commands for details.

* `--rst=FILE`

  Specifies the name of the file where the Nu result file is stored.
  This option can be used to unpack a previous turn's result, for example.
  See "Theory of Operation" below.

* `--trn=FILE`

  Specifies the name of the file where the Nu turn file is stored.


## Commands

Many commands consist of two halves that can be invoked separately.
One half accesses the network, whereas the other one operates locally.
For example, `unpack` consists of `unpack1` (download the data) and `unpack2` (unpack it).


### Command: `help`

Display a help screen.
Does not access the network.


### Command: `status`

Display the current state file.
Does not access the network.


### Command: `login`

    perl c2nu.pl login USERNAME PASSWORD

(yes, this means your password on the command line.)

This will log in to the server.
It obtains an API key that is stored in the state file.
Following network commands will use that API key and do not require you to provide a user name or password again.

To log out, delete the state file `c2nu.ini`.


### Command: `list`

    perl c2nu.pl list

List information about your games.
This will show the game number, name, and race for each of your games.
Use this to find out the game numbers for other commands.


### Command: `info`

    perl c2nu.pl info [--option] [GAME]

Show information about a game.
By default, shows the list of users on that game, the races they play, and their scores.

The game number can be obtained using `list`, but could also be a game you don't play in.
If no game number is given, the one from the state file is used, if any.

* `--raw`

  Show raw JSON result.


### Command: `unpack` (`unpack1`, `unpack2`)

    perl c2nu.pl unpack  [--options] [GAME [TURN]]
    perl c2nu.pl unpack1 [--options] [GAME [TURN]]
    perl c2nu.pl unpack2

This command will download a Nu result file and convert it into a set of v3 specification files
and an unpacked set of v3 data files. This is the preferred way to play with *c2nu*.

The most frequent usecase just specifies a game number:

    perl c2nu.pl unpack 123456

This will fetch the result file and also store the game number in the state file;
future invocations can then omit it:

    perl c2nu.pl unpack

Parameters can be used to download a different result than the current one.

* `--player=N`

  Download given player's result.

* `--turn=N`

  Download given turn's result. Alternatively, specify turn number as second positional parameter.

* `--game=N`

  Download this game's result. Alternatively, specify turn number as first positional parameter.

This command will create specification files (`hullspec.dat` etc.).
Not all required data is available in a Nu result file; most notably, the ship image links are missing.
The `unpack` command therefore uses preexisting specification files as templates.
Those should exist in the current directory, or in the directory specified using the `--root` global option.
If you fail to supply a `hullfunc.dat` file, your v3 client will not be able to show ship pictures.

The `unpack` command has two halves: `unpack1` to download and `unpack2` to unpack the file.
To unpack a file you already have (a backup, maybe), you would use a command such as

    perl c2nu.pl --rst=my_file unpack2


### Command: `rst` (`rst1`, `rst2`)

    perl c2nu.pl rst  [--options] [GAME [TURN]]
    perl c2nu.pl rst1 [--options] [GAME [TURN]]
    perl c2nu.pl rst2

This command will download a Nu result file and convert it into a set of v3 specification files and a v3 result file.

Options and footnotes for `rst` are the same as for `unpack`.
`rst` exists mainly for historical reasons (it was there first); `unpack` is the better way if you actually intend to play.

The `rst` command has two halves: `rst1` to download and `rst2` to create the file.


### Command: `dump` (`dump1`, `dump2`)

    perl c2nu.pl dump  [--options] [GAME [TURN]]
    perl c2nu.pl dump1 [--options] [GAME [TURN]]
    perl c2nu.pl dump2

This command will download a Nu result file and dump it to standard output in a nicely formatted way.
This is mainly a developer feature.

Options and footnotes for `dump` are the same as for `unpack`.

The `dump` command has two halves: `dump1` to download and `dump2` to display the file.

### Command: `vcr` (`vcr1`, `vcr2`)

    perl c2nu.pl vcr  [--options] [GAME [TURN]]
    perl c2nu.pl vcr1 [--options] [GAME [TURN]]
    perl c2nu.pl vcr2

This command will download a Nu result file and convert it into a set of v3 specification files and a VCR file.
This is a subset of the `unpack` command.

Options and footnotes for `vcr` are the same as for `unpack`.

The `vcr` command has two halves: `vcr1` to download and `vcr2` to create the files.


### Command: `maketurn` (`maketurn1`, `maketurn2`)

    perl c2nu.pl maketurn
    perl c2nu.pl maketurn1
    perl c2nu.pl maketurn2

This command takes an unpacked game directory as input, figures out your commands, and uploads them.
Use this after you played a turn in a directory created using `unpack`.

The `maketurn` command has two halves: `maketurn1` to generate the commands and `maketurn2` to upload them.


### Command: `runhost`

    perl c2nu.pl runhost

This command triggers the host run for a solo game.


### Command: `serve`

    perl c2nu.pl serve [--options] FILES...

This command serves a set of Nu result files via HTTP.

This is a developer feature: using `perl c2nu.pl serve --port=N FILES...`
you can provide result files for download using `perl c2nu.pl --api=127.0.0.1:N unpack`.

You can specify multiple result files (`c2rst.txt`), but they must all belong to different games.

* `--port=N`

  Provide the HTTP server on the given port (default: 8080).



## Theory of Operation

Planets.nu uses JSON data instead of v3's binary data.
Also, the data is organized a little different.

The main data structure for playing is a Nu result file which is a large JSON structure that contains everything,
specification files and your view of the universe.
The Nu server also allows access to old result files.
Because those files are self-contained, they can easily be backed-up (just one file, not `playerX.rst` plus `utilX.dat` plus `xyplanX.dat`...).

A result file also contains some undo information.
For example, it might say that you have 20 factories, and 5 of them were built this turn.
This way the client knows that it can scrap these 5 again.
This information is organized totally different in v3.

Planets.nu has some features that do not exist in v3.
Not much effort has been made to emulate this, as it requires native client support.
Therefore, *c2nu* can probably safely be used only in games with 11 standard players.
The good (or bad) news is that the server got better in validating turn files over time.



## Author Contact

Stefan Reuther, <streu@gmx.de>

Play v3 Planets on http://planetscentral.com/
