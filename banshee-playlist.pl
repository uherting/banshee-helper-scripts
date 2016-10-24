#! /usr/bin/env perl
# create m3u file for banshee playlist
use warnings;
use strict;

use DBI;
use File::Basename;
use Getopt::Long;
use IO::File;
use Pod::Usage;
use URI::Escape;

my $pkg = 'banshee-playlist';
my $version = '0.3';

my $db = "$ENV{HOME}/.config/banshee-1/banshee.db";
my ($export, $list, $quiet);
unless (GetOptions(help => sub { &pod2usage(-exitval => 0) },
                   'db=s' => \$db,
                   export => \$export,
                   list => \$list,
                   quiet => \$quiet,
                   version => sub { print "$pkg $version\n"; exit(0) }
                  ))
{
    warn("Try `$pkg --help' for more information.\n");
    exit(1);
}

# connect to database
die("$pkg: banshee database does not exist or is not readable")
    unless (-f $db && -r $db);
my $dbh = DBI->connect("dbi:SQLite:dbname=$db", '', '',
                       { RaiseError => 1, AutoCommit => 0 });

# see what user wants
if ($list) {
    &list_playlists($dbh);
}
else {
    # &get_list($dbh, $playlist, $export);
    &get_list($dbh, $export);
}

$dbh->disconnect;

exit(0);

# list the playlists
sub list_playlists {
    my ($dbh) = @_;

    my $list_q = q(select PlaylistID, Name from CorePlaylists where PrimarySourceID = 1 union select SmartPlaylistID as PlaylistID, Name from CoreSmartPlaylists where PrimarySourceID = 1);
    my $list_s = $dbh->prepare($list_q);

    $list_s->execute();
    while (my $row = $list_s->fetchrow_arrayref) {
        my ($id, $name) = @$row;
        print("$name\n");
    }

    return;
}

sub get_list {
    #my ($dbh, $playlist, $export) = @_;
    my ($dbh, $export) = @_;

    my $list_q = q(select PlaylistID, Name from CorePlaylists where PrimarySourceID = 1 union select SmartPlaylistID as PlaylistID, Name from CoreSmartPlaylists where PrimarySourceID = 1);
    my $list_s = $dbh->prepare($list_q);

    $list_s->execute();
    while (my $row = $list_s->fetchrow_arrayref) {
        my ($id, $name) = @$row;
        
	my($playlist) = $name;
	print("$pkg: export playlist $playlist\n") unless $quiet;

	# prep query
	my $track_q = q(
	select 
		t.Uri, e.ViewOrder as ViewOrderTmp, a.Name, 
		t.Title, t.TrackNumber, l.Title, 
		t.Year, t.Genre, t.Duration/1000, e.EntryID as EntryIDTmp
	from CorePlaylists as p
	join CorePlaylistEntries as e on e.PlaylistID = p.PlaylistID
	join CoreTracks as t on t.TrackID = e.TrackID
	join CoreArtists as a on a.ArtistID = t.ArtistID
	join CoreAlbums as l on l.AlbumID = t.AlbumID
	where 
		p.PrimarySourceID = 1 
		AND p.Name = ?
	union
	select 
		t.Uri, 1 as ViewOrderTmp, a.Name, 
		t.Title, t.TrackNumber, l.Title, 
		t.Year, t.Genre, t.Duration/1000, EntryID as EntryIDTmp
	from CoreSmartPlaylists as p
	join CoreSmartPlaylistEntries as e on e.SmartPlaylistID = p.SmartPlaylistID
	join CoreTracks as t on t.TrackID = e.TrackID
	join CoreArtists as a on a.ArtistID = t.ArtistID
	join CoreAlbums as l on l.AlbumID = t.AlbumID
	where 
		p.PrimarySourceID = 1 
		AND p.Name = ?
	order by ViewOrderTmp, EntryIDTmp
	);
	my $track_s = $dbh->prepare($track_q);

	# execute query
	$track_s->execute($playlist, $playlist);

	# open m3u file
	my $m3u = IO::File->new(">$playlist.m3u");
	die "$pkg: failed to open m3u file: $!" unless defined($m3u);
	$m3u->print("#EXTM3U\n");

	# get tracks and start loop
	while (my $row = $track_s->fetchrow_arrayref) {
	my (%track);
	@track{qw(uri order artist title tracknumber album year genre duration)} = @$row;
	my $path = $track{uri};
	$path =~ s,^file://,,;
	$path = uri_unescape($path);
	#$path =~ s# #\\ #g;
	if (! -f $path) {
	    warn("$pkg: file does not exist: '$path'\n");
	}
	if ($export) {
	    my $rv = &export_file($path, %track);
	    if (!$rv) {
		warn("$pkg: failed to export file: $path");
	    }
	    else {
		$path = $rv;
	    }
	}
#warn("$pkg: URI: $track{uri}");
	$m3u->print("#EXTINF:$track{duration},$track{artist} - $track{title}\n");
	$m3u->print("$path\n");
	}

	$m3u->close;
    }
}

# export music files
sub export_file {
    my ($path, %track) = @_;

    # parse file path
    my @exts = qw(.mp3 .ogg .flac .m4a .wma .mp4 .MP3);
    my ($base, $dir, $suffix) = fileparse($path, @exts);
    if (!$suffix) {
        warn("$pkg: unknown suffix: $path");
        return;
    }
    my $wav = "$base.wav";
    my $mp3 = "$base.mp3";
    
    $path =~ s/\/home\/devusruh\///g;
    #print("$pkg: export $path\n") unless $quiet;

    return $path;
}

__END__

=pod

=head1 NAME

banshee-playlist - list contents of banshee playlists

=head1 SYNOPSIS

B<banshee-playlist> [OPTIONS]... [PLAYLIST]

=head1 DESCRIPTION

This programs reads a Banshee database and outputs playlist
information.  It can create an m3u file for a PLAYLIST (the default),
list the available playlists, and optionally export the song music
files from a playlist.

=head1 OPTIONS

If an argument to a long option is mandatory, it is also mandatory for
the corresponding short option; the same is true for optional arguments.

=over 4

=item --db=PATH

Use PATH for banshee database rather than the default,
C<~/.config/banshee-1/banshee.db>.

=item --export

Write the m3u file and export the music files as LAME-encoded medium
quality MP3 files in the current directory.

=item --help

Display a brief description and listing of all available options.

=item --list

List the banshee playlists.

=item --version

Output version information and exit.

=item --

Terminate option processing.  This option is useful when file names
begin with a dash (-).

=back

=head1 EXAMPLES

To get a list of the playlists in banshee, run

  $ banshee-playlist --list

To write an m3u file for playlist Workout and export the song files to
the current directory, run

  $ banshee-playlist --export Workout

=head1 BUGS

Please email the author if you identify a bug.

=head1 SEE ALSO

sqlite3(1), banshee(1)

=head1 AUTHOR

David Dooling <banjo@users.sourceforge.net>

=cut
