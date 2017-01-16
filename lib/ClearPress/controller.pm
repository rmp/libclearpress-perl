# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
#########
# Author:        rmp
# Maintainer:    $Author: zerojinx $
# Created:       2007-03-28
# Last Modified: $Date: 2015-09-21 10:19:13 +0100 (Mon, 21 Sep 2015) $
# Id:            $Id: controller.pm 470 2015-09-21 09:19:13Z zerojinx $
# Source:        $Source: /cvsroot/clearpress/clearpress/lib/ClearPress/controller.pm,v $
# $HeadURL: svn+ssh://zerojinx@svn.code.sf.net/p/clearpress/code/trunk/lib/ClearPress/controller.pm $
#
# method id action  aspect  result CRUD
# =====================================
# POST   n  create  -       create    *
# POST   y  create  update  update    *
# POST   y  create  delete  delete    *
# GET    n  read    -       list
# GET    n  read    add     add/new
# GET    y  read    -       read      *
# GET    y  read    edit    edit

package ClearPress::controller;
use strict;
use warnings;
use English qw(-no_match_vars);
use Carp;
use ClearPress::decorator;
use ClearPress::view::error;
use CGI;
use HTTP::Status qw(:constants :is);

our $VERSION = q[475.1.2];
our $CRUD    = {
		POST   => 'create',
		GET    => 'read',
		PUT    => 'update',
		DELETE => 'delete',
                HEAD   => 'null',
                TRACE  => 'null',
	       };
our $REST   = {
	       create => 'POST',
	       read   => 'GET',
	       update => 'PUT|POST',
	       delete => 'DELETE|POST',
	       add    => 'GET',
	       edit   => 'GET',
	       list   => 'GET',
               null   => 'HEAD|TRACE'
	      };

our $EXPERIMENTAL_HEADERS = 0;


sub accept_extensions {
  return [
	  {'.html' => q[]},
	  {'.xml'  => q[_xml]},
	  {'.png'  => q[_png]},
	  {'.svg'  => q[_svg]},
	  {'.svgz' => q[_svgz]},
	  {'.jpg'  => q[_jpg]},
	  {'.rss'  => q[_rss]},
	  {'.atom' => q[_atom]},
	  {'.js'   => q[_json]},
	  {'.json' => q[_json]},
	  {'.ical' => q[_ical]},
	  {'.txt'  => q[_txt]},
	  {'.xls'  => q[_xls]},
	  {'.ajax' => q[_ajax]},
	 ];
}

sub accept_headers {
  return [
#	  {'text/html'        => q[]},
	  {'application/json' => q[_json]},
	  {'text/xml'         => q[_xml]},
	 ];
}

sub new {
  my ($class, $self) = @_;
  $self ||= {};
  bless $self, $class;
  $self->init();

  eval {
    #########
    # We may be given a database handle from the cache with an open
    # transaction (e.g. from running a few selects), so on controller
    # construction (effectively per-page-view), we rollback any open
    # transaction on the database handle we've been given.
    #
    $self->util->dbh->rollback();
    1;

  } or do {
    #########
    # ignore any error
    #
    carp qq[Failed per-request rollback on fresh database handle: $EVAL_ERROR];
  };

  if(!$self->{response_code}) {
    #########
    # set an expected default http response code
    #
    $self->{response_code} = HTTP_OK;
  }

  return $self;
}

sub init {
  return 1;
}

sub util {
  my ($self, $util) = @_;
  if(defined $util) {
    $self->{util} = $util;
  }
  return $self->{util};
}

sub response_code {
  my ($self, $status) = @_;

  if($status) {
    $self->{response_code} = $status;
  }

  return $self->{response_code};
}

sub response_headers {
  my ($self, $headers) = @_;

  if($headers) {
    $self->{response_headers} = $headers;
  }

  return $self->{response_headers};
}

sub packagespace {
  my ($self, $type, $entity, $util) = @_;

  if($type ne 'view' &&
     $type ne 'model') {
    return;
  }

  $util         ||= $self->util();
  my $entity_name = $entity;

  if($util->config->SectionExists('packagemap')) {
    #########
    # if there are uri-to-package maps, process here
    #
    my $map = $util->config->val('packagemap', $entity);
    if($map) {
      $entity = $map;
    }
  }

  my $namespace = $self->namespace($util);
  return "${namespace}::${type}::$entity";
}

