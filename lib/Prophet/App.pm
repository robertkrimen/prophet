package Prophet::App;
use Any::Moose;
use File::Spec ();
use Prophet::Config;
use Params::Validate qw/validate validate_pos/;

has handle => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;

        if ( ! $ENV{PROPHET_REPO}) { 
            my $type = $self->default_replica_type;
            $ENV{'PROPHET_REPO'} = $type.":file://".File::Spec->catdir($ENV{'HOME'}, '.prophet');

        }
        elsif   ($ENV{'PROPHET_REPO'} !~ /^[\w\+]+\:/ ) {
            if ( !File::Spec->file_name_is_absolute($ENV{'PROPHET_REPO'}) ) {
            # if PROPHET_REPO env var exists and is relative, make it absolute
            # to avoid breakage/confusing error messages later
            $ENV{'PROPHET_REPO'} = $self->default_replica_type . ":file://".  File::Spec->rel2abs(glob($ENV{'PROPHET_REPO'}));

            } else {
            $ENV{'PROPHET_REPO'} = $self->default_replica_type . ":file://".  $ENV{'PROPHET_REPO'};
            }
        }

        return Prophet::Replica->get_handle( url =>  $ENV{'PROPHET_REPO'}, app_handle => $self, );
    },
);

has resdb_handle => (
    is      => 'rw',
    isa     => 'Prophet::Replica',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->handle->resolution_db_handle
            if $self->handle->resolution_db_handle;
        my $root = ($ENV{'PROPHET_REPO'} || File::Spec->catdir($ENV{'HOME'}, '.prophet')) . "_res";
        my $type = $self->default_replica_type;
        my $r = Prophet::Replica->get_handle( url => $type.':file://' . $root );
        if (!$r->replica_exists && $r->can_initialize) { $r->initialize}

        return $r;
    },
);

has config => (
    is      => 'rw',
    isa     => 'Prophet::Config',
    default => sub {
        my $self = shift;
        return Prophet::Config->new(app_handle => $self);
    },
    documentation => "This is the config instance for the running application",
);

use constant DEFAULT_REPLICA_TYPE => 'prophet';

=head1 NAME

Prophet::App

=head1 SYNOPSIS

=head1 METHODS

=head2 BUILD

=cut

=head2 default_replica_type

Returns a string of the the default replica type for this application.

=cut

sub default_replica_type {
    my $self = shift;
    return $ENV{'PROPHET_REPLICA_TYPE'} || DEFAULT_REPLICA_TYPE;
}

=head2 require

=cut

sub require {
    my $self = shift;
    my $class = shift;
    $self->_require(module => $class);
}

=head2 try_to_require

=cut

sub try_to_require {
    my $self = shift;
    my $class = shift;
    $self->_require(module => $class, quiet => 1);
}

=head2 _require

=cut

sub _require {
    my $self = shift;
    my %args = ( module => undef, quiet => undef, @_);
    my $class = $args{'module'};

    # Quick hack to silence warnings.
    # Maybe some dependencies were lost.
    unless ($class) {
        warn sprintf("no class was given at %s line %d\n", (caller)[1,2]);
        return 0;
    }

    return 1 if $self->already_required($class);

    # .pm might already be there in a weird interaction in Module::Pluggable
    my $file = $class;
    $file .= ".pm"
        unless $file =~ /\.pm$/;

    $file =~ s/::/\//g;

    my $retval = eval {
        local $SIG{__DIE__} = 'DEFAULT';
        CORE::require "$file"
    };

    my $error = $@;
    if (my $message = $error) {
        $message =~ s/ at .*?\n$//;
        if ($args{'quiet'} and $message =~ /^Can't locate \Q$file\E/) {
            return 0;
        }
        elsif ( $error !~ /^Can't locate $file/) {
            die $error;
        } else {
            warn sprintf("$message at %s line %d\n", (caller(1))[1,2]);
            return 0;
        }
    }

    return 1;
}

=head2 already_required class

Helper function to test whether a given class has already been require'd.

=cut

sub already_required {
    my ($self, $class) = @_;

    return 0 if $class =~ /::$/;    # malformed class

    my $path =  join('/', split(/::/,$class)).".pm";
    return ( $INC{$path} ? 1 : 0);
}

sub set_db_defaults {
    my $self = shift;
    my $settings = $self->database_settings;
    for my $name ( keys %$settings ) {
        my ($uuid, @metadata) = @{$settings->{$name}};

        my $s = $self->setting(
            label   => $name,
            uuid    => $uuid,
            default => \@metadata,
        );

        $s->initialize;
    }
}

sub setting {
    my $self = shift;
    my %args = validate( @_, { uuid => 0, default => 0, label => 0 } );
    require Prophet::DatabaseSetting;

    my  ($uuid, $default);

    if ( $args{uuid} ) {
        $uuid = $args{'uuid'};
        $default = $args{'default'};
    } elsif ( $args{'label'} ) {
        ($uuid, $default) = @{ $self->database_settings->{ $args{'label'} }};
    }
    return Prophet::DatabaseSetting->new(
        handle  => $self->handle,
        uuid    => $uuid,
        default => $default,
        label   => $args{label}
    );

}

sub database_settings {} # XXX wants a better name


=head3 log $MSG

Logs the given message to C<STDERR> (but only if the C<PROPHET_DEBUG>
environmental variable is set).

=cut

sub log_debug {
    my $self = shift;
    return unless ($ENV{'PROPHET_DEBUG'});
    $self->log(@_);
}

sub log {
    my $self = shift;
    my ($msg) = validate_pos(@_, 1);
    print STDERR $msg."\n";# if ($ENV{'PROPHET_DEBUG'});
}

=head2 log_fatal $MSG

Logs the given message and dies with a stack trace.

=cut

sub log_fatal {
    my $self = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;

    $self->log(@_);
    Carp::confess(@_);
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;
1;
