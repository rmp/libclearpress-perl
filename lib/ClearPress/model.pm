# -*- mode: cperl; tab-width: 8; indent-tabs-mode: nil; basic-offset: 2 -*-
# vim:ts=8:sw=2:et:sta:sts=2
#########
# Author: rmp
# Created: 2006-10-31
#
package ClearPress::model;
use strict;
use warnings;
use base qw(Class::Accessor);
use ClearPress::util;
use English qw(-no_match_vars);
use Carp;
use Lingua::EN::Inflect qw(PL);
use Lingua::EN::PluralToSingular qw(to_singular);
use POSIX qw(strftime);
use Readonly;
use JSON;

our $VERSION = q[2018.08.30];

Readonly::Scalar our $DBI_CACHE_OVERWRITE => 3;

our $EXPERIMENTAL_PL = 0;

sub fields { return (); }

sub _plfunc {
  my $thing = shift;
  return $EXPERIMENTAL_PL ? PL(to_singular($thing)) : PL($thing);
}

sub primary_key {
  my $self = shift;
  return ($self->fields())[0];
}

sub secondary_key {
}

sub table {
  my $self = shift;
  my $tbl  = (ref $self) || $self;
  if(!$tbl) {
    return;
  }
  ($tbl)   = $tbl =~ /.*::([^:]+)/smx;
  return $tbl;
}

sub init  { }

sub new {
  my ($class, $ref) = @_;
  $ref ||= {};

  my $pk = $class->primary_key();

  if(!ref $ref) {
    if($pk) {
      $ref = {
	      $pk => $ref,
	     };
    } else {
      croak q[Could not set primary key in an object with no fields];
    }
  }

  bless $ref, $class;

  my $sk   = $ref->secondary_key();
  if($sk && $ref->{$sk} &&
     !$ref->{$pk}) {

    my $table = $ref->table;
    my $util  = $ref->util;
    my $dbh   = $util->dbh;
    eval {
      my $id   = $dbh->selectall_arrayref(qq[/* model::new */ SELECT $pk FROM $table WHERE $sk=?], {}, $ref->{$sk})->[0]->[0];
      $ref->{$pk} = $id;
      1;

    } or do {
      carp $EVAL_ERROR;
      return;
    };
  }

  $ref->init($ref);

  return $ref;
}

sub util {
  my ($self, $util) = @_;

  if(!ref $self) {
    #########
    # If we're being accessed as a class method (e.g. for retrieving
    # type dictionaries) Then play nicely and return a util.
    #
    # Note, this currently needs subclassing if you want class-method
    # support in your own namespace.
    #
    return ClearPress::util->new();
  }

  if($util) {
    $self->{util} = $util;
    return $util;
  }

  if($self->{util}) {
    return $self->{util};
  }

  #########
  # attempt to instantiate a util using $self's namespace
  #
  my ($ref) = (ref $self) =~ /^([^:]+)/smx;
  my $nsutil;
  eval {
    my $ns  = "${ref}::util";
    $nsutil = $ns->new();

  } or do {
    carp qq[Failed to construct a util from the current namespace ($ref).];
  };

  if($nsutil) {
    $self->{util} = $nsutil;
    return $self->{util};
  }

  #########
  # ClearPress::driver is now a Class::Singleton so, casually ignoring
  # the state of any open transactions, we should be able to
  # instantiate more copies on demand
  #
  my $cputil    = ClearPress::util->new();
  my $config    = $cputil->config();
  my $namespace = $config->val('application', 'namespace') ||
                  $config->val('application', 'name');
  $util         = "${namespace}::util"->new();
  $self->{util} = $util;
  return $util;
}

sub get {
  my ($self, $field) = @_;

  if(!exists $self->{$field}) {
    $self->read();
  }

  return $self->SUPER::get($field);
}

