#!/bin/bash

set -e

docker_compose="docker-compose.yml"
conf_check_output=$(mktemp)
project_root=$(pwd)

neo4j_ready() {
  while ! curl -s 'http://localhost:7474' | grep -q '^{'; do sleep 1; done
}

check_config_unit() {
  config_group_prefix='config_group_'

  split config_unit --lines="$NUM_PARALLEL_CHECKS" "$config_group_prefix"

  for config_group in $(ls | grep "$config_group_prefix"); do
    cat "$config_group" | xargs docker-compose up | tee "$conf_check_output"
  done
}

add_all_problem_matchers() {
  for matcher in "$PROBLEM_MATCHERS_PATH"/*; do echo "::add-matcher::$matcher"; done
}

add_all_problem_matchers
perl -pne "s{NEO4J_CREDENTIALS}{$NEO4J_CREDENTIALS}" "$NEO4J_DOCKER_COMPOSE" > "$docker_compose"

docker-compose up -d neo4j
neo4j_ready

touch 'config_unit'

# Prepare docker-compose containers
for config_unit_path in "$project_root/$CONFIG_UNITS"/*/; do
  [ -z "$config_unit_path" ] && break

  unit=$(basename "$config_unit_path")

  UNIT="$unit" CONF_HOME="$config_unit_path/domain" \
  perl -pne '
    s{CONF_TEST}{$ENV{UNIT}};
    s{VALIDATOR_IMAGE}{$ENV{VALIDATOR_IMAGE}};
    s{CONFIG_UNIT}{$ENV{UNIT}};
    s{SUCCEEDING_WITH}{$ENV{CONFIG_TESTER_SUCCESS_RESULT}};
    s{PLACE_TO_HIT}{$ENV{CONFIG_TESTER_HEALTH_ENDPOINT}};
    s{STARTUP_ARGUMENTS}{$ENV{CONFIG_TESTER_STARTUP_ARGS}};
    s{CONF_HOME}{$ENV{CONF_HOME}};
    s{VALIDATION_SCRIPT}{$ENV{VALIDATION_SCRIPT}};
    s{READY_RESPONSE}{$ENV{CONFIG_TESTER_RESPONSE_READY}};
    ' "$TEMPLATE_DOCKER_COMPOSE" >> "$docker_compose"

  echo "$unit" >> 'config_unit'
done

check_config_unit

docker-compose down

if [ $(grep -c . config_unit) != $(egrep -c 'Config unit \S+ ok' "$conf_check_output") ]
then
  exit 1
fi