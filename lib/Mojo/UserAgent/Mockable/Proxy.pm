use 5.016;

package Mojo::UserAgent::Mockable::Proxy;
use Mojo::Base 'Mojo::UserAgent::Proxy';

1;
sub detect { # Do not set any proxy 
    return; 
}

