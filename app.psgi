use strict;
use warnings;
use Twiggy::Server;
use Plack::Request;
use Plack::App::File;
use DBI;
use JSON 'to_json';

my $server = Twiggy::Server->new(
    port => ($ENV{QS_DATABASE_PORT} or die "QS_DATABASE_PORT env var required"),
);

my $db_file = ($ENV{QS_DATABASE_FILE} or die "QS_DATABASE_FILE env var required");
my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", { RaiseError => 1 });

my $insert_sth = $dbh->prepare("INSERT INTO events (timestamp, type, uri, metadata, isDiscrete, isStart, otherEndpoint, duration) VALUES (?, ?, ?, ?, ?, ?, ?, ?);");
my @all_fields = qw/timestamp type uri metadata isDiscrete isStart otherEndpoint duration/;
my @required_fields = qw/timestamp type isDiscrete/;
my @optional_fields = qw/uri metadata isStart otherEndpoint duration/;

my $listall_sth = $dbh->prepare("SELECT events.id, events.timestamp, events.type, events.uri, events.metadata, events.isDiscrete, events.isStart, events.otherEndpoint, events.duration FROM events ORDER BY events.timestamp DESC LIMIT ?;");
my $list_sth = $dbh->prepare("SELECT events.id, events.timestamp, events.type, events.uri, events.metadata, events.isDiscrete, events.isStart, events.otherEndpoint, events.duration FROM events JOIN event_types ON events.type = event_types.id WHERE event_types.materialized_path LIKE (SELECT (materialized_path || '%') FROM event_types WHERE id=?) ORDER BY events.timestamp DESC LIMIT ?;");

my @Subscribers;

use Plack::Builder;
my $app = builder {
    enable "+QS::Middleware::Auth", dbh => $dbh;

    mount "/static" => Plack::App::File->new(root => "static/")->to_app;

    mount "/add" => sub {
        my $request = Plack::Request->new(shift);
        my %args;

        for my $key (@required_fields) {
            if (!defined($request->param($key))) {
                return [400, ['Content-Type', 'text/plain'], ["Field '$key' required"]];
            }
        }

        for my $key (@required_fields, @optional_fields) {
            $args{$key} = $request->param($key);
        }

        $args{timestamp} = time if $args{timestamp} eq 'now';

        if (!$args{isDiscrete}) {
            delete $args{isStart};
            delete $args{otherEndpoint};
            delete $args{duration};
        }

        my $ok = $insert_sth->execute(@args{@all_fields});
        if ($ok) {
            my $event = to_json(\%args) . "\n";
            for (@Subscribers) {
                $_->write($event);
            }

            return [201];
        }
        else {
            return [400];
        }
    };

    mount "/types" => sub {
        my @types = $dbh->selectall_array("SELECT id, parent, label, tags, materialized_path FROM event_types;");
        my %tree;
        my @parents = [0, \%tree];
        while (@parents) {
            my ($parent_id, $parent_tree) = @{ shift @parents };
            my @children = grep { $_->[1] == $parent_id } @types;
            @types = grep { $_->[1] != $parent_id } @types;

            for (@children) {
                my ($id, undef, $label, $tags, $materialized_path) = @$_;
                my %subtree = (
                    label => $label,
                    tags => $tags,
                    materialized_path => $materialized_path,
                );
                $parent_tree->{$id} = \%subtree;
                push @parents, [$id, \%subtree];
            }
        }

        return [200, ['Content-Type', 'application/json'], [
            to_json(\%tree),
        ]];
    };

    mount "/events" => sub {
        my $req = Plack::Request->new(shift);
        my $sth = $listall_sth;
        if (my $type = $req->param('type')) {
            $sth = $list_sth;
            $sth->execute($type, 10);
        }
        else {
            $sth->execute(10);
        }

        my @results;
        while (my $row = $sth->fetchrow_hashref) {
            push @results, $row;
        }

        return [200, ['Content-Type', 'application/json'], [
            to_json(\@results),
        ]];
    };

    mount "/subscribe" => sub {
        my $env = shift;
        my $req = Plack::Request->new($env);
        $env->{'plack.skip-deflater'} = 1;

        return sub {
            my $responder = shift;
            my $writer = $responder->([200, ['Content-Type' => 'application/json', 'Cache-control' => 'private, max-age=0, no-store']]);
            push @Subscribers, $writer;
        };
    };
};

$server->register_service($app);

AE::cv->recv;
