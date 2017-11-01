use strict;
use warnings;
use Twiggy::Server;
use Plack::Request;

my $server = Twiggy::Server->new(
    port => ($ENV{QS_DATABASE_PORT} or die "QS_DATABASE_PORT env var required"),
);

my @events;
my $app = sub {
    my $request = Plack::Request->new(shift);
    if (my $event = $request->parameters->{event}) {
        push @events, [$event, time];
    }

    return [ 200, ['Content-Type', 'text/html'], [
      "<ul>",
      (map { "<li>$_->[0] (" . (time - $_->[1]) . "s ago)</li>" } @events),
      "</ul>",
    ] ];
};

$server->register_service($app);

AE::cv->recv;
