use strict;
use warnings;
use Twiggy::Server;
use Plack::Request;
use Plack::App::File;
use DBI;

my $server = Twiggy::Server->new(
    port => ($ENV{QS_DATABASE_PORT} or die "QS_DATABASE_PORT env var required"),
);

my $db_file = ($ENV{QS_DATABASE_FILE} or die "QS_DATABASE_FILE env var required");
my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", { RaiseError => 1 });

my $insert_sth = $dbh->prepare("INSERT INTO events (timestamp, type, uri, metadata, isDiscrete, isStart, otherEndpoint, duration) VALUES (?, ?, ?, ?, ?, ?, ?, ?);");
my @all_fields = qw/timestamp type uri metadata isDiscrete isStart otherEndpoint duration/;
my @required_fields = qw/timestamp type isDiscrete/;
my @optional_fields = qw/uri metadata isStart otherEndpoint duration/;

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
            return [201];
        }
        else {
            return [400];
        }
    };
};

$server->register_service($app);

AE::cv->recv;
