#!/bin/bash
set -e

backend_err=$(mktemp)
pid_file=$(mktemp)

show_logs() {
  perl -e '
  my $state=0;
  while (<>) {
    if ($state==1) {
      if (/^\s*at /) {
        $state=0;
      } elsif (/\w/) {
        s/($)/ ### Error Explanation ###$1/;
        $state=0;
      }
    } elsif ($state==0) {
      $state=1 if m{Guice/Error};
    }
    print;
  }' "$backend_err"
}

backend_ready() {
  backend_pid=$(cat $pid_file)

  while ! curl -s "$BACKEND_HEALTH_ENDPOINT" | grep -q "$CONFIG_TESTER_RESPONSE_READY"; do
    if [ ! -d "/proc/$backend_pid" ]; then
      show_logs
      exit 1
    fi

    sleep 1
  done
}

start_backend(){
  /app/docker-entrypoint.sh $BACKEND_STARTUP_ARGS > /dev/null 2> "$backend_err" &

  echo "$!" > "$pid_file"
  backend_ready
}

start_backend

BACKEND_HEALTH=$(curl -s "$BACKEND_HEALTH_ENDPOINT")

if [ "$BACKEND_HEALTH" = "$BACKEND_SUCCESS_RESULT" ]; then
  echo "Config unit $UNIT ok"
  exit 0
fi

echo "<header>Config Unit $Unit is broken</header>"
echo "$BACKEND_HEALTH" | tr '\n' ' '

show_logs

exit 1
