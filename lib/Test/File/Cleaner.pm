package Test::File::Cleaner;

=pod

=head1 NAME

Test::File::Cleaner - Automatically clean up your filesystem after tests

=head1 SYNOPSIS

  # Create the cleaner
  my $Cleaner = Test::File::Cleaner->new( 'file_dmz' );
  
  # Do some tests that create files
  touch 'file_dmz/foo';
  
  # Cleaner cleans when it is DESTROYed
  exit();
  
  # Alternatively, force an immediate clean up
  $Cleaner->clean;

=head1 DESCRIPTION

When writing file-related testing code, it is common to end up with a number
of files scattered all over the testing directories. If you are running the
test scripts over and over these leftover files can interfere with subsequent
test runs, and so they need to be cleaned up.

This clean up code typically needs to be done at END-time, so that the files
are cleaned up even if you break out of the test script while it is running.
The code to do this can get long and is labourious to maintain.

Test::File::Cleaner attempts to solve this problem. When you create a
Cleaner object for a particular directory, the object scans and saves the
contents of the directory.

When the object is DESTROYed, it compares the current state to the original,
and removes any new files and directories created during the testing process.

=head1 METHODS

=cut

use strict;
use UNIVERSAL 'isa';
use File::Spec       ();
use File::stat       ();
use File::Basename   ();
use File::Find::Rule ();

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.01';
}






#####################################################################
# Constructor

=pod

=head2 new $dir

Creates a new Test::File::Cleaner object, which will automatically clean
when it is destroyed. The cleaner is passed a directory within which it
will operate, which must exist.

Since this is intended to be used in test scripts, it will die on error.
You will not need to test the return value.

=cut

sub new {
	my $class  = ref $_[0] || $_[0];
	my $path   = -d $_[1] ? $_[1] : die "Test::File::Cleaner->new was not passed a directory";

	# Create the basic object
	my $self = bless {
		alive  => 1,
		path   => $path,
		state  => {},
		}, $class;

	# Populate the state
	$self->reset;

	$self;
}

# Clean up when we are destroyed
sub DESTROY {
	my $self = shift;
	return 1 unless $self->{alive};
	$self->clean;
	delete $self->{alive};
}



#####################################################################
# Main Methods

=pod

=head2 path

The C<path> accessor returns the current root path for the object.
The root path cannot be changed once the Test::File::Cleaner object has
been created.

=cut

sub path { $_[0]->{path} }

=pod

=head2 clean

Calling the C<clean> method forces a clean of the directory. The Cleaner
will scan it's directory, compare what it finds with it's original scan,
and then do whatever is needed to restore the directory to it's original
state.

Returns true if the Cleaner fully restores the directory, or false
otherwise.

=cut

sub clean {
	my $self = shift;

	# Fetch the new file list
	my @files = File::Find::Rule->in( $self->path );

	# Sort appropriately.
	# In this case, we MUST do files first because we arn't going to
	# be doing recursive delete of directories, and they must be clear
	# of files first.
	# We also want to be working bottom up, to help reduce the logic
	# complexity of the tests below.
	foreach ( @files ) {
		my $dir = -d $_ ? $_ : File::Basename::dirname $_;
		$_ = [ $_, -d $_, scalar File::Spec->splitdir($dir) ];
	}
	@files = map { $_->[0] }
		sort {
			$a->[1] <=> $b->[1] # Files first
			or
			$b->[2] <=> $a->[2] # Depth first
			or
			$a->[0] cmp $b->[0] # Alphabetical otherwise
		}
		@files;

	# Iterate over the files
	foreach my $file ( @files ) {
		# If it existed before, restore it's state
		my $State = $self->{state}->{$file};
		if ( $State ) {
			$State->clean;
			next;
		}

		# Was this already deleted some other way within this loop?
		next unless -e $file;

		# This file didn't exist before, delete it.
		$State = Test::File::Cleaner::State->new( $file )
			or die "Failed to get a state handle for '$file'";
		$State->remove;
	}

	1;
}

=pod

=head2 reset

The C<reset> method assumes you want to keep any changes that have been
made, and will rescan the directory and store the new state instead.

Returns true of die on error

=cut

