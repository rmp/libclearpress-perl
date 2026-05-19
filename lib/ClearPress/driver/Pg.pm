#########
# Author: rmp
# Created: 2006-10-31
#
package ClearPress::driver::Pg;
use strict;
use warnings;
use base qw(ClearPress::driver);
use English qw(-no_match_vars);
use Carp;
use Readonly;

our $VERSION = q[2026.05.18];

Readonly::Scalar our $TYPES => {
				'primary key' => 'bigserial PRIMARY KEY',
			       };
sub dbh {
  my $self = shift;

  if(!$self->{dbh} ||
     !$self->{dbh}->ping()) {
    my $dsn = sprintf q(DBI:Pg:database=%s;host=%s;port=%s),
		      $self->{dbname} || q[],
		      $self->{dbhost} || q[localhost],
		      $self->{dbport} || q[5432];

    eval {
      $self->{dbh} = DBI->connect($dsn,
				  $self->{dbuser} || q[],
				  $self->{dbpass},
				  {RaiseError => 1,
				   AutoCommit => 0});

    } or do {
      croak qq[Failed to connect to $dsn using '@{[$self->{dbuser}||""]}'\n$EVAL_ERROR];
    };

    #########
    # rollback any junk left behind if this is a cached handle
    #
    $self->{dbh}->rollback();
  }

  return $self->{dbh};
}

sub create {
  my ($self, $query, @args) = @_;
  my $dbh = $self->dbh();

  my ($table) = $query =~ /INTO\s+([[:alnum:]_]+)/smix;
  my ($pk)    = $query =~ /[(]([[:alnum:]_]+)/smx;

  if($pk) {
    $query .= qq[ RETURNING $pk];
  }

  my $sth = $dbh->prepare($query);
  $sth->execute(@args);
  my ($id) = $sth->fetchrow_array();
  $sth->finish();

  return $id;
}

sub create_table {
  my ($self, $table_name, $ref) = @_;
  return $self->SUPER::create_table($table_name, $ref);
}

sub types {
  return $TYPES;
}

sub bounded_select {
  my ($self, $query, $len, $start) = @_;

  if(defined $start && defined $len) {
    $query .= sprintf q[ LIMIT %d OFFSET %d], $len, $start;
  } elsif(defined $len) {
    $query .= sprintf q[ LIMIT %d], $len;
  }

  return $query;
}

1;
__END__

=head1 NAME

ClearPress::driver::Pg - Pg-specific implementation of the database abstraction layer

=head1 VERSION

$LastChangedRevision: 470 $

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 dbh - fetch a connected database handle

  my $oDBH = $oDriver->dbh();

=head2 create - run a create query and return this objects primary key

  my $iAssignedId = $oDriver->create($query)

=head2 create_table - Postgres-specific create_table

=head2 types - the whole type map

=head2 bounded_select - select limited by number of rows and first-row position

  my $bounded_select = $driver->bounded_select($unbounded_select, $rows, $start_row);

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item strict

=item warnings

=item base

=item ClearPress::driver

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

$Author: Roger Pettett$

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2008 Roger Pettett

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

=cut
