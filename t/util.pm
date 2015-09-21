# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
package t::util;
use strict;
use warnings;
use base qw(Exporter ClearPress::util);
use Carp;
use Readonly;
use XML::Simple qw(XMLin);
use JSON;
use English qw(-no_match_vars);
use Digest::SHA qw(sha1_hex);

our @EXPORT_OK = qw(is_rendered_js);

$ENV{dev} = q[test];

sub _tmp_db_name {
  return sprintf q[%s.db], sha1_hex($PROGRAM_NAME);
}

sub new {
  my ($class, @args) = @_;

  my $db = _tmp_db_name();
  if(-e $db) {
    unlink $db;
  }

  my $self = $class->SUPER::new(@args);
  $self->config->setval('test','dbname', $db);

  my $drv  = $self->driver();

  eval {
    $drv->create_table('derived',
		       {
			id_derived        => 'primary key',
			id_derived_parent => 'integer unsigned',
			id_derived_status => 'integer unsigned',
			text_dummy        => 'text',
			char_dummy        => 'char(128)',
			int_dummy         => 'integer unsigned',
			float_dummy       => 'float unsigned',
		       });

    $drv->create_table('derived_parent',
		       {
			id_derived_parent => 'primary key',
			text_dummy        => 'text',
		       });
    $drv->create_table('derived_child',
		       {
			id_derived_child  => 'primary key',
			id_derived        => 'integer unsigned',
			text_dummy        => 'text',
		       });

    $drv->create_table('derived_status',
		       {
			id_derived_status => 'primary key',
			id_status         => 'integer unsigned',
		       });
    $drv->create_table('status',
		       {
			id_status   => 'primary key',
			description => 'text',
		       });
    $drv->create_table('derived_attr',
		       {
			id_derived_attr => 'primary key',
			id_attribute    => 'integer unsigned',
			id_derived      => 'integer unsigned',
		       });
    $drv->create_table('attribute',
		       {
			id_attribute => 'primary key',
			description  => 'text',
		       });
  } or do {
    #########
    # Failure to create tables is usually down to the developer trying
    # to initialise two util objects in the same perl instance,
    # presuming they're unique.
    #
#    carp $EVAL_ERROR;
  };

  return $self;
}

sub data_path {
  my ($self, $data_path) = @_;
  if(defined $data_path) {
    $self->{data_path} = $data_path;
  }
  return $self->{data_path} || 't/data';
}

sub requestor {
  my ($self, $user) = @_;

  if($user) {
    if(ref $user) {
      $self->{requestor} = $user;
    } else {
      croak q[Cannot handle non object requestors];
    }
  }

  return $self->{requestor};
}

sub DESTROY {
  my $self = shift;
  if($self->{driver}) {
    $self->{driver}->DESTROY();
  }

  my $db = _tmp_db_name();
  if(-e $db) {
    unlink $db;
  }
  return 1;
}

sub is_rendered_js {
  my ($str, $fn, @args) = @_;

  if($str =~ /Content-type/smix) {
    #########
    # Response headers have no place in a json parser
    #
    $str =~ s/.*?\n\n//smx;
  }

  my $received = from_json($str);
  open my $fh, q[<], "t/data/rendered/$fn" or croak qq[Failed to open t/data/rendered/$fn];
  local $RS = undef;
  my $blob  = <$fh>;
  close $fh or croak qq[Failed to close t/data/rendered/$fn];

  my $expected = from_json($blob);

  return Test::More::is_deeply($received, $expected, @args);
}

1;
