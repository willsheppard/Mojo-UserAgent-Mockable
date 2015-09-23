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
    } => form => { foo => 'bar', quux => 'quuy', thefile => { file => q{/Users/kipeters/Documents/sample.txt} } }
);

my %headers = %{ $tx->req->headers->to_hash };
my @assets  = map { $_->asset->slurp } @{ $tx->req->content->parts };
my $url     = $tx->req->url;

my $serialized = $serializer->serialize( $tx->req );
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

is( scalar @{ $req2->content->parts }, scalar @assets, q{Asset count matches} );
for ( 0 .. $#{ $req2->content->parts } ) {
    my $got      = $req2->content->parts->[$_]->asset->slurp;
    my $expected = $assets[$_];
    is $got, $expected, qq{Chunk $_ matches};
}

done_testing;
