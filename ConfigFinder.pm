package App::Ack::ConfigFinder;

=head1 App::Ack::ConfigFinder

=head1 LOCATING CONFIG FILES

First, ack looks for a global ackrc.

=over

=item On Windows, this is `ackrc` in either COMMON_APPDATA or APPDATA.
If `ackrc` is present in both directories, ack uses both files in that
order.

=item On a non-Windows OS, this is `/etc/ackrc`.

=back

Then, ack looks for a user-specific ackrc if the HOME environment
variable is set.  This is either `$HOME/.ackrc` or `$HOME/_ackrc`.

Then, ack looks for a project-specific ackrc file.  ack searches
up the directory hierarchy for the first `.ackrc` or `_ackrc` file.
If this is one of the ackrc files found in the previous steps, it is
not loaded again.

It is a fatal error if a directory contains both `.ackrc` and `_ackrc`.

After ack loads the options from the found ackrc files, ack looks
at the ACKRC_OPTIONS environment variable.

Finally, ack takes settings from the command line.

=cut

use strict;
use warnings;

use App::Ack ();
use App::Ack::ConfigDefault;
use Cwd 3.00 ();
use File::Spec 3.00;

use if ($^O eq 'MSWin32'), 'Win32';

=head1 METHODS

=head2 new

Creates a new config finder.

=cut

sub new {
    my ( $class ) = @_;

    return bless {}, $class;
}

sub _remove_redundancies {
    my ( @configs ) = @_;

    if ( $App::Ack::is_windows ) {
        # inode stat always returns 0 on windows, so just check filenames.
        my (%seen, @uniq);

        foreach my $path (map { $_->{path} } @configs) {
            push @uniq, $path unless $seen{$path};
            $seen{$path} = 1;
        }

        return @uniq;
    }

    else {

        my %dev_and_inode_seen;

        foreach my $config ( @configs ) {
            my $path = $config->{path};
            my ( $dev, $inode ) = (stat $path)[0, 1];

            if( defined($dev) ) {
                if( $dev_and_inode_seen{"$dev:$inode"} ) {
                    undef $config;
                }
                else {
                    $dev_and_inode_seen{"$dev:$inode"} = 1;
                }
            }
        }

        return grep { defined() } @configs;

    }
}

sub _check_for_ackrc {
    return unless defined $_[0];

    my @files = grep { -f }
                map { File::Spec->catfile(@_, $_) }
                qw(.ackrc _ackrc);

    die File::Spec->catdir(@_) . " contains both .ackrc and _ackrc.\n" .
        "Please remove one of those files.\n"
            if @files > 1;

    return wantarray ? @files : $files[0];
} # end _check_for_ackrc

=head2 $finder->find_config_files

Locates config files, and returns a list of them.

=cut

sub find_config_files {
    my @config_files;

    if ( $App::Ack::is_windows ) {
        push @config_files, map { +{ path => File::Spec->catfile($_, 'ackrc') } } (
            Win32::GetFolderPath(Win32::CSIDL_COMMON_APPDATA()),
            Win32::GetFolderPath(Win32::CSIDL_APPDATA()),
        );
    }
    else {
        push @config_files, { path => '/etc/ackrc' };
    }


    if ( $ENV{'ACKRC'} && -f $ENV{'ACKRC'} ) {
        push @config_files, { path => $ENV{'ACKRC'} };
    }
    else {
        push @config_files, map { +{ path => $_ } } _check_for_ackrc($ENV{'HOME'});
    }

    my @dirs = File::Spec->splitdir(Cwd::getcwd());
    while(@dirs) {
        my $ackrc = _check_for_ackrc(@dirs);
        if(defined $ackrc) {
            push @config_files, { project => 1, path => $ackrc };
            last;
        }
        pop @dirs;
    }

    # XXX we only test for existence here, so if the file is
    #     deleted out from under us, this will fail later. =(
    return _remove_redundancies( @config_files );
}

=head2 read_rcfile

Reads the contents of the .ackrc file and returns the arguments.

=cut

sub read_rcfile {
    my $file = shift;

    return unless defined $file && -e $file;

    my @lines;

    open( my $fh, '<', $file ) or App::Ack::die( "Unable to read $file: $!" );
    while ( my $line = <$fh> ) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;

        next if $line eq '';
        next if $line =~ /^#/;

        push( @lines, $line );
    }
    close $fh;

    return @lines;
}

1;
