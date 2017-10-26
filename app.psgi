use strict;
use warnings;
use Plack::Request;

my @events;
return sub {
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

