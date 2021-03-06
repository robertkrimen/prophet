#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 24;
use Test::Exception;
use File::Temp 'tempdir';
use Params::Validate;

my ($bug_uuid, $pullall_uuid);

my $alice_published = tempdir(CLEANUP => ! $ENV{PROPHET_DEBUG});

as_alice {
    run_ok('prophet', [qw(init)]);
    run_output_matches( 'prophet',
        [qw(create --type Bug -- --status new --from alice )],
        [qr/Created Bug \d+ \((\S+)\)(?{ $bug_uuid = $1 })/],
        "Created a Bug record as alice");
    ok($bug_uuid, "got a uuid for the Bug record");
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], [], " Found our record" );
    run_ok( 'prophet', [qw(publish --to), $alice_published] );
};

my $path =$alice_published;

as_bob {
    run_ok( 'prophet', ['clone', '--from', "file://$path"] );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], [], " Found our record" );
};
as_alice {
    run_output_matches( 'prophet',
        [qw(create --type Pullall -- --status new --from alice )],
        [qr/Created Pullall \d+ \((\S+)\)(?{ $pullall_uuid = $1 })/],
        [],
        "Created a Pullall record as alice");
    ok($pullall_uuid, "got a uuid $pullall_uuid for the Pullall record");

    run_ok( 'prophet', [qw(publish --to), $alice_published] );
};

as_bob {
    run_ok( 'prophet', ['pull', '--all'] );
    run_output_matches( 'prophet', [qw(search --type Pullall --regex .)], [qr/new/], [], " Found our record" );
};


as_charlie {
    run_ok( 'prophet', ['clone', '--from', "file://$path"] );
};

is(database_uuid_for('alice'), database_uuid_for('charlie'), "pull propagated the database uuid properly");
isnt(replica_uuid_for('alice'), replica_uuid_for('charlie'), "pull created a new replica uuid");

as_alice { check_replica('alice') };
as_bob { check_replica('bob') };
as_charlie { check_replica('charlie') };

sub check_replica {

    my $user = shift;

    my $cli = Prophet::CLI->new();
    my $replica = $cli->handle;
    my $changesets = $replica->fetch_changesets(after => 0);

    is(@$changesets, 2, "two changesets for $user");

    changeset_ok(
        changeset   => $changesets->[0],
        user        => $user,
        record_type => 'Bug',
        record_uuid => $bug_uuid,
        sequence_no => 1,
        merge       => $user ne 'alice',
        name        => "$user\'s first changeset",
    );
    changeset_ok(
        changeset   => $changesets->[1],
        user        => $user,
        record_type => 'Pullall',
        record_uuid => $pullall_uuid,
        sequence_no => 2,
        merge       => $user ne 'alice',
        name        => "$user\'s second changeset",
    );
}

sub changeset_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my %args = validate(@_, {
        changeset   => 1,
        user        => 1,
        sequence_no => 1,
        record_type => 1,
        record_uuid => 1,
        merge       => 1,
        name        => 0,
    });

    my $changeset = $args{changeset}->as_hash;

    my $changes = {
        $args{record_uuid} => {
            change_type  => 'add_file',
            record_type  => $args{record_type},
            prop_changes => {
                status => {
                    old_value => undef,
                    new_value => 'new',
                },
                from => {
                    old_value => undef,
                    new_value => 'alice',
                },
                creator => {
                    old_value => undef,
                    new_value => 'alice',
                },
                original_replica => {
                    old_value => undef,
                    new_value => replica_uuid_for('alice'),
                },
            },
        },
    };

    if ($args{merge}) {
        my $change_type = $args{sequence_no} > 1
                        ? 'update_file'
                        : 'add_file';

        my $prev_changeset_num = $args{sequence_no} > 1
                               ? $args{sequence_no} - 1
                               : undef;

    }

    is_deeply($changeset, {
        creator              => 'alice',
        created              => $changeset->{created},
        is_resolution        => undef,
        is_nullification     => undef,
        sequence_no          => $args{sequence_no},
        source_uuid          => replica_uuid_for($args{user}),
        original_sequence_no => $args{sequence_no},
        original_source_uuid => replica_uuid_for('alice'),
        changes              => $changes,
    }, $args{name});
}

