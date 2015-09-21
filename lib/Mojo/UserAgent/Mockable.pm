use 5.014;
package Mojo::UserAgent::Mockable;

# ABSTRACT: A Mojo User-Agent that can record and play back requests without Internet connectivity, similar to LWP::UserAgent::Mockable

use Mojo::Base 'Mojo::UserAgent';
use Mojo::Message::Serializer;

has 'action' => 'passthrough';

# Connection handled by Mojo::IOLoop::Client::connect


1;
