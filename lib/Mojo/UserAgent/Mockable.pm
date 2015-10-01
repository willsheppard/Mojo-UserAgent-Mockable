use 5.014;

package Mojo::UserAgent::Mockable;

use warnings::register;

use Carp;
use File::Slurp;
use JSON::MaybeXS;
use Mojo::Base 'Mojo::UserAgent';
use Mojo::Util qw/secure_compare/;
use Mojo::UserAgent::Mockable::Serializer;
use Mojo::UserAgent::Mockable::Request::Compare;
use Mojo::JSON;
use TryCatch;

# ABSTRACT: A Mojo User-Agent that can record and play back requests without Internet connectivity, similar to LWP::UserAgent::Mockable

=head1 SYNOPSIS

    my $ua = Mojo::UserAgent::Mockable->new( mode => 'record', file => '/path/to/file' );
    my $tx = $ua->get($url);

    # Then later...
    my $ua = Mojo::UserAgent::Mockable->new( mode => 'playback', file => '/path/to/file' );
    
    my $tx = $ua->get($url); 
    # This is the same content as above. The saved response is returned, and no HTTP request is
    # sent to the remote host.
    my $reconstituted_content = $tx->res->body;

=attr mode

Mode to operate in.  One of:

=for :list
= passthrough
Operates like L<Mojo::UserAgent> in all respects. No recording or playback happen.
= record
Records all transactions made with this instance to the file specified by L</file>.
= playback
Plays back transactions recorded in the file specified by L</file>
= lwp-ua-mockable
Works like L<LWP::UserAgent::Mockable>. Set the LWP_UA_MOCK environment variable to 'playback', 
'record', or 'passthrough', and the LWP_UA_MOCK_FILE environment variable to the recording file.

=attr file

File to record to / play back from.a

=attr unrecognized

What to do on an unexpected request.  One of:

=for :list
= exception
Throw an exception (i.e. die).
= null
Return a response with empty content
= fallback
Process the request as if this instance were in "passthrough" mode and perform the HTTP request normally.

=attr serializer

Class that will be used to serialize messages.  L<Mojo::Message::Serializer> by default.

=attr ignore_headers

Request header names to ignore when comparing a request made with this class to a stored request in 
playback mode. Specify 'all' to remove any headers from consideration. By default, the 'Connection',
'Host', 'Content-Length', and 'User-Agent' headers are ignored.

=head1 THEORY OF OPERATION

=head2 Recording mode

For the life of a given instance of this class, all transactions made using that instance will be 
serialized by means of the class specified by L</serializer> and stored in memory.  When that 
instance goes out of scope, the transaction cache will be written to the file specfied by L</file>
in JSON format in the order they were made.  

=head2 Playback mode

When this class is instantiated, the instance will read the transaction cache from the file 
specified by L</file>. When a request is first made using the instance, if the request matches 
that of the first transaction in the cache, the request URL will be rewritten to that of the local 
host, and the response from the first stored transaction will be returned to the caller. Each 
subsequent request will be handled similarly, and requests must be made in the same order as they 
were originally made, i.e. if orignally the request order was A, B, C, with responses A', B', C',
requests in order A, C, B will NOT return responses A', C', B'. Request A will correctly return 
response A', but request C will trigger an error (behavior configurable by the L</unrecognized>
option).

=head3 Request matching

Two requests are considered to be equivalent if they have the same URL (order of query parameters
notwithstanding), the same body content, and the same headers.  You may exclude headers from 
consideration by means of the L</ignore_headers> attribute.

=cut

has 'mode' => 'passthrough';
has 'file';
has 'unrecognized' => 'exception';
has 'serializer' => sub { Mojo::UserAgent::Mockable::Serializer->new };
has 'comparator' => sub {
    Mojo::UserAgent::Mockable::Request::Compare->new( ignore_headers => 'all' );
        #        ignore_headers => [ 'Connection', 'Host', 'Content-Length', 'User-Agent' ] );
};
has 'ignore_headers' => sub { [] };
has '_mode';
has '_current_txn';
has '_compare_result';

