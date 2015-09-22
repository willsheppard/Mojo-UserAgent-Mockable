use 5.014;
use File::Temp;
use Test::Most;
use Test::JSON;
use Mojo::JSON;
use Mojo::Message::Serializer;
use Mojo::Message::Request;
use Mojo::Message::Response;
use Mojo::UserAgent;
use Mojolicious::Quick;

my $serializer = Mojo::Message::Serializer->new;

subtest 'simple request' => sub {
    my $req    = Mojo::Message::Request->new;
    my $cookie = 'foo=bar';
    $req->parse("PUT /upload HTTP/1.1\x0d\x0aCookie: $cookie; sessionID=OU812\x0d\x0a");
    $req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");

    my $expected_body = $req->to_string;
    my $serialized = $serializer->serialize($req);
    my $slush = Mojo::JSON::decode_json($serialized);
    is $slush->{'class'}, 'Mojo::Message::Request', 'class correct';
    is $slush->{'body'}, $expected_body, 'Body correct';  

    $req = undef;

    my $r2 = $serializer->deserialize($serialized);
    is $r2->method,  'PUT',     'right method';
    is $r2->version, '1.1',     'right version';
    is $r2->url,     '/upload', 'right URL';
    is $r2->cookie('foo')->value, 'bar', 'cookie matches';
    is $r2->cookie('sessionID')->value, 'OU812', 'cookie matches';
};

subtest 'Multipart' => sub {
    my $app = Mojolicious::Quick->new(
        [   '/target' => sub {
                my $c = shift;
                $c->render('OK');
            }
        ]
    );
    my $ua = $app->ua;
    my $tx = $ua->post(
        '/target' => {
            'X-Zaphod-Last-Name'                => 'Beeblebrox',
            'X-Benedict-Cumberbatch-Silly-Name' => 'Bumbershoot Crinklypants',
            'Cookie'                            => 'foo=bar; sessionID=OU812; datingMyself=yes',
            } => form =>
            { foo => 'bar', quux => 'quuy', thefile => { file => q{/Users/kipeters/Documents/sample.txt} } }
    );

    my %headers = %{$tx->req->headers->to_hash};
    my @assets = map { $_->asset->slurp } @{$tx->req->content->parts};
    my $url = $tx->req->url;
    
    my $serialized = $serializer->serialize($tx->req);
    $tx = undef;

    my $req2 = $serializer->deserialize($serialized);

    subtest 'headers match both ways' => sub {
        for my $key ( keys %headers ) {
            my $expected_header = $headers{$key};
            my $got_header      = $req2->headers->header($key);
            is( $got_header, $expected_header, qq{Header '$key' OK} );
        }
        for my $key ( keys %{ $req2->headers->to_hash } ) {
            my $got_header      = $headers{$key};
            my $expected_header = $req2->headers->header($key);
            is( $got_header, $expected_header, qq{Header '$key' OK} );
        }
    };

    is( $req2->url->path, $url->path, 'path match' );
    
    is( scalar @{$req2->content->parts}, scalar @assets, q{Asset count matches} );
    for ( 0 .. $#{ $req2->content->parts } ) {
        my $got = $req2->content->parts->[$_]->asset->slurp;
        my $expected = $assets[$_];
        is $got, $expected, qq{Chunk $_ matches};
    }
};

subtest 'events' => sub {
    my $req    = Mojo::Message::Request->new;
    my $cookie = 'foo=bar';
    $req->parse("PUT /upload HTTP/1.1\x0d\x0aCookie: $cookie; sessionID=OU812\x0d\x0a");
    $req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");

    my %events;
    $req->on(
        pre_freeze => sub {
            my ($message) = @_;
            isa_ok( $message, 'Mojo::Message::Request' );
            $events{'pre_freeze'} = 1;
        }
    );
    $req->on(
        post_freeze => sub {
            my ( $message, $slush ) = @_;
            isa_ok( $message, 'Mojo::Message::Request' );
            is ref $slush, 'HASH', 'slush is a hashref';
            is $slush->{'class'}, 'Mojo::Message::Request', 'Class correct';
            $events{'post_freeze'} = 1;
        }
    );

    my $serialized;
    lives_ok { $serialized = $serializer->serialize($req); } 'Serialize() did not die';
    $req = undef;

    my @expected_events = qw/
        pre_freeze post_freeze thaw finish progress
        /;
    my %subscriptions = map { my $event = $_; $event => sub { $events{$event} = 1; } } @expected_events;

    my $r2 = $serializer->deserialize($serialized, %subscriptions);

    for my $event (@expected_events) {
        is $events{$event}, 1, qq{Event "$event" fired};
    }
};

subtest 'store and retrieve' => sub {
    my $req    = Mojo::Message::Request->new;
    $req->parse("PUT /upload HTTP/1.1\x0d\x0aCookie: foo=bar; sessionID=OU812\x0d\x0a");
    $req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");

    my %events;
    $req->on(
        pre_freeze => sub {
            my ($message) = @_;
            isa_ok( $message, 'Mojo::Message::Request' );
            $events{'pre_freeze'} = 1;
        }
    );
    $req->on(
        post_freeze => sub {
            my ( $message, $slush ) = @_;
            isa_ok( $message, 'Mojo::Message::Request' );
            is ref $slush, 'HASH', 'slush is a hashref';
            is $slush->{'class'}, 'Mojo::Message::Request', 'Class correct';
            $events{'post_freeze'} = 1;
        }
    );

    my $temp = File::Temp->new();
    lives_ok { $serializer->store($req, $temp->filename); } 'store() did not die';
    $temp->flush;
    $req = undef;

    my @expected_events = qw/
        pre_freeze post_freeze thaw finish progress
        /;
    my %subscriptions = map { my $event = $_; $event => sub { $events{$event} = 1; } } @expected_events;
    
    my $obj;
    lives_ok { $obj = $serializer->retrieve($temp->filename, %subscriptions) } 'retrieve() did not die';

    for my $event (@expected_events) {
        is $events{$event}, 1, qq{Event "$event" fired};
    }
};

done_testing;