sub process_request { ## no critic (Subroutines::ProhibitExcessComplexity)
  my ($self, $util) = @_;
  my $method        = $ENV{REQUEST_METHOD} || 'GET';
  my $action        = $CRUD->{uc $method};
  my $pi            = $ENV{PATH_INFO}      || q[];
  my $accept        = $ENV{HTTP_ACCEPT}    || q[];
  my $qs            = $ENV{QUERY_STRING}   || q[];
  my $hxrw          = $ENV{HTTP_X_REQUESTED_WITH} || q[];
  my $xhr           = ($hxrw =~ /XMLHttpRequest/smix);

  my $accept_extensions = join q[|],
                          grep { defined }
                          map  { m{[.](\S+)$}smx; $1 || undef; } ## no critic (ProhibitCaptureWithoutTest, ProhibitComplexMappings)
                          map  { join q[,], keys %{$_} }
                          @{$self->accept_extensions()};

  if($xhr && $pi !~ m{(?:$accept_extensions)(?:/[^/]*?)?$}smx) {
    if($pi =~ /[;]/smx) {
      $pi .= q[_ajax];
    } else {
      $pi .= q[.ajax];
    }
  }

  my ($entity)      = $pi =~ m{^/([^/;.]+)}smx;
  $entity         ||= q[];
  my ($dummy, $aspect_extra, $id) = $pi =~ m{^/$entity(/(.*))?/([[:lower:][:digit:]:,\-_%@.+\s]+)}smix;

  my ($aspect)      = $pi =~ m{;(\S+)}smx;

  if($action eq 'read' && !$id && !$aspect) {
    $aspect = 'list';
  }

  if($action eq 'create' && $id) {
    if(!$aspect || $aspect =~ /^update/smx) {
      $action = 'update';

    } elsif($aspect =~ /^delete/smx) {
      $action = 'delete';
    }
  }

  $aspect ||= q[];
  $aspect_extra ||= q[];

  #########
  # process request extensions
  #
  my $uriaspect = $self->_process_request_extensions(\$pi, $aspect, $action) || q[];
  if($uriaspect ne $aspect) {
    $aspect = $uriaspect;
    ($id)   = $pi =~ m{^/$entity/?$aspect_extra/([[:lower:][:digit:]:,\-_%@.+\s]+)}smix;
  }

  #########
  # process HTTP 'Accept' header
  #
  $aspect   = $self->_process_request_headers(\$accept, $aspect, $action);
  $entity ||= $util->config->val('application', 'default_view');
  $aspect ||= q[];
  $id       = CGI->unescape($id||'0');

  #########
  # no view determined and no configured default_view
  # pull the first one off the list
  #
  if(!$entity) {
    my $views = $util->config->val('application', 'views') || q[];
    $entity   = (split /[\s,]+/smx, $views)[0];
  }

  #########
  # no view determined, no default_view and none in the list
  #
  if(!$entity) {
    croak q[No available views];
  }

  my $viewclass = $self->packagespace('view', $entity, $util);

  if($aspect_extra) {
    $aspect_extra =~ s{/}{_}smxg;
  }

  if($id eq '0') {
    #########
    # no primary key:
    # /thing;method
    # /thing;method_xml
    # /thing.xml;method
    #
    my $tmp = $aspect || $action;
    if($aspect_extra) {
      $tmp =~ s/_/_${aspect_extra}_/smx;

      if($viewclass->can($tmp)) {
	$aspect = $tmp;
      }
    }

  } elsif($id !~ /^\d+$/smx) {
    #########
    # mangled primary key - attempt to match method in view object
    # /thing/method          => list_thing_method (if exists), or read(pk=method)
    # /thing/part1/part2     => list_thing_part1_part2 if exists, or read_thing_part1(pk=part2)
    # /thing/method.xml      => list_thing_method_xml (if exists), or read_thing_xml (pk=method)
    # /thing/part1/part2.xml => list_thing_part1_part2_xml (if exists), or read_thing_part1_xml (pk=part2)
    #

    my $tmp = $aspect;

    if($tmp =~ /_/smx) {
      $tmp =~ s/_/_${id}_/smx;

    } else {
      $tmp = "${action}_$id";

    }

    $tmp =~ s/^read/list/smx;
    $tmp =~ s/^update/create/smx;

    if($aspect_extra) {
      $tmp =~ s/_/_${aspect_extra}_/smx;
    }

    if($viewclass->can($tmp)) {
      $id     = 0;
      $aspect = $tmp;

      #########
      # id has been modified, so reset action
      #
      if($aspect =~ /^create/smx) {
	$action = 'create';
      }

    } else {
      if($aspect_extra) {
	if($aspect =~ /_/smx) {
	  $aspect =~ s/_/_${aspect_extra}_/smx;
	} else {
	  $aspect .= "_$aspect_extra";
	}
      }
    }

  } elsif($aspect_extra) {
    #########
    # /thing/method/50       => read_thing_method(pk=50)
    #
    if($aspect =~ /_/smx) {
      $aspect =~ s/_/_${aspect_extra}_/smx;
    } else {
      $aspect .= "${action}_$aspect_extra";
    }
  }

  #########
  # fix up aspect
  #
  my ($firstpart) = $aspect =~ /^${action}_([^_]+)_?/smx;
  if($firstpart) {
    my $restpart = $REST->{$firstpart};
    if($restpart) {
      ($restpart) = $restpart =~ /^([^|]+)/smx;
      if($restpart) {
	my ($crudpart) = $CRUD->{$restpart};
	if($crudpart) {
	  $aspect =~ s/^${crudpart}_//smx;
	}
      }
    }
  }

  if($aspect !~ /^(?:create|read|update|delete|add|list|edit)/smx) {
    my $action_extended = $action;
    if(!$id) {
      $action_extended = {
			  read => 'list',
			 }->{$action} || $action_extended;
    }
    $aspect = $action_extended . ($aspect?"_$aspect":q[]);
  }

  #########
  # sanity checks
  #
  my ($type) = $aspect =~ /^([^_]+)/smx; # read|list|add|edit|create|update|delete
  if($method !~ /^$REST->{$type}$/smx) {
    $self->response_code(HTTP_BAD_REQUEST);
    croak qq[Bad request. $aspect ($type) is not a $CRUD->{$method} method];
  }

  if(!$id &&
     $aspect =~ /^(?:delete|update|edit|read)/smx) {
    $self->response_code(HTTP_BAD_REQUEST);
    croak qq[Bad request. Cannot $aspect without an id];
  }

  if($id &&
     $aspect =~ /^(?:create|add|list)/smx) {
    $self->response_code(HTTP_BAD_REQUEST);
    croak qq[Bad request. Cannot $aspect with an id];
  }

  $aspect =~ s/__/_/smxg;
  return ($action, $entity, $aspect, $id);
}

