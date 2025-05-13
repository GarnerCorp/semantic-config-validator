#!/bin/bash

set -e

if [ -n "$TRACE" ]; then
  set -x
fi

docker_compose="docker-compose.yml"
conf_check_output=$(mktemp)
project_root=$(pwd)
web_root=$(mktemp -d)
web_port=9001
web_pid=$(mktemp)

start_web_server() {
  (
    cd "$web_root"
    python3 -m http.server $web_port &
    echo $! > "$web_pid"
  )
  export CONFIG_SERVER=$(hostname -i):$web_port
}

stop_web_server() {
  if [ -s "$web_pid" ]; then
    kill $(cat "$web_pid")
  fi
}

neo4j_ready() {
  while ! curl -s 'http://localhost:7474' | grep -q '^{'; do sleep 1; done
}

check_config_unit() {
  config_group_prefix='config_group_'

  split config_unit --lines="$NUM_PARALLEL_CHECKS" "$config_group_prefix"

  for config_group in $(ls | grep "$config_group_prefix"); do
    cat "$config_group" | xargs docker compose up | tee -a "$conf_check_output"
  done
}

add_all_problem_matchers() {
  for matcher in "$PROBLEM_MATCHERS_PATH"/*; do echo "::add-matcher::$matcher"; done
}

fill_in_github_action_path() {
  perl -pe 's/\$GITHUB_ACTION_PATH/$ENV{GITHUB_ACTION_PATH}/g'
}

expand_github_action_path() {
  CONFIG_TESTER_HEALTH_ENDPOINT="$(echo "$CONFIG_TESTER_HEALTH_ENDPOINT" | fill_in_github_action_path)"
  VALIDATION_SCRIPT="$(echo "$VALIDATION_SCRIPT" | fill_in_github_action_path)"
  NEO4J_DOCKER_COMPOSE="$(echo "$NEO4J_DOCKER_COMPOSE" | fill_in_github_action_path)"
  TEMPLATE_DOCKER_COMPOSE="$(echo "$TEMPLATE_DOCKER_COMPOSE" | fill_in_github_action_path)"
  PROBLEM_MATCHERS_PATH="$(echo "$PROBLEM_MATCHERS_PATH" | fill_in_github_action_path)"
}

expand_github_action_path
add_all_problem_matchers
perl -pe 's/NEO4J_IMAGE/$ENV{NEO4J_IMAGE}/;s/NEO4J_CREDENTIALS/$ENV{NEO4J_CREDENTIALS}/' "$NEO4J_DOCKER_COMPOSE" > "$docker_compose"
docker pull $VALIDATOR_IMAGE &
pull_pid=$!

docker compose up -d neo4j &
start_web_server

cp "$VALIDATION_SCRIPT" "$web_root"/run-script

touch 'config_unit'
ip addr list
sleep 2
curl -v -f http://$CONFIG_SERVER || true

# Prepare docker-compose containers
for config_unit_path in "$project_root/$CONFIG_UNITS"/*/; do
  [ -z "$config_unit_path" ] && break

  unit=$(basename "$config_unit_path")
  (
    cd "$project_root/$CONFIG_UNITS/$unit/domain"
    tar czf "$web_root/$unit.tar.gz" .
  )

  UNIT="$unit" CONF_HOME="$config_unit_path/domain" \
  perl -pe '
    s{CONF_TEST}{$ENV{UNIT}};
    s{VALIDATOR_IMAGE}{$ENV{VALIDATOR_IMAGE}};
    s{CONFIG_UNIT}{$ENV{UNIT}};
    s{SUCCEEDING_WITH}{$ENV{CONFIG_TESTER_SUCCESS_RESULT}};
    s{PLACE_TO_HIT}{$ENV{CONFIG_TESTER_HEALTH_ENDPOINT}};
    s{STARTUP_ARGUMENTS}{$ENV{CONFIG_TESTER_STARTUP_ARGS}};
    s{CONF_HOME}{$ENV{CONF_HOME}};
    s{CONFIG_SERVER}{$ENV{CONFIG_SERVER}};
    s{READY_RESPONSE}{$ENV{CONFIG_TESTER_RESPONSE_READY}};
    s{TRACE_STATUS}{$ENV{TRACE}};
    ' "$TEMPLATE_DOCKER_COMPOSE" >> "$docker_compose"

  echo "$unit" >> 'config_unit'
done

if ! docker compose ps >/dev/null; then
  echo ::error title=Invalid Configuration::docker compose objected to the configuration
  (
    b='`'
    echo '# Error'
    echo '```sh'
    (docker compose ps >/dev/null || true) 2>&1
    echo '```'
    echo
    echo "<details><summary>$b$docker_compose$b</summary>"
    echo
    echo '```yml'
    cat "$docker_compose"
    echo '```'
    echo
    echo '</details>'
  ) >> "$GITHUB_STEP_SUMMARY"
  exit 15
fi

neo4j_ready
wait $pull_pid
check_config_unit

docker compose down
stop_web_server

if [ $(grep -c . config_unit) != $(egrep -c 'Config unit \S+ ok' "$conf_check_output") ]
then
  exit 1
fi
