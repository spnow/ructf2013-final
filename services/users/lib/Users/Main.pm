package Users::Main;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw/sha1_sum hmac_sha1_sum secure_compare b64_encode b64_decode/;
use Mango::BSON ':bson';

sub index {
  my $self = shift;
  my ($session, $sign) = split '!', $self->cookie('session');
  if ($sign && secure_compare($sign, hmac_sha1_sum $session, $self->app->secret)) {
    my $json = Mojo::JSON->new;
    my $user = $json->decode(b64_decode $session);
    $self->stash(ok => 1);
    $self->stash(fname => $user->{first_name});
    $self->stash(lname => $user->{last_name});
  }
  $self->render();
}

sub logout {
  my $self = shift;
  $self->cookie(session => '', {expires => 1});
  $self->redirect_to('index');
}

sub register {
  my $self = shift;
  $self->render_later;
  my $db = $self->mango->db('users');
  my $user;

  if ($self->req->is_xhr) {
    my $json = $self->req->json;
    return $self->render_json($self->_error(0, 'invalid input')) unless $json;
    my $pointer = Mojo::JSON::Pointer->new;
    for my $field (qw/login password first_name last_name language/) {
      return $self->render_json($self->_error(0, 'invalid input'))
        unless $pointer->contains($json, "/$field");
      $user->{$field} = $pointer->get($json, "/$field");
    }
  } else {
    my $params = $self->req->params->to_hash;
    ## TODO: check input parameters
    my @fields = qw/login password first_name last_name language/;
    @{$user}{@fields} = @{$params}{@fields};
  }
  $user->{salt} = $self->_salt;
  $user->{hash} = sha1_sum delete($user->{password}) . $user->{salt};
  $db->collection('user')->insert(
    $user => sub {
      my ($collection, $err, $uid) = @_;
      if ($err) {
        given ($err) {
          when (/E11000/) {
            return $self->req->is_xhr
              ? $self->render_json($self->_error(1, 'login already used'))
              : $self->render_exception;
          }
          default {
            $self->app->log->error("Error while insert user: $err");
            return $self->req->is_xhr
              ? $self->render_json($self->_error(-1, 'internal error'))
              : $self->render_exception;
          }
        }
      }
      if ($self->req->is_xhr) {
        return $self->render_json({status => 'OK', uid => $uid});
      } else {
        $self->stash(register => 1);
        return $self->redirect_to('sign_in');
      }
    });
}

sub login {
  my $self = shift;
  $self->render_later;
  my $db = $self->mango->db('users');
  my ($login, $password);

  if ($self->req->is_xhr) {
    my $json = $self->req->json;
    return $self->render_json($self->_error(0, 'invalid input')) unless $json;
    my $pointer = Mojo::JSON::Pointer->new;
    for my $field (qw/login password/) {
      return $self->render_json($self->_error(0, 'invalid input'))
        unless $pointer->contains($json, "/$field");
    }
    ($login, $password) = ($json->{login}, $json->{password});
  } else {
    my $params = $self->req->params->to_hash;
    ## TODO: check input parameters
    my @fields = qw/login password/;
    ($login, $password) = @{$params}{@fields};
  }
  $db->collection('user')->find_one(
    {login => $login} => sub {
      my ($collection, $err, $user) = @_;
      if ($err) {
        $self->app->log->error("Error while find_one user: $err");
        return $self->req->is_xhr
          ? $self->render_json($self->_error(-1, 'internal error'))
          : $self->render_exception;
      }
      unless ($user) {
        return $self->req->is_xhr
          ? $self->render_json($self->_error(3, 'invalid login or password'))
          : $self->render_exception;
      }
      if ($user->{hash} eq sha1_sum $password . $user->{salt}) {
        my $response;
        @{$response}{'uid', 'first_name', 'last_name', 'language'} =
          @{$user}{'_id',   'first_name', 'last_name', 'language'};
        my $json    = Mojo::JSON->new;
        my $data    = b64_encode($json->encode($response), '');
        my $session = $data . '!' . hmac_sha1_sum $data, $self->app->secret;
        $self->cookie(session => $session);
        return $self->req->is_xhr
          ? $self->render_json({status => 'OK'})
          : $self->redirect_to('index');
      } else {
        return $self->req->is_xhr
          ? $self->render_json($self->_error(3, 'invalid login or password'))
          : $self->render_exception;
      }
    });
}

sub user {
  my $self = shift;
  $self->render_later;
  my $db = $self->mango->db('users');
  my $cookie;

  if ($self->req->is_xhr) {
    my $json = $self->req->json;
    return $self->render_json($self->_error(0, 'invalid input')) unless $json;
    my $pointer = Mojo::JSON::Pointer->new;
    for my $field (qw/session/) {
      return $self->render_json($self->_error(0, 'invalid input'))
        unless $pointer->contains($json, "/$field");
    }
    $cookie = $json->{session};
  }
  my ($session, $sign) = split '!', $cookie;
  if ($sign && secure_compare($sign, hmac_sha1_sum $session, $self->app->secret)) {
    my $json = Mojo::JSON->new;
    my $user = $json->decode(b64_decode $session);
    $user->{status} = 'OK';
    return $self->render_json($user);
  } else {
    return $self->render_json($self->_error(5, 'invalid sign, possible hack attempt'));
  }
}

sub _salt {
  return sha1_sum rand . $$;
}

sub _error {
  my ($self, $code, $str) = @_;
  return {status => 'FAIL', error => {code => $code, str => $str}};
}

1;