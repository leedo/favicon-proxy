package FaviconProxy;

use CHI;
use AnyEvent::HTTP ();
use HTML::Parser;
use Plack::Util::Accessor qw{cache};
use Plack::Request;
use MIME::Base64 ();
use URI;

use parent 'Plack::Component';

sub prepare_app {
  my $self = shift;
  $self->{default} = MIME::Base64::decode_base64(join "", <DATA>);
  $self->{cache} = CHI->new(driver => "Memory", global => 1)
    unless defined $self->{cache};
}

sub not_found {
  my ($self, $status) = @_;
  $status ||= 404;
  return [$status, ["Content-Type", "image/png"], [$self->{default}]];
}

sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  my $url = $req->parameters->{url};

  if (!$url) {
    return $self->not_found(410);
  }

  my $domain = URI->new($url)->host;

  if (!$domain) {
    return $self->not_found;
  }

  my $info = $self->{cache}->get($domain);

  if ($info) {
    my ($image, @headers) = @$info;
    return [200, \@headers, [$image]];
  }

  return sub {
    my $respond = shift;
    AnyEvent::HTTP::http_get "http://$domain/favicon.ico", sub {
      my ($body, $headers) = @_;
      if ($headers->{Status} == 200) {
        my @headers = map {$_, $headers->{$_}} grep {/^[a-z]/} keys %$headers;
        $self->{cache}->set($domain, [$body, @headers]);
        $respond->([200, \@headers, [$body]]);
      }
      else {
        AnyEvent::HTTP::http_get $url, sub {
          my ($body, $headers) = @_;
          if ($headers->{Status} == 200 and $headers->{"content-type"} =~ m{/x?html$}) {
            my $url;
            my $parser = HTML::Parser->new(
              api_version => 3,
              start_h => [ sub {
                if ($_[0] eq "link" and $_[1]->{rel} eq "shortcut icon") {
                  $url = $_[1]->{href};
                  $_[2]->eof;
                }
              }, "tagname, attr, self" ],
            );
            $parser->parse($body);
            $parser->eof;

            if ($url) {
              AnyEvent::HTTP::http_get $url, sub {
                my ($body, $headers) = @_;
                if ($headers->{Status} == 200) {
                  my @headers = map {$_, $headers->{$_}} grep {/^[a-z]/} keys %$headers;
                  $self->{cache}->set($domain, [$body, @headers]);
                  $respond->([200, \@headers, [$body]]);
                }
                else {
                  $respond->($self->not_found);
                }
              };
            }
          }
          else {
            $respond->($self->not_found);
          }
        };
      }
    };
  };
}

1;

__DATA__
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsSAAALEgHS3X78AAACiElEQVQ4EaVTzU8TURCf2tJuS7tQtlRb6UKBIkQwkRRSEzkQgyEc6lkOKgcOph78Y+CgjXjDs2i44FXY9AMTlQRUELZapVlouy3d7kKtb0Zr0MSLTvL2zb75eL838xtTvV6H/xELBptMJojeXLCXyobnyog4YhzXYvmCFi6qVSfaeRdXdrfaU1areV5KykmX06rcvzumjY/1ggkR3Jh+bNf1mr8v1D5bLuvR3qDgFbvbBJYIrE1mCIoCrKxsHuzK+Rzvsi29+6DEbTZz9unijEYI8ObBgXOzlcrx9OAlXyDYKUCzwwrDQx1wVDGg089Dt+gR3mxmhcUnaWeoxwMbm/vzDFzmDEKMMNhquRqduT1KwXiGt0vre6iSeAUHNDE0d26NBtAXY9BACQyjFusKuL2Ry+IPb/Y9ZglwuVscdHaknUChqLF/O4jn3V5dP4mhgRJgwSYm+gV0Oi3XrvYB30yvhGa7BS70eGFHPoTJyQHhMK+F0ZesRVVznvXw5Ixv7/C10moEo6OZXbWvlFAF9FVZDOqEABUMRIkMd8GnLwVWg9/RkJF9sA4oDfYQAuzzjqzwvnaRUFxn/X2ZlmGLXAE7AL52B4xHgqAUqrC1nSNuoJkQtLkdqReszz/9aRvq90NOKdOS1nch8TpL555WDp49f3uAMXhACRjD5j4ykuCtf5PP7Fm1b0DIsl/VHGezzP1KwOiZQobFF9YyjSRYQETRENSlVzI8iK9mWlzckpSSCQHVALmN9Az1euDho9Xo8vKGd2rqooA8yBcrwHgCqYR0kMkWci08t/R+W4ljDCanWTg9TJGwGNaNk3vYZ7VUdeKsYJGFNkfSzjXNrSX20s4/h6kB81/271ghG17l+rPTAAAAAElFTkSuQmCC
