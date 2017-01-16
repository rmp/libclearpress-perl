# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
use strict;
use warnings;
use Test::More;
use English qw(-no_match_vars);
use Carp;
#use HTML::TreeBuilder;
use XML::TreeBuilder;
use Template;
use Test::Trap;

eval {
  require DBD::SQLite;
  plan tests => 10;
} or do {
  plan skip_all => 'DBD::SQLite not installed';
};

use lib qw(t/lib);
use t::util;

use_ok('ClearPress::view::error');

my $util = t::util->new();

{
  my $view = ClearPress::view::error->new({
					   util   => $util,
					  });
  isa_ok($view, 'ClearPress::view::error');
}

{
  my $view = ClearPress::view::error->new({
					   aspect => q[read],
					   errstr => 'test',
					   util   => $util,
					  });
  trap {
    render_ok($view, 'view-error-read.html');
  };
  like($trap->stderr(), qr/Serving\ error/mix, 'warn to console');
}

{
  my $view = ClearPress::view::error->new({
					   aspect => q[read_xml],
					   errstr => q[test & @ ' ; "],
					   util   => $util,
					  });
  trap {
    render_ok($view, 'view-error-read.xml');
  };
  like($trap->stderr(), qr/Serving\ error/mix, 'warn to console');
}

{
  my $view = ClearPress::view::error->new({
					   aspect => q[read_json],
					   errstr => q[test & @ ' ; "],
					   util   => $util,
					  });
  trap {
    is($view->render(), q[{"error":"Error: test & @ ' ; \""}]);
  };
  like($trap->stderr(), qr/Serving\ error/mix, 'warn to console');
}

{
  Template->error(q[a template error]);
  my $view = ClearPress::view::error->new({
					   aspect => q[read],
					   util   => $util,
					  });
  trap {
    render_ok($view, 'view-error-read-tt.html');
  };
  like($trap->stderr(), qr/Serving\ error/mix, 'warn to console');
}

sub render_ok {
  my ($view, $fn) = @_;

  open my $fh, q[<], "t/data/rendered/$fn" or croak $ERRNO;
  local $RS   = undef;
  my $content = <$fh>;
  close $fh;

  my $expected_tree = XML::TreeBuilder->new;
  $expected_tree->parse_file("t/data/rendered/$fn");

  my $rendered_tree = XML::TreeBuilder->new;
  $rendered_tree->parse($view->render());

  return is($expected_tree->as_XML(), $rendered_tree->as_XML());
}
