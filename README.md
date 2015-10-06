# NAME

Mojo::UserAgent::Mockable - A Mojo User-Agent that can record and play back requests without Internet connectivity, similar to LWP::UserAgent::Mockable

# VERSION

version 0.001

# SYNOPSIS

    my $ua = Mojo::UserAgent::Mockable->new( mode => 'record', file => '/path/to/file' );
    my $tx = $ua->get($url);

    # Then later...
    my $ua = Mojo::UserAgent::Mockable->new( mode => 'playback', file => '/path/to/file' );
    
    my $tx = $ua->get($url); 
    # This is the same content as above. The saved response is returned, and no HTTP request is
    # sent to the remote host.
    my $reconstituted_content = $tx->res->body;

# ATTRIBUTES

## mode

Mode to operate in.  One of:

- passthrough

    Operates like [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) in all respects. No recording or playback happen.

- record

    Records all transactions made with this instance to the file specified by ["file"](#file).

- playback

    Plays back transactions recorded in the file specified by ["file"](#file)

- lwp-ua-mockable

    Works like [LWP::UserAgent::Mockable](https://metacpan.org/pod/LWP::UserAgent::Mockable). Set the LWP\_UA\_MOCK environment variable to 'playback', 
    'record', or 'passthrough', and the LWP\_UA\_MOCK\_FILE environment variable to the recording file.

## file

File to record to / play back from.a

## unrecognized

What to do on an unexpected request.  One of:

- exception

    Throw an exception (i.e. die).

- null

    Return a response with empty content

- fallback

    Process the request as if this instance were in "passthrough" mode and perform the HTTP request normally.

## serializer

Class that will be used to serialize messages.  [Mojo::Message::Serializer](https://metacpan.org/pod/Mojo::Message::Serializer) by default.

## ignore\_headers

Request header names to ignore when comparing a request made with this class to a stored request in 
playback mode. Specify 'all' to remove any headers from consideration. By default, the 'Connection',
'Host', 'Content-Length', and 'User-Agent' headers are ignored.

# THEORY OF OPERATION

## Recording mode

For the life of a given instance of this class, all transactions made using that instance will be 
serialized by means of the class specified by ["serializer"](#serializer) and stored in memory.  When that 
instance goes out of scope, the transaction cache will be written to the file specfied by ["file"](#file)
in JSON format in the order they were made.  

## Playback mode

When this class is instantiated, the instance will read the transaction cache from the file 
specified by ["file"](#file). When a request is first made using the instance, if the request matches 
that of the first transaction in the cache, the request URL will be rewritten to that of the local 
host, and the response from the first stored transaction will be returned to the caller. Each 
subsequent request will be handled similarly, and requests must be made in the same order as they 
were originally made, i.e. if orignally the request order was A, B, C, with responses A', B', C',
requests in order A, C, B will NOT return responses A', C', B'. Request A will correctly return 
response A', but request C will trigger an error (behavior configurable by the ["unrecognized"](#unrecognized)
option).

### Request matching

Two requests are considered to be equivalent if they have the same URL (order of query parameters
notwithstanding), the same body content, and the same headers.  You may exclude headers from 
consideration by means of the ["ignore\_headers"](#ignore_headers) attribute.

# CAVEATS

## Local application server

Using this module against a local app, e.g.: 

    my $app = Mojolicious->new;
    ...

    my $ua = Mojo::UserAgent::Mockable->new;
    $ua->server->app($app);

Doesn't work, because in playback mode, requests are served from an internal Mojolicious instance.
So if you blow that away, the thing stops working, natch.

# AUTHOR

Kit Peters &lt;kit.peters@broadbean.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Broadbean Technology.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
