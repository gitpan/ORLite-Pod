package ORLite::Pod;

=pod

=head1 NAME

ORLite::Pod - Documentation generator for ORLite

=head1 SYNOPSIS

  orlite2pod Class::Name

=head1 DESCRIPTION

I<This initial release is intended to test whether or not search.cpan.org
gets confused by the heredoc POD fragments in this file. Use of this
module is not recommended for any users at this time>

B<THIS MODULE IS EXPERIMENTAL AND SUBJECT TO CHANGE WITHOUT NOTICE.>

B<YOU HAVE BEEN WARNED!>

The biggest downside of L<ORLite> is that because it can generate you
an entire ORM in one line of code, you can have a large an extensive
API without anywhere for documentation for the API to exist.

The result is quick efficient creation of APIs that nobody can
understand or use :)

B<ORLite::Pod> was created to fix this problem by allowing you to keep
your slimline Perl module as is, but generating a tree of .pod files
alongside the regular modules containing the documentation for the API.

B<ORLite::Pod> connects directly to a loaded ORLite instance,
interrogating it to find the database it connects to, and discovering
which tables have or don't have classes generated for them.

TO BE COMPLETED

=head1 METHODS

=cut

use 5.006;
use strict;
use Carp         ();
use File::Spec   ();
use Params::Util qw{_CLASS};
use ORLite       ();

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.02';
}





#####################################################################
# Constructor and Accessors

sub new {
	my $class = shift;
	my $self  = bless { @_ }, $class;

	# Check params
	unless (
		_CLASS($self->from)
		and
		$self->from->can('orlite')
	) {
		die("Did not provide a 'from' ORLite root class to generate from");
	}
	my $to = $self->to;
	unless ( $self->to ) {
		die("Did not provide a 'to' lib directory to write into");
	}
	unless ( -d $self->to ) {
		die("The 'to' lib directory '$to' does not exist");
	}
	unless ( -w $self->to ) {
		die("No permission to write to directory '$to'");
	}

	return $self;
}

sub from {
	$_[0]->{from};
}

sub to {
	$_[0]->{to};
}





#####################################################################
# POD Generation

