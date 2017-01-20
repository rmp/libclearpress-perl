use strict;
use warnings;
use Test::More tests => 84;
use HTTP::Headers;
use HTTP::Status qw(:constants);
use IO::Capture::Stderr;
use JSON;
use XML::XPath;
use English qw(-no_match_vars);
use lib qw(t/headers//lib t/lib);
use t::request;

use t::model::response;
use t::view::response;

my $runner = sub {
  my ($headers_ref, $content_ref, $config) = @_;

  no warnings qw(redefine once);
  local *ClearPress::util::data_path = sub { return 't/headers/data'; };

  my $response = t::request->new($config);

  my ($header_str, $content) = $response =~ m{^(.*?\n)\n(.*)$}smix;
  my $headers = HTTP::Headers->new();

  for my $line (split /\n/smx, $header_str) {
    my ($k, $v) = split m{\s*:\s*}smx, $line, 2;
    $headers->header($k, $v);
  }

  ${$headers_ref} = $headers;
  ${$content_ref} = $content;

  return 1;
};

{
  my $sets = [
	      [ '',     'text/html',        sub { my $arg=shift; return $arg;                                                      } ], # plain # <p class="error">
	      [ '.js',  'application/json', sub { my $arg=shift; return JSON->new->decode($arg)->{error};                          } ], # json
	      [ '.csv', 'application/csv',  sub { my $arg=shift; return [split /[\r\n]+/smix, $arg]->[0];                          } ], # csv
	      [ '.xml', 'text/xml',         sub { my $arg=shift; return XML::XPath->new(content=>$arg)->find('/error')->as_string; } ], # xml
	     ];

  for my $set (@{$sets}) {
    my ($extension, $content_type, $extraction) = @{$set};
    my $tests = [
		 ['/t', '/no_config',    'GET', '', HTTP_NOT_FOUND,             'No such view (no_config)', 'no config'],
		 ['/t', '/no_model',     'GET', '', HTTP_INTERNAL_SERVER_ERROR, 'Failed to instantiate no_model model', 'no model'],
		 ['/t', '/response/200', 'GET', '', HTTP_OK,                    '', '200 response'], # extractors look for error blocks, so can't check "code=200" here
		 ['/t', '/response/301', 'GET', '', HTTP_MOVED_PERMANENTLY,     '', '301 redirect'],
		 ['/t', '/response/302', 'GET', '', HTTP_FOUND,                 '', '302 moved'],
		 ['/t', '/response/403', 'GET', '', HTTP_FORBIDDEN,             '', '403 forbidden'],
		 ['/t', '/response/404', 'GET', '', HTTP_NOT_FOUND,             '', '404 not found'],
		 ['/t', '/response/500', 'GET', '', HTTP_INTERNAL_SERVER_ERROR, '', '500 error'],
		 ['/t', '/response/999', 'GET', '', HTTP_INTERNAL_SERVER_ERROR, 'Application Error', '999 failure'],
		];

    for my $t (@{$tests}) {
      my ($script_name, $path_info, $method, $username, $status, $errstr, $msg) = @{$t};
      $path_info .= $extension;

      my $cap = IO::Capture::Stderr->new;
      $cap->start;
      my ($headers, $content);
      $runner->(\$headers, \$content,
		{
		 SCRIPT_NAME    => $script_name,
		 PATH_INFO      => $path_info,
		 REQUEST_METHOD => $method,
		 username       => $username,
		});
      $cap->stop;

      my $ct_header = $headers->header('Content-Type') || q[];
      my ($charset) = $ct_header =~ m{\s*;\s*charset\s*=\S*(.*)$}smix;
      $ct_header    =~ s{\s*;\s*charset\s*=\S*.*$}{}smix;

      is($headers->header('Status'), $status,       "$method $script_name$path_info status $status [$msg]");
      is($ct_header,                 $content_type, "$method $script_name$path_info content_type $content_type [$msg]");

      if($errstr) {
	$errstr =~ s{([ ()])}{\[$1\]}smxg;
	my $str;
	eval {
	  $str = $extraction->($content);
	} or do {
	  diag("failed to extract content: $EVAL_ERROR");
	};
	like($str, qr{$errstr}smx, "$method $script_name$path_info content matches '$errstr'");
      }

#      diag "HEADERS=".$headers->as_string;
    }
  }
}
