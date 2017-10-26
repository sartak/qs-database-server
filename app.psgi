use strict;
use warnings;

return sub {
    return [ 200, ['Content-Type', 'text/html'], ['<h1>Hello world!</h1>'] ];
};

