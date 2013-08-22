package AnyEvent::UserAgent;

# This module based on original AnyEvent::HTTP::Simple module by punytan
# (punytan@gmail.com): http://github.com/punytan/AnyEvent-HTTP-Simple

use Moo;

use AnyEvent::HTTP ();
use HTTP::Cookies ();
use HTTP::Request ();
use HTTP::Request::Common ();
use HTTP::Response ();


our $VERSION = '0.02';


has agent         => (is => 'rw', default => sub { $AnyEvent::HTTP::USERAGENT . ' AnyEvent-UserAgent/' . $VERSION });
has cookie_jar    => (is => 'rw', default => sub { HTTP::Cookies->new });
has max_redirects => (is => 'rw', default => sub { 5 });
has timeout       => (is => 'rw', default => sub { 30 });

sub request {
	my ($self, $req, $cb) = @_;

	$self->_request($req, sub {
		$self->_response($req, @_, $cb);
	});
}

sub get    { _make_request(GET    => @_) }
sub head   { _make_request(HEAD   => @_) }
sub put    { _make_request(PUT    => @_) }
sub delete { _make_request(DELETE => @_) }
sub post   { _make_request(POST   => @_) }

sub _make_request {
	my $cb   = pop();
	my $meth = shift();
	my $self = shift();

	no strict 'refs';
	$self->request(&{'HTTP::Request::Common::' . $meth}(@_), $cb);
}

sub _request {
	my ($self, $req, $cb) = @_;

	$req->headers->user_agent($self->agent);
	$self->cookie_jar->add_cookie_header($req);

	my $headers = $req->headers;

	delete($headers->{'::std_case'});

	my %opts = (
		timeout => $self->timeout,
		recurse => 0,
		headers => $headers,
		body    => $req->content,
	);

	AnyEvent::HTTP::http_request(
		$req->method,
		$req->uri,
		%opts,
		sub {
			$cb->(@_);
		}
	);
}

sub _redirect {
	my ($self, $req, $prev, $count, $cb) = @_;

	$self->_request($req, sub {
		$self->_response($req, @_, $prev, $count - 1, sub { return $cb->(@_); });
	});
}

sub _response {
	my $cb = pop();
	my ($self, $req, $body, $hdrs, $prev, $count) = @_;

	my $res = HTTP::Response->new(delete($hdrs->{Status}), delete($hdrs->{Reason}));

	$res->request($req);
	$res->previous($prev) if $prev;

	delete($hdrs->{URL});
	if (defined($hdrs->{HTTPVersion})) {
		$res->protocol('HTTP/' . delete($hdrs->{HTTPVersion}));
	}
	if (my $cookies = $hdrs->{'set-cookie'}) {
		local @_ = split(/,(\w+=)/, ',' . $cookies);
		shift();
		my @val;
		push(@val, join('', shift(), shift())) while @_;
		$hdrs->{'set-cookie'} = \@val;
	}
	if (keys(%$hdrs)) {
		$res->header(%$hdrs);
	}
	if (defined($body)) {
		$res->content_ref(\$body);
	}
	$self->cookie_jar->extract_cookies($res);

	if (grep { $_ == $res->code } (301, 302, 303, 307)) {
		$count //= $self->max_redirects;
		unless ($count) {
			return $cb->($res);
		}
		else {
			my $meth = $req->method eq 'HEAD' ? 'HEAD' : 'GET';
			my $uri  = $hdrs->{location};
			no strict 'refs';
			my $req = &{'HTTP::Request::Common::' . $meth}($uri);
			return $self->_redirect($req, $res, $count, sub { $cb->(@_); });
		}
	}
	else {
		return $cb->($res);
	}
}


1;


__END__

=head1 NAME

AnyEvent::UserAgent - AnyEvent::HTTP OO-wrapper

=head1 SYNOPSIS

    use AnyEvent::UserAgent;
    use Data::Dumper;

    my $ua = AnyEvent::UserAgent->new;
    my $cv = AE::cv;

    $ua->get('http://example.com/', sub {
        my ($res) = @_;
        print(Dumper($res, $ua->cookie_jar));
        $cv->send();
    });
    $cv->recv();

=head1 DESCRIPTION

AnyEvent::UserAgent is a OO-wrapper around L<AnyEvent::HTTP> with cookies
support by L<HTTP::Cookies>. Also request callback receives response as
L<HTTP::Response> object.

=head1 ATTRIBUTES

=head2 agent

The product token that is used to identify the user agent on the network. The
agent value is sent as the C<User-Agent> header in the requests.

=head2 cookie_jar

The cookie jar object to use. The only requirement is that the cookie jar object
must implement the C<extract_cookies($req)> and C<add_cookie_header($res)>
methods. These methods will then be invoked by the user agent as requests are
sent and responses are received. Normally this will be a L<HTTP::Cookies> object
or some subclass. Default cookie jar is the L<HTTP::Cookies> object.

=head2 timeout

The request timeout. See L<C<timeout>|AnyEvent::HTTP/timeout-seconds> in
L<AnyEvent::HTTP>. Default timeout is 30 seconds.

=head1 METHODS

=head2 new

    my $ua = AnyEvent::UserAgent->new;
    my $ua = AnyEvent::UserAgent->new(timeout => 60);

Constructor for the user agent. You can pass it either a hash or a hash
reference with attribute values.

=head2 get

    $ua->get('http://example.com/', sub { print($_[0]->code) });

This method is a wrapper for the L<C<HTTP::Request::Common::GET()>|HTTP::Request::Common/GET $url>.
The last argument must be a callback.

=head2 head

This method is a wrapper for the L<C<HTTP::Request::Common::HEAD()>|HTTP::Request::Common/HEAD $url>.
See L<C<get()>|/get>.

=head2 put

This method is a wrapper for the L<C<HTTP::Request::Common::PUT()>|HTTP::Request::Common/PUT $url>.
See L<C<get()>|/get>.

=head2 delete

This method is a wrapper for the L<C<HTTP::Request::Common::DELETE()>|HTTP::Request::Common/DELETE $url>.
See L<C<get()>|/get>.

=head2 post

    $ua->post('http://example.com/', [key => 'value'], sub { print($_[0]->code) });

This method is a wrapper for the L<C<HTTP::Request::Common::POST()>|HTTP::Request::Common/POST $url>.
The last argument must be a callback.

=head1 SEE ALSO

L<AnyEvent::HTTP>, L<HTTP::Cookies>, L<HTTP::Request::Common>, L<HTTP::Response>.

=head1 SUPPORT

=over 4

=item Repository

L<http://github.com/AdCampRu/anyevent-useragent>

=item Bug tracker

L<http://github.com/AdCampRu/anyevent-useragent/issues>

=back

=head1 AUTHOR

Denis Ibaev C<dionys@cpan.org> for AdCamp.ru.

=head1 CONTRIBUTORS

Andrey Khozov C<avkhozov@cpan.org>.

This module based on original L<AnyEvent::HTTP::Simple|http://github.com/punytan/AnyEvent-HTTP-Simple>
module by punytan C<punytan@gmail.com>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

See L<http://dev.perl.org/licenses/> for more information.

=cut
