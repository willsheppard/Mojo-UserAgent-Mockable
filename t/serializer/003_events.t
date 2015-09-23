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
my $req        = Mojo::Message::Request->new;
my $cookie     = 'foo=bar';
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
my %subscriptions = map {
    my $event = $_;
    $event => sub { $events{$event} = 1; }
} @expected_events;

my $r2 = $serializer->deserialize( $serialized, %subscriptions );

for my $event (@expected_events) {
    is $events{$event}, 1, qq{Event "$event" fired};
}
done_testing;
