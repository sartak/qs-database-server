use strict;
use warnings;
use Twiggy::Server;
use Plack::Request;
use Plack::App::File;

my $server = Twiggy::Server->new(
    port => ($ENV{QS_DATABASE_PORT} or die "QS_DATABASE_PORT env var required"),
);

my $db_file = ($ENV{QS_DATABASE_FILE} or die "QS_DATABASE_FILE env var required");
my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "");

my $app = sub {
    my $request = Plack::Request->new(shift);
};

use Plack::Builder;
$app = builder {
    enable "+QS::Middleware::Auth", dbh => $dbh;
    mount "/static" => Plack::App::File->new(root => "static/")->to_app;
    mount "/" => $app;
};

$server->register_service($app);

AE::cv->recv;
