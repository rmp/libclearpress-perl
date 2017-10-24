# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
use strict;
use warnings;
use Test::More;
use English qw(-no_match_vars);
use Carp;
use lib qw(t/lib);
use t::request;
use t::model::derived;
use t::view::derived;

eval {
  require DBD::SQLite;
  plan tests => 1;
} or do {
  plan skip_all => 'DBD::SQLite not installed';
};


{
  no warnings qw(redefine once);

  local *t::view::derived::render = sub {
    my $self = shift;

    if(1) { # conditional special handling requirements here
      $self->action('list');
      $self->aspect('list_extended'); # wherever you want to end up
      my $class = ref $self->model;
      my $table_name = $self->model->table;
      my ($pi) = $ENV{PATH_INFO} =~ m{^.*?$table_name(.*)}smix;
      $self->model($class->new($pi));
    }

    return ClearPress::view::render($self);
  };

  local *t::view::derived::list_extended = sub {
    my $self = shift;
    my $pk   = $self->model->primary_key;
    ok($self->model->$pk, q[/secondary/key/with/slashes]);
  };

  my ($head, $body) = t::request->new({
				       PATH_INFO      => '/derived/secondary/key/with/slashes',
				       REQUEST_METHOD => 'GET',
				       util           => t::util->new,
				      });
}

