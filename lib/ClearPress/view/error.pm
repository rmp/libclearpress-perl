# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
#########
# Author:        rmp
# Maintainer:    $Author: zerojinx $
# Created:       2007-03-28
# Last Modified: $Date: 2015-09-21 10:19:13 +0100 (Mon, 21 Sep 2015) $
# Id:            $Id: error.pm 470 2015-09-21 09:19:13Z zerojinx $
# $HeadURL: svn+ssh://zerojinx@svn.code.sf.net/p/clearpress/code/trunk/lib/ClearPress/view/error.pm $
#
package ClearPress::view::error;
use strict;
use warnings;
use base qw(ClearPress::view Class::Accessor);
use English qw(-no_match_vars);
use Template;
use Carp;

__PACKAGE__->mk_accessors(qw(errstr));

our $VERSION = q[474.0.1];

sub safe_errors {
  return 1;
}

sub render {
  my $self   = shift;
  my $aspect = $self->aspect();
  my $errstr = q(Error: ) . ($self->errstr()||q[]);

  if(Template->error()) {
    $errstr .= q(Template Error: ) . Template->error();
  }

  if($self->safe_errors) {
    print {*STDERR} "Serving error: $errstr\n" or croak $ERRNO;
    $errstr =~ s/[ ]at[ ]\S+[ ]line[ ][[:digit:]]+//smxg;
    $errstr =~ s/\s+$//smx;
    $errstr =~ s/Error:\s+Error/Error:/smix;
  }

  #########
  # initialise tt_filters by resetting tt
  #
  my $util = $self->util;
  delete $util->{tt};
  my $tt = $self->tt;

  if($aspect =~ /(?:ajax|xml|rss|atom)$/smx) {
    my $escaped = $self->tt_filters->{xml_entity}->($errstr);
    return qq[<?xml version='1.0'?>\n<error>$escaped</error>];
  }

  if($aspect =~ /json$/smx) {
    my $escaped = $self->tt_filters->{js_string}->($errstr);
    return qq[{"error":"$escaped"}];
  }

  my $escaped = $self->tt_filters->{xml_entity}->($errstr);
  return q(<div id="main"><h2 class="error">An Error Occurred</h2>) .  $self->actions() . q(<p class="error">) . $escaped . q(</p></div>);
}

1;

__END__

=head1 NAME

ClearPress::view::error - specialised view for error handling

=head1 VERSION

$LastChangedRevision: 470 $

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 errstr - Get/set accessor for an error string to display

  $oErrorView->errstr($sErrorMessage);
  my $sErrorMessage = $oErrorView->errstr();

=head2 render - encapsulated HTML rather than a template, in case the template has caused the error

  my $sErrorOutput = $oErrorView->render();

=head2 safe_errors - boolean flag, default on - strip strings which look like filenames and line numbers

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item strict

=item warnings

=item base

=item ClearPress::view

=item Class::Accessor

=item English

=item Template

=item Carp

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Roger Pettett, E<lt>rpettett@cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2007 by Roger Pettett

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