sub _process_request_extensions {
  my ($self, $pi, $aspect, $action) = @_;

  my $extensions = join q[], reverse ${$pi} =~ m{([.][^;.]+)}smxg;

  for my $pair (@{$self->accept_extensions}) {
    my ($ext, $meth) = %{$pair};
    $ext =~ s/[.]/\\./smxg;

    if($extensions =~ s{$ext$}{}smx) {
      ${$pi}    =~ s{$ext}{}smx;
      $aspect ||= $action;
      $aspect   =~ s/$meth$//smx;
      $aspect  .= $meth;
    }
  }

  return $aspect;
}

sub _process_request_headers {
  my ($self, $accept, $aspect, $action) = @_;

  for my $pair (@{$self->accept_headers()}) {
    my ($header, $meth) = %{$pair};
    if(${$accept} =~ /$header$/smx) {
      $aspect ||= $action;
      $aspect  =~ s/$meth$//smx;
      $aspect .= $meth;
      last;
    }
  }

  return $aspect;
}

sub decorator {
  my ($self, $util) = @_;

  if(!$self->{decorator}) {
    my $appname   = $util->config->val('application', 'name') || 'Application';
    my $namespace = $self->namespace;
    my $decorpkg  = "${namespace}::decorator";
    my $config    = $util->config;
    my $decor;

    eval {
      require $decorpkg;
      $decor = $decorpkg->new();
    } or do {
      $decor = ClearPress::decorator->new();
    };

    for my $field ($decor->fields) {
      $decor->$field($config->val('application', $field));
    }

    if(!$decor->title) {
      $decor->title($config->val('application', 'name') || 'ClearPress Application');
    }

    $self->{decorator} = $decor;
  }

  return $self->{decorator};
}

sub session {
  my ($self, $util) = @_;
  my $decorator = $self->decorator($util || $self->util());
  return $decorator->session() || {};
}

sub set_http_status {
  my $self = shift;
  my $util = $self->util;
  my $cgi  = $util->cgi;
  my $r    = $cgi->r;

  if(!$r) {
#    carp q[Warning: no request object available. Limited HTTP response support.];

    print "Status: @{[$self->response_code]}\n" or croak qq[Error printing: $ERRNO];
    while(my ($k, $v) = each %{$self->response_headers || {}}) {
      print "$k: $v\n" or croak qq[Error printing: $ERRNO];
    }

    return;
  }

  carp qq[Serving response code @{[$self->response_code]}];
  $r->status($self->response_code);
  while(my ($k, $v) = each %{$self->response_headers || {}}) {
    $r->headers_out->set($k => $v);
  }
  $r->rflush();

  return 1;
}