sub reset {
	my $self = shift;

	# Catalogue the existing files
	my %state = ();
	foreach my $file ( File::Find::Rule->in($self->path) ) {
		$state{$file} = Test::File::Cleaner::State->new($file)
			or die "Failed to create state object for '$file'";
	}

	# Save the state
	$self->{state} = \%state;

	1;
}





#####################################################################
package Test::File::Cleaner::State;

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.01';
}

=pod

=head1 Test::File::Cleaner::State

A Test::File::Cleaner::State object stores the state information for a single
file or directory, and performs tasks to restore old states.

=head2 new $file

Creates a new State object for a given file name. The file or directory must
exist.

Returns a new Test::File::Cleaner::State object, or dies on error.

=cut

sub new {
	my $class = ref $_[0] || $_[0];
	my $path  = -e $_[1] ? $_[1]
		: die "Tried to create $class object for non-existant file '$_[1]'";
	my $Stat = File::stat::stat $path
		or die "Failed to get a stat on '$path'";

	# Create the basic object
	bless {
		path => $path,
		dir  => -d $path,
		Stat => $Stat,
		}, $class;
}





#####################################################################
# Accessors

=pod

=head2 path

Returns the path of the file

=head2 dir

Returns true if the state object is a directory

=head2 Stat

Returns the L<File::stat> object for the file

=head2 mode

Returns the permissions mode for the file/directory

=cut

sub path { $_[0]->{path} }

sub dir  { $_[0]->{dir}  }

sub Stat { $_[0]->{Stat} }

sub mode {
	my $mode = $_[0]->{Stat}->mode;
	return undef unless defined $mode;
	$mode & 07777;
}





#####################################################################
# Action Methods

=pod

=head2 clean

Cleans the state object, by examining the new state of the file, and
reverting it to the old one if possible.

=cut

sub clean {
	my $self = shift;
	my $term = $self->dir ? "directory" : "file";
	my $path = $self->{path};

	# Does the file/dir still exist
	die "The original $term '$path' no longer exists" unless -e $path;

	# Is it still a file/directory?
	my $dir  = -d $path;
	unless ( $dir eq $self->dir ) {
		die "File/directory mismatch for '$path'";
	}

	# Do we care about modes
	my $mode = $self->mode;
	return 1 unless defined $mode;

	# Yes, has the mode changed?
	my $mode2 = File::stat::stat($path)->mode & 07777;
	unless ( $mode == $mode2 ) {
		# Revert the permissions to match the old one
		printf "# chmod 0%lo %s\n", $mode, $path;
		chmod $mode, $path or die "Failed to correct permissions mode for $term '$path'";
	}

	1;
}

=pod

=head2 remove

The C<remove> method deletes a file for which we are holding a state. The
reason we provide a special method for this is that in some situations, a
file permissions may not allow us to remove it, and thus we may need to
correct it's permissions first.

=cut

sub remove {
	my $self = shift;
	my $term = $self->dir ? "directory" : "file";
	my $path = $self->{path};

	# Already removed?
	return 1 unless -e $path;

	# Write permissions means delete permissions
	unless ( -w $path ) {
		# Try to give ourself write permissions
		if ( $self->dir ) {
			print "# chmod 0777 $path\n";
			chmod 0777, $path or die "Failed to get enough permissions to delete $term '$path'";
		} else {
			print "# chmod 0666 $path\n";
			chmod 0666, $path or die "Failed to get enough permissions to delete $term '$path'";
		}
	}

	# Now attempt to delete it
	if ( $self->dir ) {
		print "# rmdir $path\n";
		rmdir $path or die "Failed to delete $term '$path'";
	} else {
		print "# rm $path\n";
		unlink $path or die "Failed to delete $term '$path'";
	}

	1;
}

1;

=pod

=head1 SUPPORT

Bugs should be submitted via the CPAN bug tracker, located at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test%3A%3AFile%3A%3ACleaner>

For other issues, contact the author.

=head1 AUTHOR

Adam Kennedy (Maintainer), L<http://ali.as/>, cpan@ali.as

=head1 COPYRIGHT

Thank you to Phase N Australia (L<http://phase-n.com/>) for permitted the
open sourcing and release of this distribution as a spin-off from a
commercial project.

Copyright (c) 2004 Adam Kennedy. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
