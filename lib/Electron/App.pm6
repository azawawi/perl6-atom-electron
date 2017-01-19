=begin pod
  This is the screen API wrapper which is described in
  https://github.com/atom/electron/blob/master/docs/api/app.md

  TODO implement remaining parts of Electron::App
=end pod
unit class Electron::App;

use File::Which;
use JSON::RPC::Client;
use LWP::Simple;

has $!electron_process;
has @!listeners;

# Singleton instance
my Electron::App $instance;

# The JSON RPC client
my JSON::RPC::Client $json-rpc;

# No constructor allowed
method new {
  !!!
}

=begin pod
The singleton instance of the Electron App.
Please note that App.new will die by design
=end pod
method instance {
  if ! $instance.defined {
    $instance = Electron::App.bless;
    $instance.initialize;
  }
  $instance;
}

=begin pod
The JSON RPC Client
=end pod
method json-rpc {
  return $json-rpc;
}

=begin pod
Internal method to initialize electron process along with JSON RPC client
=end pod
submethod initialize {
  unless $!electron_process {
    fail("Cannot find electron in PATH") unless which('electron');

    # Find Electron/main_app folder in resources
    my $app_path = %?RESOURCES{"main_app"};
    fail("Cannot find electron main app in resources") unless $app_path.defined;

    # Start the electron main process
    $!electron_process = Proc::Async.new( "electron", $app_path );
    $!electron_process.start;

    # Try to create a JSON RPC client for MAX_TRIES times
    my constant MAX_TRIES = 3;
    my constant RETRY_TIMEOUT = 0.5;
    unless $json-rpc {
      for 1..MAX_TRIES {
        # Create json rpc client
        $json-rpc = JSON::RPC::Client.new(
          transport => sub (Str :$json, Bool :$get_response) {
            my $t = LWP::Simple.post(
              'http://127.0.0.1:3333',
              { 'Content-Type' => 'application/json' },
              $json
            );
            return $t.decode('utf-8');
          }
        );

        # We're done if the electron main process json rpc server pongs back
        last if $json-rpc.ping eq 'pong';

        CATCH {
          default {
            # We failed... Retry after timeout
            sleep RETRY_TIMEOUT;
          }
        }
      }
    }
  }
}

=begin pod
Destroy the singleton App by quitting it, sleeping a bit and
then force killing the electron process
=end pod
method destroy {
  $json-rpc.App-quit;
  sleep 0.5;
  if $!electron_process.defined {
    $!electron_process.kill(SIGTERM);
  }
}

=begin pod
Start processing and dispatching events. It also blocks the current thread.
=end pod
method run {

  loop {
    # Process pending events indefinity
    my $o = $.json-rpc.get-pending-events;
    for @($o<events>) -> $event {
      for @!listeners -> $listener {
        next if $listener<id>.defined && $listener<id> != $event<id>;
        next if $listener<name> ne $event<name>;
        $listener<listener>();
      }
    }

    # Sleep a bit to prevent 100% CPU usage
    sleep 0.05;
  }
}

=begin pod
Registers an event listener
=end pod
method on(:$name, :$id, :$listener) {
  @!listeners.push({
    "id"        => $id,
    "name"      => $name,
    "listener"  => $listener
  });
}