sub handler { ## no critic (Complexity)
  my ($self, $util) = @_;
  if(!ref $self) {
    $self = $self->new({util => $util});
  }

  my $cgi           = $util->cgi();
  my $decorator     = $self->decorator($util);
  my $namespace     = $self->namespace($util);

  my ($action, $entity, $aspect, $id) = $self->process_request($util);

  $util->username($decorator->username());
  $util->session($self->session($util));

  if(!$self->response_code) {
    $self->response_code(HTTP_OK);
  }

  my $viewobject = $self->dispatch({
				    util   => $util,
				    entity => $entity,
				    aspect => $aspect,
				    action => $action,
				    id     => $id,
				   });
  #########
  # boolean
  #
  my $decor = $viewobject->decor();

  #########
  # let the view have the decorator in case it wants to modify headers
  #
  $viewobject->decorator($decorator);

  if($decor) {
    if($viewobject->charset && $decorator->can('charset')) {
      $decorator->charset($viewobject->charset);
    }

    my $content_type = $viewobject->content_type();
    my $charset      = $viewobject->charset();
    if($content_type =~ /text/smx && $charset =~ /utf-?8/smix) {
      binmode STDOUT, q[:encoding(UTF-8)];
    }

    $viewobject->output_buffer($decorator->header());
  }

  my $errstr;
  eval {
    #########
    # view->render() may be streamed
    #
    $viewobject->output_buffer($viewobject->render());
    1;
  } or do {
    carp qq[view->render failed: $EVAL_ERROR];
    $viewobject->response_code(HTTP_INTERNAL_SERVER_ERROR);
    $errstr = $EVAL_ERROR;
  };

  #########
  # handle special cases like redirect headers
  #
  my ($code, $headers) = $viewobject->response_code();

  #########
  # copy response header state from view into self
  #
  $self->response_code($code);
  $self->response_headers({%{$headers || {}}});

  my $bail_early = 0;

  if($code && !is_success($code)) { # is_error | is_redirect
    $bail_early = 1;
  }

  #########
  # emit http response headers based on self->response_code/response_headers
  #
  $self->set_http_status();

  #########
  # bail out of response handler early (trigger subrequest if necessary)
  #
  if($bail_early) {
    #########
    # force reconstruction of CGI object from subrequest QUERY_STRING
    #
    delete $util->{cgi};

    #########
    # but pass-through the errstr
    #
    $util->cgi->param('errstr', $cgi->escape($errstr));

    $viewobject->output_finished(0);
    $viewobject->output_reset();

    if($cgi->r) {
      #########
      # mod-perl errordocument handled by subrequest
      #
      return;
    }

    #########
    # non-mod-perl errordocument handled by application internals
    #
    my $error_ns = sprintf q[%s::view::error], $namespace;
    carp qq[Handling error with $error_ns];

    eval {
      $viewobject = $error_ns->new({util => $util});
    } or do {
      $viewobject = ClearPress::view::error->new({util => $util});
    };

    $viewobject->output_buffer($decorator->header());
    $viewobject->output_buffer($viewobject->render());
  }

  #########
  # re-test decor in case it's changed by render()
  #
  if($viewobject->decor()) {
    #########
    # assume it's safe to re-open the output stream (Eesh!)
    #
    $viewobject->output_buffer($decorator->footer());

  } else {
    #########
    # prepend content-type to output buffer
    #
    if(!$viewobject->output_finished()) {
      print qq(X-Generated-By: ClearPress\n) or croak $ERRNO;

      my $charset = $viewobject->charset();
      if(defined $charset) {
        $charset = qq[; charset="$charset"];
      }

      my $content_type = $viewobject->content_type();
      $content_type = qq[Content-type: $content_type$charset\n\n];

      print $content_type or croak $ERRNO;
    }
  }

  #########
  # flush everything left to client socket (via stdout)
  #
  $viewobject->output_end();

  #########
  # save the session after the request has processed
  #
  $decorator->save_session();

  #########
  # clean up any shared state so it's not carried over (e.g. incomplete transactions)
  #
  $util->cleanup();

  return 1;
}

sub namespace {
  my ($self, $util) = @_;
  my $ns   = q[];

  if((ref $self && !$self->{namespace}) || !ref $self) {
    $util ||= $self->util();
    $ns = $util->config->val('application', 'namespace') ||
          $util->config->val('application', 'name') ||
	  'ClearPress';
    if(ref $self) {
      $self->{namespace} = $ns;
    }
  } else {
    $ns = $self->{namespace};
  }

  return $ns;
}

