# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
use strict;
use warnings;
use Test::More;
use English qw(-no_match_vars);
use IO::Scalar;
use CGI;
use Carp;
use lib qw(t/lib);
use t::request;
use t::model::derived;
use t::view::derived;
use JSON;

eval {
  require DBD::SQLite;
  plan tests => 3;
} or do {
  plan skip_all => 'DBD::SQLite not installed';
};

# update with postdata json
# update with no payload - last_modified touch

{
  my $util = t::util->new;
  my $obj = {
	     char_dummy => "a string",
	     int_dummy  => 5,
	    };
  my $str = t::request->new({
			     PATH_INFO      => '/derived',
                             REQUEST_METHOD => 'POST',
                             util           => $util,
			     cgi_params     => {
						POSTDATA => JSON->new->encode($obj),
					       },
			    });
  my $ref = $util->dbh->selectall_arrayref(q[SELECT * FROM derived], {Slice => {}});

  is_deeply($ref, [
		   {
		    id_derived        => 1,
		    char_dummy        => "a string",
		    text_dummy        => undef,
		    int_dummy         => 5,
		    float_dummy       => undef,
		    id_derived_status => undef,
		    id_derived_parent => undef,
		   }
		  ], 'create with json postdata');
}

{
  my $util = t::util->new;
  my $existing = t::model::derived->new({
					 id_derived_parent => 1,
					 id_derived_status => 2,
					 char_dummy => "existing char",
					 float_dummy => 42.7,
					 int_dummy => 42,
					 text_dummy => "some text",
					});
  $existing->create;
  my $obj = {
	     id_derived => $existing->id_derived, # has no impact!
	     char_dummy => "a string",
	     int_dummy  => 5,
	    };
  my $str = t::request->new({
			     PATH_INFO      => "/derived/@{[$existing->id_derived]}",
                             REQUEST_METHOD => 'POST',
                             util           => $util,
			     cgi_params     => {
						POSTDATA => JSON->new->encode($obj),
					       },
			    });
  my $ref = $util->dbh->selectall_arrayref(q[SELECT * FROM derived], {Slice => {}});
  is_deeply($ref, [
		   {
		    id_derived_parent => 1,
		    char_dummy => 'a string',
		    text_dummy => 'some text',
		    int_dummy => 5,
		    id_derived => 1,
		    id_derived_status => 2,
		    float_dummy => 42.7,
		   }
		  ], 'update (id in url) with json postdata');
}

{
  my $util = t::util->new;
  my $existing = t::model::derived->new({
					 id_derived_parent => 1,
					 id_derived_status => 2,
					 char_dummy => "existing char",
					 float_dummy => 42.7,
					 int_dummy => 42,
					 text_dummy => "some text",
					});
  $existing->create;
  my $obj = {
	     id_derived => $existing->id_derived, # has no impact!
	     char_dummy => "a string",
	     int_dummy  => 5,
	    };
  my $str = t::request->new({
			     PATH_INFO      => '/derived',
                             REQUEST_METHOD => 'POST',
                             util           => $util,
			     cgi_params     => {
						POSTDATA => JSON->new->encode($obj),
					       },
			    });
  my $ref = $util->dbh->selectall_arrayref(q[SELECT * FROM derived], {Slice => {}});
  is_deeply($ref, [
		   {
		    id_derived_parent => 1,
		    char_dummy => 'existing char',
		    text_dummy => 'some text',
		    id_derived_status => 2,
		    id_derived => 1,
		    float_dummy => 42.7,
		    int_dummy => 42
		   },
		   {
		    id_derived_status => undef,
		    text_dummy => undef,
		    char_dummy => 'a string',
		    id_derived_parent => undef,
		    int_dummy => 5,
		    float_dummy => undef,
		    id_derived => 2
		   }
		  ], 'update (id in payload) with json postdata - should create, not update');
}
