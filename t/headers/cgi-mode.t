use strict;
use warnings;
use Test::More tests => 72;
use HTTP::Headers;
use HTTP::Status qw(:constants);
use IO::Capture::Stderr;
use lib qw(t/headers//lib t/lib);
use t::request;

#use t::model::response;
#use t::view::response;
#use t::view::error;

my $runner = sub {
  my ($headers_ref, $content_ref, $config) = @_;
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

no warnings qw(redefine once);
local *ClearPress::util::data_path = sub { return 't/headers/data'; };

{
  my $sets = [
	      [ '',     'text/html'        ], # plain
	      [ '.js',  'application/json' ], # json
	      [ '.csv', 'application/csv'  ], # csv
	      [ '.xml', 'text/xml'         ], # xml
	     ];

  for my $set (@{$sets}) {
    my ($extension, $content_type) = @{$set};
    my $tests = [
		 ['/t', '/no_config',    'GET', '', HTTP_NOT_FOUND,             'no config'],
		 ['/t', '/no_model',     'GET', '', HTTP_INTERNAL_SERVER_ERROR, 'no model'],
		 ['/t', '/response/200', 'GET', '', HTTP_OK,                    '200 response'],
		 ['/t', '/response/301', 'GET', '', HTTP_OK,                    '301 redirect'],
		 ['/t', '/response/302', 'GET', '', HTTP_FOUND,                 '302 moved'],
		 ['/t', '/response/403', 'GET', '', HTTP_FORBIDDEN,             '403 forbidden'],
		 ['/t', '/response/404', 'GET', '', HTTP_NOT_FOUND,             '404 not found'],
		 ['/t', '/response/500', 'GET', '', HTTP_INTERNAL_SERVER_ERROR, '500 error'],
		 ['/t', '/response/999', 'GET', '', HTTP_INTERNAL_SERVER_ERROR, '999 failure'],


	     # undecorated json/xml
	     # streamed html/json/xml
	    ];
    for my $t (@{$tests}) {
      my ($script_name, $path_info, $method, $username, $status, $msg) = @{$t};
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

      is($headers->header('Status'),       $status,       "$method $script_name$path_info status $status [$msg]");
      is($headers->header('Content-Type'), $content_type, "$method $script_name$path_info content_type $content_type [$msg]");
      
      diag "HEADERS=".$headers->as_string;
      #    diag "CONTENT=$content";
    }
  }
}