sub gen_getarray {
  my ($self, $class, $query, @args) = @_;
  my $util = $self->util();

  if(!ref $self) {
    $self = $self->new({
			util => $util,
		       });
  }

  my $res  = [];
  my $sth;

  eval {
    my $dbh = $util->dbh();
    #########
    # statement caching removed as cache conflicts are dangerous
    # and could be easily generated by accident
    $sth = $dbh->prepare($query);
    $sth->execute(@args);
    1; # sth->execute() does not return true!

  } or do {
    $query =~ s/\s+/ /smxg;
    local $LIST_SEPARATOR = q[, ];
    carp qq[GEN_GETARRAY ERROR\nEVAL_ERROR: $EVAL_ERROR\nCaller: @{[q[].caller]}\nQuery:\n$query\nDBH: @{[$util->dbh]}\nUTIL: $util\nParams: @{[map { (defined $_)?$_:'NULL' } @args]}];
    return;
  };

  while(my $ref = $sth->fetchrow_hashref()) {
    $ref->{util} = $util;
    push @{$res}, $class->new($ref);
  }
  $sth->finish();

  return $res;
}

sub gen_getall {
  my ($self, $class, $cachekey) = @_;
  $class ||= ref $self;

  if(!$cachekey) {
    ($cachekey) = $class =~ /([^:]+)$/smx;
    $cachekey   = _plfunc($cachekey);
  }

  if(!$self->{$cachekey}) {
    my $sortk = $self->secondary_key;
    if(!$sortk) {
      $sortk = $self->primary_key;
    }
    my $query = <<"EOT";
/* model::gen_getall */
SELECT   @{[join q(, ), $class->fields()]}
FROM     @{[$class->table()]}
ORDER BY $sortk
EOT
    $self->{$cachekey} = $self->gen_getarray($class, $query);
  }

  return $self->{$cachekey};
}

sub gen_getfriends {
  my ($self, $class, $cachekey) = @_;
  $class ||= ref $self;

  if(!$cachekey) {
    ($cachekey) = $class =~ /([^:]+)$/smx;
    $cachekey   = _plfunc($cachekey);
  }

  if(!$self->{$cachekey}) {
    my $link  = $self->primary_key();
    my $query = <<"EOT";
/* model::gen_getfriends */
SELECT   @{[join q(, ), $class->fields()]}
FROM     @{[$class->table()]}
WHERE    $link=?
ORDER BY $link
EOT
    $self->{$cachekey} = $self->gen_getarray($class, $query, $self->$link());
  }

  return $self->{$cachekey};
}

sub gen_getfriends_through {
  my ($self, $class, $through, $cachekey) = @_;
  $class ||= ref $self;

  if(!$cachekey) {
    ($cachekey) = $class =~ /([^:]+)$/smx;
    $cachekey   = _plfunc($cachekey);
  }

  if(!$self->{$cachekey}) {
    my ($through_pkg) = (ref $self) =~ /^(.*::)[^:]+$/smx;
    $through_pkg     .= $through;
    my $through_key   = $self->primary_key();
    my $friend_key    = $class->primary_key();
    my $query         = <<"EOT";
/* model::gen_getfriends_through */
SELECT @{[join q(, ),
               (map { "f.$_" } $class->fields()),
               (map { "t.$_" } $through_pkg->fields())]}
FROM   @{[$class->table()]} f,
       $through             t
WHERE  t.$through_key = ?
AND    t.$friend_key  = f.$friend_key
EOT
    $self->{$cachekey} = $self->gen_getarray($class, $query, $self->$through_key());
  }

  return $self->{$cachekey};
}

sub gen_getobj {
  my ($self, $class)   = @_;
  $class             ||= ref $self;
  my $pk               = $class->primary_key();
  my ($cachekey)       = $class =~ /([^:]+)$/smx;
  $self->{$cachekey} ||= $class->new({
				      util => $self->util(),
				      $pk  => $self->$pk(),
				     });
  return $self->{$cachekey};
}

sub gen_getobj_through {
  my ($self, $class, $through, $cachekey) = @_;
  $class ||= ref $self;

  if(!$cachekey) {
    ($cachekey) = $class =~ /([^:]+)$/smx;
  }

  if(!$self->{$cachekey}) {
    # todo: use $through class to determine $through_key
    #       - but $through class may not always be implemented
    my $through_key = q(id_).$through;
    my $friend_key  = $class->primary_key();
    my $query       = <<"EOT";
/* model::gen_getobj_through */
SELECT @{[join q(, ), map { "f.$_" } $class->fields()]}
FROM   @{[$class->table()]} f,
       $through            t
WHERE  t.$through_key = ?
AND    t.$friend_key  = f.$friend_key
EOT

    $self->{$cachekey} = $self->gen_getarray($class, $query, $self->$through_key())->[0];
  }

  return $self->{$cachekey};
}