# Internal Mojolicious app that handles transaction playback
has '_app' => sub {
    my $self = shift;
    my $app  = Mojolicious->new;
    $app->routes->any(
        '/*any' => { any => '' } => sub {
            my $c  = shift;
            my $tx = $c->tx;

            my $txn = $self->_current_txn;
            if ($txn) {
                $tx->res( $txn->res );
                $tx->res->headers->header( 'X-MUA-Mockable-Regenerated' => 1 );
                $c->rendered( $txn->res->code );
            }
            else {
                for my $header ( keys %{ $tx->req->headers->to_hash } ) {
                    if ( $header =~ /^X-MUA-Mockable/ ) {
                        my $val = $tx->req->headers->header($header);
                        $tx->res->headers->header( $header, $val );
                    }
                }
                $c->render( text => '' );
            }
        },
    );
    $app;
};

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{'_launchpid'} = $$;
    if ($self->mode eq 'lwp-ua-mockable') {
        $self->_mode($ENV{'LWP_UA_MOCK'});
        if ($self->file) {
            croak qq{Do not specify 'file' when 'mode' is set to 'lwp-ua-mockable'. Use the LWP_UA_MOCK_FILE } 
                 . q{environment var instead.};
        }
        $self->file($ENV{'LWP_UA_MOCK_FILE'});
    }
    else {
        $self->_mode($self->mode);
    }

    if ($self->_mode ne 'passthrough' && !$self->file) {
        croak qq{Error: You must specify a recording file};
    }

    if ($self->_mode ne 'passthrough') {
        my $mode = lc $self->_mode;
        if ($mode eq 'recording') {
            $mode = 'record';
        }
        my $mode_init = qq{_init_$mode}; 
        if (!$self->can($mode_init)) {
            croak qq{Error: unsupported mode "$mode"};
        }
        return $self->$mode_init;
    }

    return $self;
}

sub save {
    my ( $self, $file ) = @_;
    if ( $self->_mode eq 'record' ) {
        $file ||= $self->file;

        my $transactions = $self->{'_transactions'};
        $self->serializer->store($file, @{$transactions});
    }
    else {
        carp 'save() only works in record mode' if warnings::enabled;
    }
}

sub _init_playback {
    my $self = shift;

    $self->{'_transactions'} = [ $self->serializer->retrieve($self->file) ];

    $self->server->app($self->_app);

    $self->{'_events'}{'start'} = $self->on(
        start => sub {
            my ( $ua, $tx ) = @_;

            my $recorded_tx = shift @{ $self->{'_transactions'} };

            if ($self->comparator->compare( $tx->req, $recorded_tx->req )) { 
                $self->_current_txn($recorded_tx);
                $tx->req->url->host('')->scheme('')->port( $self->server->url->port );
            }
            else {
                my $result = $self->comparator->compare_result;
                $self->_current_txn(undef);
                unshift @{ $self->{'_transactions'} }, $recorded_tx;
                if ( $self->unrecognized eq 'exception' ) {
                    croak qq{Unrecognized request: $result};
                }
                elsif ( $self->unrecognized eq 'null' ) {
                    $tx->req->headers->header( 'X-MUA-Mockable-Request-Recognized'      => 0 );
                    $tx->req->headers->header( 'X-MUA-Mockable-Request-Match-Exception' => $result );
                    $tx->req->url->host('')->scheme('')->port( $self->server->url->port );
                }
                elsif ( $self->unrecognized eq 'fallback' ) {
                    $tx->on(
                        finish => sub {
                            my $self = shift;
                            $tx->req->headers->header( 'X-MUA-Mockable-Request-Recognized'      => 0 );
                            $tx->req->headers->header( 'X-MUA-Mockable-Request-Match-Exception' => $result );
                        }
                    );
                }
            }
        }
    );

    return $self;
}


sub _init_record {
    my $self = shift;

    $self->{'_events'}{'start'} = $self->on(
        start => sub {
            my ( $ua, $tx ) = @_;

            $tx->once(
                finish => sub {
                    my $tx  = shift;
                    push @{ $self->{'_transactions'} }, $tx;
                }
            );
        },
    );

    return $self;
}

sub _load_transactions {
    my ($self) = @_;

    my @transactions = $self->serializer->retrieve($self->file);

    return \@transactions;
}

# TODO: This doesn't work like it oughtta.
# # In record mode, write out the recorded file 
# sub DESTROY { 
#     my $self = shift;
#    
#     local($., $@, $!, $^E, $?);
# 
#     warn qq{In DESTROY. Launch: $self->{'_launchpid'}. Current: $$};
#     if ($self->_mode eq 'record') {
#         my $dir = (File::Spec->splitpath($self->file))[1];
#         
#         warn qq{"$dir" does not exist} unless -e $dir;
#         if ( ! -e $dir && warnings::enabled) {
#             carp qq{Cannot write output file: directory "$dir" does not exist};
#         }
#         $self->save($self->file);
#     }
# }
1;