sub is_valid_view {
  my ($self, $ref, $viewname) = @_;
  my $util     = $ref->{util};
  my @entities = split /[,\s]+/smx, $util->config->val('application','views');

  if(!scalar grep { $_ eq $viewname } @entities) {
    return;
  }

  return 1;
}

sub dispatch {
  my ($self, $ref) = @_;
  my $util      = $ref->{util};
  my $entity    = $ref->{entity};
  my $aspect    = $ref->{aspect};
  my $action    = $ref->{action};
  my $id        = $ref->{id};
  my $viewobject;

  my $state = $self->is_valid_view($ref, $entity);
  if(!$state) {
    $self->response_code(HTTP_NOT_FOUND);
    croak qq(No such view ($entity). Is it in your config.ini?);
  }

  my $entity_name = $entity;
  my $viewclass   = $self->packagespace('view',  $entity, $util);

  my $modelobject;
  if($entity ne 'error') {
    my $modelclass = $self->packagespace('model', $entity, $util);
    eval {
      my $modelpk    = $modelclass->primary_key();
      $modelobject   = $modelclass->new({
                                         util => $util,
                                         $modelpk?($modelpk => $id):(),
                                        });
      1;
    } or do {
      # bail out
    };

    if(!$modelobject) {
      $self->response_code(HTTP_INTERNAL_SERVER_ERROR);
      croak qq[Failed to instantiate $entity model: $EVAL_ERROR];
    }
  }

  eval {
    $viewobject = $viewclass->new({
                                   util        => $util,
                                   model       => $modelobject,
                                   action      => $action,
                                   aspect      => $aspect,
                                   entity_name => $entity_name,
                                   decorator   => $self->decorator,
                                  });
    1;
  } or do {
    # bail out
  };

  if(!$viewobject) {
    $self->response_code(HTTP_INTERNAL_SERVER_ERROR);
    croak qq[Failed to instantiate $entity view: $EVAL_ERROR];
  }

  return $viewobject;
}

1;
__END__

=head1 NAME

ClearPress::controller - Application controller

=head1 VERSION

$Revision: 470 $

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 new - constructor, usually no specific arguments

 my $oController = application::controller->new();

=head2 init - post-constructor initialisation, called after new()

 $oController->init();

=head2 session

=head2 util

=head2 decorator - get/set accessor for a page decorator implementing the ClearPress::decorator interface

  $oController->decorator($oDecorator);

  my $oDecorator = $oController->decorator();

=head2 accept_extensions - data structure of file-extensions-to-aspect mappings  (e.g. '.xml', '.js') in precedence order

 my $arAcceptedExtensions = $oController->accept_extensions();

 [
  {'.ext' => '_aspect'},
  {'.js'  => '_json'},
 ]

=head2 accept_headers - data structure of accept_header-to-aspect mappings  (e.g. 'text/xml', 'application/javascript') in precedence order

 my $arAcceptedHeaders = $oController->accept_headers();

 [
  {'text/mytype'            => '_aspect'},
  {'application/javascript' => '_json'},
 ]

=head2 process_uri - deprecated. use process_request()

=head2 process_request - extract useful things from %ENV relating to our URI

  my ($sAction, $sEntity, $sAspect, $sId) = $oCtrl->process_request($oUtil);

=head2 handler - run the controller

=head2 namespace - top-level package namespace from config.ini

  my $sNS = $oCtrl->namespace();
  my $sNS = app::controller->namespace();

=head2 packagespace - mangled namespace given a package- and entity-type

  my $pNS = $oCtrl->packagespace('model', 'entity_type');
  my $pNS = $oCtrl->packagespace('view',  'entity_type');
  my $pNS = app::controller->packagespace('model', 'entity_type', $oUtil);
  my $pNS = app::controller->packagespace('view',  'entity_type', $oUtil);

=head2 dispatch - view generation

=head2 is_valid_view - view-name validation

#=head2 build_error_object - builds an error view object

=head2 response_code - wrap view->response_code and extend with more error statuses

=head2 response_headers - wrap view->response_code

=head2 set_http_status - configure outbound response status header via CGI.pm

 $oController->set_http_status();

 Based on view->response_code || controller->response_code

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

Set $ClearPress::controller::EXPERIMENTAL_HEADERS = 1 to enable basic CGI response headers for various error states

=head1 DEPENDENCIES

=over

=item strict

=item warnings

=item English

=item Carp

=item ClearPress::decorator

=item ClearPress::view::error

=item CGI

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Roger Pettett, E<lt>rpettett@cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2008 Roger Pettett

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