sub run {
	my $self = shift;
	my $pkg  = $self->from;

	# Capture the raw schema information
	print( "Analyzing " . $pkg->dsn . "...\n" );
	my $dbh  = $pkg->dbh;
	my $tables = $dbh->selectall_arrayref(
		'select * from sqlite_master where type = ?',
		{ Slice => {} }, 'table',
	);
	foreach my $table ( @$tables ) {
		$table->{columns} = $dbh->selectall_arrayref(
			"pragma table_info('$table->{name}')",
		 	{ Slice => {} },
		);
	}

	# Generate the main additional table level metadata
	my %tindex = map { $_->{name} => $_ } @$tables;
	foreach my $table ( @$tables ) {
		my @columns      = @{ $table->{columns} };
		my @names        = map { $_->{name} } @columns;
		$table->{cindex} = map { $_->{name} => $_ } @columns;

		# Discover the primary key
		$table->{pk}     = List::Util::first { $_->{pk} } @columns;
		$table->{pk}     = $table->{pk}->{name} if $table->{pk};

		# What will be the class for this table
		$table->{class}  = ucfirst lc $table->{name};
		$table->{class}  =~ s/_([a-z])/uc($1)/ge;
		$table->{class}  = "${pkg}::$table->{class}";

		# Generate various SQL fragments
		my $sql = $table->{sql} = { create => $table->{sql} };
		$sql->{cols}     = join ', ', map { '"' . $_ . '"' } @names;
		$sql->{vals}     = join ', ', ('?') x scalar @columns;
		$sql->{select}   = "select $table->{sql}->{cols} from $table->{name}";
		$sql->{count}    = "select count(*) from $table->{name}";
		$sql->{insert}   = join ' ',
			"insert into $table->{name}" .
			"( $table->{sql}->{cols} )"  .
			" values ( $table->{sql}->{vals} )";
	}

	# Generate the foreign key metadata
	foreach my $table ( @$tables ) {
		# Locate the foreign keys
		my %fk     = ();
		my @fk_sql = $table->{sql}->{create} =~ /[(,]\s*(.+?REFERENCES.+?)\s*[,)]/g;

		# Extract the details
		foreach ( @fk_sql ) {
			unless ( /^(\w+).+?REFERENCES\s+(\w+)\s*\(\s*(\w+)/ ) {
				die "Invalid foreign key $_";
			}
			$fk{"$1"} = [ "$2", $tindex{"$2"}, "$3" ];
		}
		foreach ( @{ $table->{columns} } ) {
			$_->{fk} = $fk{$_->{name}};
		}
	}

	# Generate the root module .pod file
	$self->write_root( $tables );

	# Generate the table .pod files
	foreach my $table ( @$tables ) {
		# Skip tables we aren't modelling
		next unless $table->{class}->can('new');

		# Generate the table-specific file
		$self->write_table( $tables, $table );
	}

	return 1;
}





#####################################################################
# Generation of Base Documentation

sub write_root {
	my $self   = shift;
	my $tables = shift;

	# Determine the file we're going to be writing to
	my $pkg = $self->from;
	my $file = File::Spec->catfile(
		$self->to,
		 split( /::/, $pkg )
	) . '.pod';

	# Start writing the file
	print "Generating $file...\n";
	local *FILE;
	open( FILE, '>', $file ) or die "open: $!";
	_print( <<"END_POD" );
|=head1 NAME
|
|$pkg - An ORLite-based ORM Database API
|
|=head1 SYNOPSIS
|
|  TO BE COMPLETED
|
|=head1 DESCRIPTION
|
|TO BE COMPLETED
|
|=head1 METHODS
|
END_POD



	# Add pod for each method that is defined
	_print( <<"END_POD" ) if $pkg->can('dsn');
|=head2 dsn
|
|  my \$string = Foo::Bar->dsn;
|
|The C<dsn> accessor returns the dbi connection string used to connect
|to the SQLite database as a string.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('dbh');
|=head2 dbh
|
|  my \$handle = Foo::Bar->dbh;
|
|To reliably prevent potential SQLite deadlocks resulting from multiple
|connections in a single process, each ORLite package will only ever
|maintain a single connection to the database.
|
|During a transaction, this will be the same (cached) database handle.
|
|Although in most situations you should not need a direct DBI connection
|handle, the C<dbh> method provides a method for getting a direct
|connection in a way that is compatible with ORLite's connection
|management.
|
|Please note that these connections should be short-lived, you should
|never hold onto a connection beyond the immediate scope.
|
|The transaction system in ORLite is specifically designed so that code
|using the database should never have to know whether or not it is in a
|transation.
|
|Because of this, you should B<never> call the -E<gt>disconnect method
|on the database handles yourself, as the handle may be that of a
|currently running transaction.
|
|Further, you should do your own transaction management on a handle
|provided by the <dbh> method.
|
|In cases where there are extreme needs, and you B<absolutely> have to
|violate these connection handling rules, you should create your own
|completely manual DBI-E<gt>connect call to the database, using the connect
|string provided by the C<dsn> method.
|
|The C<dbh> method returns a L<DBI::db> object, or throws an exception on
|error.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('begin');
|=head2 begin
|
|  Foo::Bar->begin;
|
|The C<begin> method indicates the start of a transaction.
|
|In the same way that ORLite allows only a single connection, likewise
|it allows only a single application-wide transaction.
|
|No indication is given as to whether you are currently in a transaction
|or not, all code should be written neutrally so that it works either way
|or doesn't need to care.
|
|Returns true or throws an exception on error.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('commit');
|=head2 commit
|
|  Foo::Bar->commit;
|
|The C<commit> method commits the current transaction. If called outside
|of a current transaction, it is accepted and treated as a null operation.
|
|Once the commit has been completed, the database connection falls back
|into auto-commit state. If you wish to immediately start another
|transaction, you will need to issue a separate -E<gt>begin call.
|
|Returns true or throws an exception on error.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('rollback');
|=head2 rollback
|
|The C<rollback> method rolls back the current transaction. If called outside
|of a current transaction, it is accepted and treated as a null operation.
|
|Once the rollback has been completed, the database connection falls back
|into auto-commit state. If you wish to immediately start another
|transaction, you will need to issue a separate -E<gt>begin call.
|
|If a transaction exists at END-time as the process exits, it will be
|automatically rolled back.
|
|Returns true or throws an exception on error.
|
|=head2 do
|
|  Foo::Bar->do('insert into table (foo, bar) values (?, ?)', {},
|      \$foo_value,
|      \$bar_value,
|  );
|
|The C<do> method is a direct wrapper around the equivalent L<DBI> method,
|but applied to the appropriate locally-provided connection or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('selectall_arrayref');
|=head2 selectall_arrayref
|
|The C<selectall_arrayref> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('selectall_hashref');
|=head2 selectall_hashref
|
|The C<selectall_hashref> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('selectcol_arrayref');
|=head2 selectcol_arrayref
|
|The C<selectcol_arrayref> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('selectrow_array');
|=head2 selectrow_array
|
|The C<selectrow_array> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('selectrow_arrayref');
|=head2 selectrow_arrayref
|
|The C<selectrow_arrayref> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('selectrow_hashref');
|=head2 selectrow_hashref
|
|The C<selectrow_hashref> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction.
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('prepare');
|=head2 prepare
|
|The C<prepare> method is a direct wrapper around the equivalent
|L<DBI> method, but applied to the appropriate locally-provided connection
|or transaction
|
|It takes the same parameters and has the same return values and error
|behaviour.
|
|In general though, you should try to avoid the use of your own prepared
|statements if possible, although this is only a recommendation and by
|no means prohibited.
|
END_POD



	_print( <<"END_POD" ) if $pkg->can('pragma');
|=head2 pragma
|
|  # Get the user_version for the schema
|  my \$version = Foo::Bar->pragma('user_version');
|
|The C<pragma> method provides a convenient method for fetching a pragma
|for a datase. See the SQLite documentation for more details.
|
END_POD

	# Add a footer
	_print( <<"END_POD" );
|=head1 SUPPORT
|
|$pkg is based on L<ORLite> $ORLite::VERSION.
|
|Documentation created by L<ORLite::Pod> $ORLite::Pod::VERSION.
|
|For general support, please see the support section of the main project
|documentation.
|
|=head1 AUTHOR
|
|Adam Kennedy E<lt>adamk\@cpan.orgE<gt>
|
|=head1 COPYRIGHT
|
|Copyright 2009 Adam Kennedy.
|
|This program is free software; you can redistribute
|it and/or modify it under the same terms as Perl itself.
|
|The full text of the license can be found in the
|LICENSE file included with this module.
|
END_POD

	close FILE;
	return 1;
}





#####################################################################
# Generation of Table-Specific Documentation

sub write_table {
	my $self   = shift;
	my $tables = shift;
	my $table  = shift;

	# Determine the file we're going to be writing to
	my $root = $self->from;
	my $pkg  = $table->{class};
	my $file = File::Spec->catfile(
		$self->to,
		 split( /::/, $pkg )
	) . '.pod';

	# Start writing the file
	print "Generating $file...\n";
	local *FILE;
	open( FILE, '>', $file ) or die "open: $!";
	_print( <<"END_POD" );
|=head1 NAME
|
|$pkg - $root class for the $table->{name} table
|
|=head1 SYNOPSIS
|
|  TO BE COMPLETED
|
|=head1 DESCRIPTION
|
|TO BE COMPLETED
|
|=head1 METHODS
|
END_POD

	_print( <<"END_POD" ) if $pkg->can('select');
|=head2 select
|
|  # Get all objects in list context
|  my \@list = $pkg->select;
|  
|  # Get a subset of objects in scalar context
|  my \$array_ref = $pkg->select(
|      'where $table->{pk} > ? order by $table->{pk}',
|      1000,
|  );
|
|The C<select> method executes a typical SQL C<SELECT> query on the
|$table->{name} table.
|
|It takes an optional argument of a SQL phrase to be added after the
|C<FROM $table->{name}> section of the query, followed by variables
|to be used for any placeholders in the conditions. Any SQL that is
|compatible with SQLite can be used in the parameter.
|
|Returns a list of B<$pkg> objects when called in list context, or a
|reference to an ARRAY of B<$pkg> objects when called in scalar context.
|
|Throws an exception on error, typically directly from the L<DBI> layer.
|
END_POD

	_print( <<"END_POD" ) if $pkg->can('count');
|=head2 count
|
|  # How many objects are in the table
|  my \$rows = $pkg->count;
|  
|  # How many objects 
|  my \$small = $pkg->count(
|      'where $table->{pk} > ?',
|      1000,
|  );
|
|The C<count> method executes a C<SELECT COUNT(*)> query on the
|$table->{name} table.
|
|It takes an optional argument of a SQL phrase to be added after the
|C<FROM $table->{name}> section of the query, followed by variables
|to be used for any placeholders in the conditions. Any SQL that is
|compatible with SQLite can be used in the parameter.
|
|Returns the number of objects that match the condition.
|
|Throws an exception on error, typically directly from the L<DBI> layer.
|
END_POD


	# Add a footer
	_print( <<"END_POD" );
|=head1 SUPPORT
|
|$pkg is part of the L<$root> API.
|
|See the documentation for L<$root> for more information.
|
|=head1 AUTHOR
|
|Adam Kennedy E<lt>adamk\@cpan.orgE<gt>
|
|=head1 COPYRIGHT
|
|Copyright 2009 Adam Kennedy.
|
|This program is free software; you can redistribute
|it and/or modify it under the same terms as Perl itself.
|
|The full text of the license can be found in the
|LICENSE file included with this module.
|
END_POD

	close FILE;
	return 1;
}





#####################################################################
# Support Functions

sub _print {
	my $string = shift;
	$string =~ s/^\|//gm;
	print FILE $string;
}

1;

=pod

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=ORLite-Pod>

For other issues, contact the author.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2009 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