sub belongs_to {
  my ($class, @args) = @_;
  return $class->has_a(@args);
}

sub hasa {
  my ($class, @args) = @_;
  carp q[hasa is deprecated. Use has_a];
  return $class->has_a(@args);
}

sub has_a {
  my ($class, $attr) = @_;

  if(ref $attr ne 'ARRAY') {
    $attr = [$attr];
  }

  for my $single (@{$attr}) {
    my $pkg = $single;

    if(ref $single eq 'HASH') {
      ($pkg)    = values %{$single};
      ($single) = keys %{$single};
    }

    my $namespace = "${class}::$pkg";
    my $yield     = $class;
    if($yield !~ /model/smx) {
      croak qq[$pkg is not under a model:: namespace. Friend relationships will not work.];
    }

    $yield =~ s/^(.*model::).*$/$1$pkg/smx;

    if (defined &{$namespace}) {
      next;
    }

    no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{$namespace} = sub {
      my $self = shift;
      return $self->gen_getobj($yield);
    };
  }

  return;
}

sub hasmany {
  my ($class, @args) = @_;
  carp q[hasmany is deprecated. Use has_many];
  return $class->has_many(@args);
}

sub has_many {
  my ($class, $attr) = @_;

  if(ref $attr ne 'ARRAY') {
    $attr = [$attr];
  }

  for my $single (@{$attr}) {
    my $pkg = $single;

    if(ref $single eq 'HASH') {
      ($pkg)    = values %{$single};
      ($single) = keys %{$single};
    }

    my $plural    = _plfunc($single);
    my $namespace = "${class}::$plural";
    my $yield     = $class;
    $yield        =~ s/^(.*model::).*$/$1$pkg/smx;

    if($yield !~ /model/smx) {
      croak qq[$pkg is not under a model:: namespace. Friend relationships will not work.];
    }

    if (defined &{$namespace}) {
      next;
    }

    no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{$namespace} = sub {
      my $self = shift;
      return $self->gen_getfriends($yield, $plural);
    };
  }

  return;
}

sub belongs_to_through {
  my ($class, @args) = @_;
  return $class->has_a_through(@args);
}

sub has_a_through {
  my ($class, $attr) = @_;

  if(ref $attr ne 'ARRAY') {
    $attr = [$attr];
  }

  for my $single (@{$attr}) {
    my $pkg = $single;

    if(ref $single eq 'HASH') {
      ($pkg)    = values %{$single};
      ($single) = keys %{$single};
    }
    $pkg =~ s/[|].*//smx;

    my $through;
    ($single, $through) = split /[|]/smx, $single;

    if(!$through) {
      croak qq(Cannot build belongs_to_through for $single);
    }

    my $namespace = "${class}::$pkg";
    my $yield     = $class;
    $yield        =~ s/^(.*model::).*$/$1$pkg/smx;

    if($yield !~ /model/smx) {
      croak qq[$pkg is not under a model:: namespace. Friend relationships will not work.];
    }

    if (defined &{$namespace}) {
      next;
    }

    no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{$namespace} = sub {
      my $self = shift;
      return $self->gen_getobj_through($yield, $through);
    };
  }

  return;
}

sub has_many_through {
  my ($class, $attr) = @_;

  if(ref $attr ne 'ARRAY') {
    $attr = [$attr];
  }

  for my $single (@{$attr}) {
    my $pkg = $single;

    if(ref $single eq 'HASH') {
      ($pkg)    = values %{$single};
      ($single) = keys %{$single};
    }
    $pkg =~ s/[|].*//smx;

    my $through;
    ($single, $through) = split /[|]/smx, $single;

    if(!$through) {
      croak qq(Cannot build has_many_through for $single);
    }

    my $plural    = _plfunc($single);
    my $namespace = "${class}::$plural";
    my $yield     = $class;
    $yield        =~ s/^(.*model::).*$/$1$pkg/smx;

    if($yield !~ /model/smx) {
      croak qq[$pkg is not under a model:: namespace. Friend relationships will not work.];
    }

    if (defined &{$namespace}) {
      next;
    }

    no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{$namespace} = sub {
      my $self = shift;

      return $self->gen_getfriends_through($yield, $through, $plural);
    };
  }

  return;
}

