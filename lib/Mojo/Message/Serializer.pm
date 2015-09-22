use 5.014;

package Mojo::Message::Serializer;

use warnings::register;

use Carp;
use Class::Load ':all';
use Data::Serializer::Raw;
use File::Slurp qw/slurp write_file/;
use MooseX::Singleton;
use MooseX::AttributeShortcuts;
use Safe::Isa (qw/$_isa/);
use Mojo::JSON qw/encode_json decode_json/;

has _serializer => ( is => 'lazy', isa => 'Data::Serializer::Raw', builder => sub { Data::Serializer::Raw->new(); } );

# ABSTRACT

# VERSION

=head1 SYNOPSIS

    use Mojo::Message::Serializer;
    use File::Slurp;

    my $ua = Mojo::UserAgent->new;

    my $tx = $ua->get('http://example.com');

    my $json = Mojo::Message::Serializer->serialize($tx->req);

    write_file('/path/to/file.json', $json);

    # Later...

    my $json = read_file('/path/to/file.json');
    my $reconstituted_request = Mojo::Message::Serializer->deserialize($json);

=head1 EVENTS

This module does not itself emit any events. However, messages serialized using this module will
re-emit any events they previously emitted, as well as the following:

=head2 pre_freeze
    
    $message->on(freeze => sub {
        my $msg = shift;
        ...
    });

Emitted immediately before the message is serialized.

=head2 post_freeze

Emitted immediately after the message is serialized. See L</DATA STRUCTURE> for details of the 
frozen format.

    $message->on(post_freeze => sub {
        my $msg = shift;
        my $frozen = shift;
        ...
    });

=head2 thaw

Emitted immediately after the message is unserialized. NOTE: The only way to access this event is 
by passing a subscriber to L</deserialize>.

=head1 DATA STRUCTURE

L<serialize> produces, and L<deserialize> expects, JSON data with the following keys:

=for :list
= 'class'
The class name of the serialized object.  This should be a subclass of L<Mojo::Message>
= 'events'
Array of events with subscribers in the serialized object. These events will be re-emitted after 
the L</thaw> event is emitted, but any subscribers present in the original object will be lost.
= 'body'
The raw HTTP message body.

=head1 CAVEATS

At present, this module does not serialize any event listeners.  This may change in future releases.

=method serialize

Serialize or freeze an instance of L<Mojo::Message>.  Takes a single argument, the message to be 
serialized.  This method will generate a warning if the instance has any subscribers (see 
L<Mojo::EventEmitter/on>).  Suppress this warning with (e.g.):

  no warnings 'Mojo::Message::Serializer';
  $serializer->serialize($message);
  use warnings 'Mojo::Message::Serializer';

=method deserialize

Deserialize or thaw a previously serialized instance of L<Mojo::Message>. Arguments:

=for :list
= $data 
Serialized object to deserialize
= %subscriptions
Hash of events to subscribe to on the deserialized object.  See L<Mojo::EventEmitter/on>.

=method store

Serialize an instance of L<Mojo::Message> and write it to the given file or file handle.  Takes two
arguments:

=for :list
= $message
Instance of L<Mojo::Message> to serialize
= $file 
File or handle to write serialized object to.
 
=method retrieve

Read from the specified file or file handle and deserialize an instance of L<Mojo::Message> from 
the data read.  If a file handle is passed, data will be read until an EOF is received.

=cut

my $WARNING_CATEGORY = __PACKAGE__ . '::event';

sub serialize {
    my ($self, $message) = @_;

    if (!$message->$_isa('Mojo::Message')) {
        croak q{Only instances of Mojo::Message may be serialized using this class};
    }

    $message->emit('pre_freeze');

    my $slush = {
        'class' => ref $message,
        'body' => $message->to_string,
    };
    for my $event (keys %{$message->{'events'}}) {
        next if $event eq 'pre_freeze' or $event eq 'post_freeze';
        carp(qq{Subscriber for event "$event" not serialized}) if warnings::enabled; 
        push @{$slush->{'events'}}, $event;
    }
    $message->emit('post_freeze', $slush);

    return encode_json($slush);
}

sub deserialize { 
    my ($self, $frozen, %subscriptions) = @_;

    my $slush = decode_json($frozen);

    my $class = $slush->{'class'};
    if (!$class) {
        croak q{Invalid serialized data: Missing required key 'class'.};
    }
    
    load_class($class);
    my $obj = $class->new();

    if (!$obj->$_isa('Mojo::Message')) {
        croak q{Only instances of Mojo::Message may be deserialized using this class};
    }
    for my $event (keys %subscriptions) {
        $obj->on($event => $subscriptions{$event});
    }

    $obj->parse($slush->{'body'});
    for my $event (@{$slush->{'events'}}) {
        $obj->emit($event, $slush);
    }

    $obj->emit('thaw', $slush);

    return $obj;
}

sub store {
    my ($self, $message, $file) = @_;

    my $serialized = $self->serialize($message);
    write_file($file, $serialized);
}

sub retrieve {
    my ($self, $file, %subscriptions) = @_;

    my $contents = slurp($file);
    return $self->deserialize($contents, %subscriptions);
}
1;