sub has_all {
  my ($class) = @_;

  my ($single)  = $class =~ /([^:]+)$/smx;
  my $plural    = _plfunc($single);
  my $namespace = "${class}::$plural";

  if (defined &{$namespace}) {
    return;
  }

  no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
  *{$namespace} = sub {
    my $self = shift;
    return $self->gen_getall();
  };

  return 1;
}

sub create {
  my $self     = shift;
  my $util     = $self->util();
  my $dbh      = $util->dbh();
  my $pk       = $self->primary_key();
  my $tr_state = $util->transactions();
  my $table    = $self->table();

  if(!$table) {
    croak q(No table defined);
  }

  #########
  # disallow saving against zero
  #
  if(!$self->$pk()) {
    delete $self->{$pk};
  }

  my $query = <<"EOT";
INSERT INTO $table (@{[join q(, ), $self->fields()]})
VALUES (@{[join q(, ), map { q(?) } $self->fields()]})
EOT

  my @args = map { $self->{$_} } $self->fields();
  eval {
    my $drv = $util->driver();
    my $id  = $drv->create($query, @args);
    $self->$pk($id);

  } or do {
    $tr_state and $dbh->rollback();
    carp qq[CREATE Query was:\n$query\n\nParams: @{[map { (defined $_)?$_:'NULL' } @args]}];
    croak $EVAL_ERROR;
  };

  eval {
    $tr_state and $dbh->commit();
    1;

  } or do {
    $tr_state and $dbh->rollback();
    croak $EVAL_ERROR;
  };

  return 1;
}

sub read { ## no critic (homonym)
  my ($self, $query, @args) = @_;
  my $pk   = $self->primary_key();
  my $util = $self->util;

  if(!$query && !$self->{$pk}) {
#    carp q(No primary key);
    return;
  }

  my $table = $self->table();
  if(!$table) {
    croak q(No table defined);
  }

  if(!$self->{_loaded}) {
    if(!$query) {
      $query = <<"EOT";
/* model::read */
SELECT @{[join q(, ), $self->fields()]}
FROM   $table
WHERE  $pk=?
EOT
      @args = ($self->{$pk});
    }

    eval {
      my $sth = $util->dbh->prepare($query);
      $sth->execute(@args);

      my $ref = $sth->fetchrow_hashref();

      if(!$sth->rows()) {
	#########
	# entity not in database
	#
	$sth->finish();
	croak q[missing entity];
      }

      $sth->finish();

      my $warnings = $util->driver->sth_has_warnings($sth);
      if(!$warnings) {
        for my $f ($self->fields()) {
          $self->{$f} = $ref->{$f};
        }

      } else {
        for my $w (@{$warnings}) {
          carp qq[ClearPress::model::read: mysql warning: $w->[2]];
        }
      }

      1;

    } or do {
      if($EVAL_ERROR =~ /missing\sentity/smx) {
	return;
      }
      carp qq[SELECT ERROR\nEVAL_ERROR: $EVAL_ERROR\nQuery:\n$query\n\nParams: @{[map { (defined $_)?$_:'NULL' } @args]}\n];
    };
  }
  $self->{_loaded} = 1;
  return 1;
}

sub update {
  my $self  = shift;
  my $pk    = $self->primary_key();

  if(!$pk || !$self->$pk()) {
    croak q(No primary key);
  }

  my $table = $self->table();
  if(!$table) {
    croak q(No table defined);
  }

  my $util     = $self->util();
  my $tr_state = $util->transactions();
  my $dbh      = $util->dbh();
  my @fields   = grep { exists $self->{$_} }
                 grep { $_ ne $pk }
                 $self->fields();
  my $query   = <<"EOT";
UPDATE @{[$self->table()]}
SET    @{[join q(, ),
               map  { qq[$_ = ?] }
               @fields]}
WHERE  $pk=?
EOT

  eval {
    $dbh->do($query, {}, (map { $self->$_() } @fields), $self->$pk);

  } or do {
    $tr_state and $dbh->rollback();
    croak $EVAL_ERROR.q[ ].$query;
  };

  eval {
    $tr_state and $dbh->commit();
    1;

  } or do {
    croak $EVAL_ERROR;
  };

  return 1;
}

sub delete { ## no critic (homonym)
  my $self     = shift;
  my $util     = $self->util();
  my $tr_state = $util->transactions();
  my $dbh      = $util->dbh();
  my $pk       = $self->primary_key();

  if(!$pk || !$self->$pk()) {
    croak q(No primary key);
  }

  my $query = <<"EOT";
DELETE FROM @{[$self->table()]}
WHERE $pk=?
EOT

  eval {
    $dbh->do($query, {}, $self->$pk());

  } or do {
    $tr_state and $dbh->rollback();
    croak $EVAL_ERROR.$query;
  };

  eval {
    $tr_state and $dbh->commit();
    1;

  } or do {
    croak $EVAL_ERROR;
  };

  return 1;
}

sub save {
  my $self = shift;
  my $pk   = $self->primary_key();

  if($pk && defined $self->{$pk}) {
    return $self->update();
  }

  return $self->create();
}

sub zdate {
  my $self = shift;
  my $date = q[];

  if(scalar grep { $_ eq 'date' } $self->fields()) {
    $date = $self->date() || q[];
    $date =~ s/[ ]/T/smx;
    $date .='Z';
  }

  if(!$date) {
    $date = strftime q(%Y-%m-%dT%H:%M:%SZ), gmtime;
  }

  return $date;
}

sub isodate {
  return strftime q(%Y-%m-%d %H:%M:%S), gmtime;
}

sub as_json {
  my ($self, $cb) = @_;
#  $self->read;
  my $obj = {
             map { $_ => $self->{$_} } ($self->fields)
            };
  if($cb) {
    $cb->($obj);
  }

  return JSON->new->encode($obj);
}

1;
__END__

=head1 NAME

ClearPress::model - a base class for the data-model of the ClearPress MVC family

=head1 VERSION

$Revision: 470 $

=head1 SYNOPSIS

 use strict;
 use warning;
 use base qw(ClearPress::model);

 __PACKAGE__->mk_accessors(__PACKAGE__->fields());

 sub fields { return qw(...); }

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 fields

  my @aFields = $oModel->fields();
  my @aFields = __PACKAGE__->fields();

=head2 primary_key - usually the first element of fields();

  my $sPrimaryKey = $oModel->primary_key();

=head2 secondary_key - alternative key, usually a unique, non-numeric name to complement the primary_key

  my $sSecondaryKey = $oModel->secondary_key();

=head2 table - database table name this class represents

  my $sTableName = $oModel->table();

=head2 init - post-constructor hook, called by new();

=head2 new - Constructor

  my $oInstance = ClearPress::model::subclass->new();

  also supports creation with a hashref of key:values and creation
  with a scalar primary key, e.g.

  my $oInstance = ClearPress::model::subclass->new({id_subclass => 10});

  my $oInstance = ClearPress::model::subclass->new(10);

=head2 util - ClearPress::util (or subclass) object

  my $oUtil = ClearPress::model::subclass->util();

  my $oUtil = $oInstance->util();

=head2 get - generic 'get' accessor, derived from Class::Accessor.

 Invokes $self->read() if necessary.

 my $sFieldValue = $oModel->get($sFieldName);

=head2 gen_getarray - Arrayref of objects of a given type for a given database query

  my $arObjects = $oModel->gen_getarray('ClearPress::model::subclass',
                                        q(SELECT a,b,c FROM x,y WHERE x.d=? AND y.e=?),
                                        @bind_params);

=head2 gen_getall - Arrayref of all objects of type (ref $self) or a given class

  my $arObjects = $oModel->gen_getall();
  my $arObjects = $oModel->gen_getall('ClearPress::otherclass');

=head2 gen_getobj - An object of a given class based on the value of
the primary key in that class equalling the value in the same
field-name in this object.

  my $oObj = $self->gen_getobj($sClass);

=head2 gen_getfriends - arrayref of relatives related by this model's primary key

  my $arObjects = $oModel->gen_getfriends($sClass);
  my $arObjects = $oModel->gen_getfriends($sClass, $sCacheKey);

=head2 gen_getfriends_through - arrayref of relatives related by this model's primary key through an additional join table

  my $arObjects = $oModel->gen_getfriends($sClass, $sJoinTable);
  my $arObjects = $oModel->gen_getfriends($sClass, $sJoinTable, $sCacheKey);

=head2 gen_getobj_through - fetch a relative through a join table

  my $oRelative = $oModel->gen_getobj_through($sClass, $sJoinTable);
  my $oRelative = $oModel->gen_getobj_through($sClass, $sJoinTable, $sCacheKey);

=head2 has_a - one:one package relationship

  __PACKAGE__->has_a('my::pkg');
  __PACKAGE__->has_a(['my::pkg1', 'my::pkg2']);
  __PACKAGE__->has_a({method => 'my::fieldpkg'});
  __PACKAGE__->has_a([{method_one => 'my::pkg1'},
                      {method_two => 'my::pkg2'});

=head2 has_many - one:many package relationship

  __PACKAGE__->has_many('my::pkg');

 If my::pkg has a table of "package" then this creates a method "sub
 packages" in $self, yielding an arrayref of my::pkg objects related
 by the primary_key of $self.

  __PACKAGE__->has_many(['my::pkg1', 'my::pkg2']);

 Define multiple relationships together.


  __PACKAGE__->has_many({method => 'my::fieldpkg'});

 Defines a method "sub methods" in $self yielding an arrayref of
 my::fieldpkg objects related by the primary_key of $self.

  __PACKAGE__->has_many([{method_one => 'my::pkg1'},
                         {method_two => 'my::pkg2'});

 Defines multiple relationships with overridden method names.

=head2 hasa - deprecated synonym for has_a()

=head2 belongs_to - synonym for has_a()

=head2 hasmany - deprecated synonym for has_many()

=head2 has_many_through - arrayref of related entities through a join table

  Define a 'users' method in this class which fetches users like so:

    SELECT u.id_user, u.foo, u.bar
    FROM   user f, centre_user t
    WHERE  t.id_this = ?           # the primary_key for $self's class
    AND    t.id_user = f.id_user   # the primary_key for friend 'user'

  __PACKAGE__->has_many_through(['user|centre_user']);

=head2 has_a_through - a one-to-one relationship, like has_a, but through a join table

  __PACKAGE__->has_a_through(['user|friend', 'user|enemy']);

=head2 belongs_to_through - synonym for has_a_through

=head2 has_all - allows fetching of all entities of this type

  __PACKAGE__->has_all();

=head2 create - Generic INSERT into database

  $oModel->create();

=head2 read - Generic lazy-load from the database

  $oModel->load();

=head2 update - Generic UPDATE into database against primary_key

  $oModel->update();

=head2 delete - Generic delete from database

  $oModel->delete();

=head2 save - Generic save object to database

  $oModel->save();

=head2 zdate - Generic Zulu-date based on object's date() method or gmtime

  my $sZuluTime = $oModel->zdate();

=head2 isodate - Generic iso-formatted date YYYY-MM-DD HH:MM:SS for gmtime

  my $sISODate = $oModel->isodate();

=head2 as_json - JSON representation of this object

  my $sJSON = $oModel->as_json();

=head2 as_xml - XML representation of this object

  my $oXML = $oModel->as_xml();

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

 Pluralisation behaviour:
  Default is Lingua::EN::Inflect PL(X)

 Set $ClearPress::model::EXPERIMENTAL_PL = 1 to use:

   PL(to_singular(X)); provided by Lingua::EN::Inflect and Lingua::EN::PluralToSingular

=head1 DEPENDENCIES

=over

=item strict

=item warnings

=item base

=item Class::Accessor

=item ClearPress::util

=item English

=item Carp

=item Lingua::EN::Inflect

=item Lingua::EN::PluralToSingular

=item POSIX

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Roger Pettett, E<lt>rpettett@cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2008 Roger Pettett

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

=cut
